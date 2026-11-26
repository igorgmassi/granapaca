using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using YamlDotNet.Serialization;
using YamlDotNet.Serialization.NamingConventions;

namespace GranaPaCa.Modules.Categorization;

internal sealed record ProfileRuleTemplate(
    string TemplateId,
    string SourceType,
    string SourceId,
    string Name,
    string Explanation,
    string MatchPattern,
    string? Category,
    string? Essentiality,
    string? Brand,
    int Priority);

internal sealed record ProfileEntry(
    string Id,
    string Kind,
    string Label,
    string Description,
    IReadOnlyList<ProfileRuleTemplate> Rules);

internal sealed record ProfileCatalogSnapshot(
    IReadOnlyList<ProfileEntry> Occupations,
    IReadOnlyList<ProfileEntry> HomeTraits,
    IReadOnlyList<ProfileEntry> TransportModes);

internal sealed class ProfileCatalog
{
    private readonly Dictionary<string, ProfileEntry> _occupations;
    private readonly Dictionary<string, ProfileEntry> _homeTraits;
    private readonly Dictionary<string, ProfileEntry> _transportModes;

    public ProfileCatalog(IConfiguration configuration, ILogger<ProfileCatalog> logger)
    {
        _occupations = BuildDefaultOccupations().ToDictionary(p => p.Id, StringComparer.OrdinalIgnoreCase);
        _homeTraits = BuildDefaultHomeTraits().ToDictionary(p => p.Id, StringComparer.OrdinalIgnoreCase);
        _transportModes = BuildDefaultTransportModes().ToDictionary(p => p.Id, StringComparer.OrdinalIgnoreCase);

        LoadYamlOverrides(configuration, logger);
    }

    public ProfileCatalogSnapshot GetCatalog() =>
        new(
            _occupations.Values.OrderBy(p => p.Label, StringComparer.OrdinalIgnoreCase).ToList(),
            _homeTraits.Values.OrderBy(p => p.Label, StringComparer.OrdinalIgnoreCase).ToList(),
            _transportModes.Values.OrderBy(p => p.Label, StringComparer.OrdinalIgnoreCase).ToList());

    public IReadOnlyList<ProfileRuleTemplate> PreviewRules(
        IReadOnlyCollection<string> occupations,
        IReadOnlyCollection<string> homeTraits,
        IReadOnlyCollection<string> transportModes)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<ProfileRuleTemplate>();

        void Collect(IReadOnlyCollection<string> ids, Dictionary<string, ProfileEntry> map)
        {
            foreach (var rawId in ids)
            {
                if (string.IsNullOrWhiteSpace(rawId))
                {
                    continue;
                }

                if (!map.TryGetValue(rawId.Trim(), out var entry))
                {
                    continue;
                }

                foreach (var rule in entry.Rules)
                {
                    if (seen.Add(rule.TemplateId))
                    {
                        result.Add(rule);
                    }
                }
            }
        }

        // Order matters deterministically: occupation (work) -> transport -> home traits.
        Collect(occupations, _occupations);
        Collect(transportModes, _transportModes);
        Collect(homeTraits, _homeTraits);

        return result
            .OrderBy(r => r.Priority)
            .ThenBy(r => r.TemplateId, StringComparer.Ordinal)
            .ToList();
    }

    private void LoadYamlOverrides(IConfiguration configuration, ILogger<ProfileCatalog> logger)
    {
        var directory = ResolveProfilesDirectory(configuration["Profiles:Directory"]);
        if (directory is null || !Directory.Exists(directory))
        {
            return;
        }

        var deserializer = new DeserializerBuilder()
            .WithNamingConvention(UnderscoredNamingConvention.Instance)
            .IgnoreUnmatchedProperties()
            .Build();

        var yamlFiles = Directory.EnumerateFiles(directory, "*.yml", SearchOption.AllDirectories)
            .Concat(Directory.EnumerateFiles(directory, "*.yaml", SearchOption.AllDirectories))
            .OrderBy(path => path, StringComparer.Ordinal);

        foreach (var file in yamlFiles)
        {
            try
            {
                var content = File.ReadAllText(file);
                var doc = deserializer.Deserialize<YamlProfileDocument?>(content);
                if (doc is null || string.IsNullOrWhiteSpace(doc.Id) || string.IsNullOrWhiteSpace(doc.Kind))
                {
                    continue;
                }

                var kind = doc.Kind.Trim().ToLowerInvariant();
                var target = kind switch
                {
                    "occupation" => _occupations,
                    "home_trait" or "hometrait" => _homeTraits,
                    "transport_mode" or "transportmode" or "transport" => _transportModes,
                    _ => null
                };

                if (target is null)
                {
                    continue;
                }

                var basePriority = kind switch
                {
                    "occupation" => 200,
                    "transport_mode" or "transportmode" or "transport" => 210,
                    _ => 220
                };

                var rules = new List<ProfileRuleTemplate>();
                var index = 0;
                foreach (var rule in doc.Rules ?? [])
                {
                    index++;
                    if (string.IsNullOrWhiteSpace(rule.MatchPattern) ||
                        string.IsNullOrWhiteSpace(rule.Name) ||
                        string.IsNullOrWhiteSpace(rule.Explanation))
                    {
                        continue;
                    }

                    if (!TaxonomyConstants.TryNormalizeCategory(rule.Category, out var category) ||
                        !TaxonomyConstants.TryNormalizeEssentiality(rule.Essentiality, out var essentiality))
                    {
                        logger.LogWarning("Skipped invalid YAML profile rule in {FileName}.", Path.GetFileName(file));
                        continue;
                    }

                    var templateId = string.IsNullOrWhiteSpace(rule.Id)
                        ? $"{doc.Id.Trim().ToLowerInvariant()}-rule-{index}"
                        : rule.Id.Trim().ToLowerInvariant();

                    rules.Add(new ProfileRuleTemplate(
                        templateId,
                        kind,
                        doc.Id.Trim().ToLowerInvariant(),
                        rule.Name.Trim(),
                        rule.Explanation.Trim(),
                        rule.MatchPattern.Trim(),
                        category,
                        essentiality,
                        string.IsNullOrWhiteSpace(rule.Brand) ? null : rule.Brand.Trim(),
                        rule.Priority ?? (basePriority + index)));
                }

                var entry = new ProfileEntry(
                    doc.Id.Trim().ToLowerInvariant(),
                    kind,
                    string.IsNullOrWhiteSpace(doc.Label) ? doc.Id.Trim() : doc.Label.Trim(),
                    string.IsNullOrWhiteSpace(doc.Description) ? string.Empty : doc.Description.Trim(),
                    rules);

                target[entry.Id] = entry;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to parse YAML profile file {FileName}; keeping defaults.", Path.GetFileName(file));
            }
        }
    }

    private static string? ResolveProfilesDirectory(string? configuredPath)
    {
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            return Path.GetFullPath(configuredPath);
        }

        var current = new DirectoryInfo(Directory.GetCurrentDirectory());
        for (var depth = 0; depth < 6 && current is not null; depth++)
        {
            var candidate = Path.Combine(current.FullName, "profiles");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            current = current.Parent;
        }

        return null;
    }

    private static IReadOnlyList<ProfileEntry> BuildDefaultOccupations() =>
    [
        new ProfileEntry(
            "desenvolvedor",
            "occupation",
            "Desenvolvedor(a) de software",
            "Ajusta internet, ferramentas de código e equipamentos técnicos para quem trabalha com tecnologia.",
            [
                new ProfileRuleTemplate(
                    "dev-internet",
                    "occupation",
                    "desenvolvedor",
                    "Internet de trabalho",
                    "Para quem trabalha com desenvolvimento, internet estável é ferramenta essencial de trabalho.",
                    "internet|fibra|banda larga",
                    "services",
                    "essential",
                    null,
                    201),
                new ProfileRuleTemplate(
                    "dev-cloud-tools",
                    "occupation",
                    "desenvolvedor",
                    "Nuvem e ferramentas técnicas",
                    "Serviços de nuvem, domínios e licenças apoiam diretamente a rotina de desenvolvimento.",
                    "github|aws|cloud|jetbrains|dominio|hosting|software",
                    "services",
                    "important",
                    null,
                    202),
                new ProfileRuleTemplate(
                    "dev-hardware",
                    "occupation",
                    "desenvolvedor",
                    "Equipamentos de informática",
                    "Notebook e periféricos são investimentos importantes para o trabalho técnico.",
                    "notebook|teclado|monitor|informatica",
                    "shopping",
                    "important",
                    null,
                    203),
                new ProfileRuleTemplate(
                    "dev-education",
                    "occupation",
                    "desenvolvedor",
                    "Livros e cursos técnicos",
                    "Atualização técnica contínua é importante na área de tecnologia.",
                    "livraria|curso|treinamento|certificacao",
                    "education",
                    "important",
                    null,
                    204)
            ]),
        new ProfileEntry(
            "motorista-de-app",
            "occupation",
            "Motorista de aplicativo",
            "Trata combustível, manutenção veicular e dados móveis como despesas essenciais do trabalho.",
            [
                new ProfileRuleTemplate(
                    "driver-fuel",
                    "occupation",
                    "motorista-de-app",
                    "Combustível para trabalho",
                    "Para motorista de aplicativo, combustível é custo essencial da operação diária.",
                    "posto|combustivel|gasolina|etanol|gnv|abastecimento",
                    "transport",
                    "essential",
                    null,
                    201),
                new ProfileRuleTemplate(
                    "driver-maintenance",
                    "occupation",
                    "motorista-de-app",
                    "Manutenção e proteção do veículo",
                    "Manter o veículo rodando em segurança é gasto essencial para trabalhar.",
                    "oficina|mecanica|borracharia|lava jato|seguro auto|estacionamento|pedagio",
                    "transport",
                    "essential",
                    null,
                    202),
                new ProfileRuleTemplate(
                    "driver-mobile",
                    "occupation",
                    "motorista-de-app",
                    "Telefonia e dados móveis",
                    "Dados móveis e telefonia são essenciais para aceitar corridas na rua.",
                    "telefone|celular|recarga|plano movel",
                    "services",
                    "essential",
                    null,
                    203)
            ]),
        new ProfileEntry(
            "designer",
            "occupation",
            "Designer",
            "Prioriza softwares criativos, internet rápida e equipamentos de criação.",
            [
                new ProfileRuleTemplate(
                    "designer-software",
                    "occupation",
                    "designer",
                    "Softwares de criação",
                    "Ferramentas de design e bancos criativos são essenciais na rotina de produção.",
                    "adobe|figma|canva|creative|banco de imagens",
                    "services",
                    "essential",
                    null,
                    201),
                new ProfileRuleTemplate(
                    "designer-internet",
                    "occupation",
                    "designer",
                    "Internet de alta velocidade",
                    "Enviar e revisar arquivos pesados exige conexão estável como gasto essencial.",
                    "internet|fibra|banda larga",
                    "services",
                    "essential",
                    null,
                    202),
                new ProfileRuleTemplate(
                    "designer-hardware",
                    "occupation",
                    "designer",
                    "Equipamentos criativos",
                    "Equipamentos e materiais gráficos são importantes para entregas de design.",
                    "notebook|monitor|mesa digitalizadora|papelaria",
                    "shopping",
                    "important",
                    null,
                    203)
            ]),
        new ProfileEntry(
            "estudante",
            "occupation",
            "Estudante",
            "Coloca ensino, materiais didáticos, internet e deslocamento de estudo como essenciais.",
            [
                new ProfileRuleTemplate(
                    "student-education",
                    "occupation",
                    "estudante",
                    "Formação e material didático",
                    "Para estudantes, mensalidades, livros e cursos são despesas essenciais.",
                    "faculdade|universidade|escola|curso|livraria|apostila|papelaria",
                    "education",
                    "essential",
                    null,
                    201),
                new ProfileRuleTemplate(
                    "student-transport",
                    "occupation",
                    "estudante",
                    "Deslocamento para aulas",
                    "Transporte diário até o local de estudo entra como gasto essencial.",
                    "onibus|metro|bilhete unico|passagem|transporte",
                    "transport",
                    "essential",
                    null,
                    202),
                new ProfileRuleTemplate(
                    "student-internet",
                    "occupation",
                    "estudante",
                    "Internet para estudos",
                    "Acesso à internet é essencial para aulas, pesquisas e entregas acadêmicas.",
                    "internet|fibra",
                    "services",
                    "essential",
                    null,
                    203)
            ]),
        new ProfileEntry(
            "professor",
            "occupation",
            "Professor(a)",
            "Destaca livros, material didático, internet e cuidados preventivos de saúde como essenciais.",
            [
                new ProfileRuleTemplate(
                    "teacher-materials",
                    "occupation",
                    "professor",
                    "Livros e material didático",
                    "Livros e materiais de apoio são essenciais para preparar e ministrar aulas.",
                    "livraria|livro|papelaria|curso|didatico",
                    "education",
                    "essential",
                    null,
                    201),
                new ProfileRuleTemplate(
                    "teacher-internet",
                    "occupation",
                    "professor",
                    "Internet para planejamento",
                    "Conexão confiável é essencial para pesquisa, planejamento e aulas.",
                    "internet|fibra",
                    "services",
                    "essential",
                    null,
                    202),
                new ProfileRuleTemplate(
                    "teacher-health",
                    "occupation",
                    "professor",
                    "Cuidados preventivos de saúde",
                    "Cuidados de saúde e farmácia são essenciais para sustentar a rotina docente.",
                    "farmacia|clinica|fonoaudiologia|medico",
                    "health",
                    "essential",
                    null,
                    203)
            ])
    ];

    private static IReadOnlyList<ProfileEntry> BuildDefaultHomeTraits() =>
    [
        new ProfileEntry(
            "casa-sozinho",
            "home_trait",
            "Moro sozinho(a)",
            "Separa compras básicas de mercado (essenciais) de refeições prontas ou delivery (flexíveis).",
            [
                new ProfileRuleTemplate(
                    "home-solo-market",
                    "home_trait",
                    "casa-sozinho",
                    "Mercado e padaria da casa",
                    "Compras básicas de alimentação doméstica são essenciais.",
                    "supermercado|mercado|hortifruti|feira|padaria",
                    "food",
                    "essential",
                    null,
                    221),
                new ProfileRuleTemplate(
                    "home-solo-delivery",
                    "home_trait",
                    "casa-sozinho",
                    "Restaurantes e delivery",
                    "Refeições fora de casa ou por aplicativo entram como gasto flexível.",
                    "restaurante|ifood|delivery|lanchonete",
                    "food",
                    "flexible",
                    null,
                    222)
            ]),
        new ProfileEntry(
            "casa-familia",
            "home_trait",
            "Moro com família ou parceiro(a)",
            "Marca abastecimento da casa e contas fixas da moradia como essenciais.",
            [
                new ProfileRuleTemplate(
                    "home-family-market",
                    "home_trait",
                    "casa-familia",
                    "Abastecimento da casa",
                    "Compras de supermercado e feira são essenciais para manter a casa abastecida.",
                    "supermercado|atacadao|atacarejo|mercado|hortifruti|acougue",
                    "food",
                    "essential",
                    null,
                    221),
                new ProfileRuleTemplate(
                    "home-family-housing",
                    "home_trait",
                    "casa-familia",
                    "Contas fixas da moradia",
                    "Despesas fixas da residência compartilhada são essenciais.",
                    "aluguel|condominio|conta de luz|energia|agua|gas",
                    "housing",
                    "essential",
                    null,
                    222)
            ]),
        new ProfileEntry(
            "casa-filhos",
            "home_trait",
            "Tenho filhos",
            "Trata escola, creche e cuidados de saúde infantil como essenciais.",
            [
                new ProfileRuleTemplate(
                    "home-kids-education",
                    "home_trait",
                    "casa-filhos",
                    "Escola e material escolar",
                    "Educação e cuidados escolares dos filhos são despesas essenciais.",
                    "escola|creche|bercario|material escolar|uniforme",
                    "education",
                    "essential",
                    null,
                    221),
                new ProfileRuleTemplate(
                    "home-kids-health",
                    "home_trait",
                    "casa-filhos",
                    "Saúde e farmácia infantil",
                    "Farmácia, consultas pediátricas e cuidados infantis são essenciais.",
                    "farmacia|pediatra|clinica|vacina|fralda",
                    "health",
                    "essential",
                    null,
                    222)
            ]),
        new ProfileEntry(
            "casa-pets",
            "home_trait",
            "Tenho pets",
            "Garante que ração e cuidados veterinários entrem como essenciais.",
            [
                new ProfileRuleTemplate(
                    "home-pets-care",
                    "home_trait",
                    "casa-pets",
                    "Ração e veterinário",
                    "Ração e cuidados veterinários são despesas essenciais para quem tem pets.",
                    "pet shop|petshop|veterinario|racao|clinica vet",
                    "other",
                    "essential",
                    null,
                    221)
            ])
    ];

    private static IReadOnlyList<ProfileEntry> BuildDefaultTransportModes() =>
    [
        new ProfileEntry(
            "transporte-carro-moto",
            "transport_mode",
            "Carro ou moto próprios",
            "Coloca combustível, oficina, pedágio e estacionamento como essenciais.",
            [
                new ProfileRuleTemplate(
                    "transport-own-vehicle",
                    "transport_mode",
                    "transporte-carro-moto",
                    "Combustível e manutenção do veículo",
                    "Quem depende de carro ou moto próprios no dia a dia tem combustível e manutenção como essenciais.",
                    "posto|combustivel|gasolina|etanol|oficina|estacionamento|pedagio|ipva|seguro auto",
                    "transport",
                    "essential",
                    null,
                    211)
            ]),
        new ProfileEntry(
            "transporte-publico",
            "transport_mode",
            "Transporte público",
            "Trata ônibus e metrô como essenciais e corridas eventuais de aplicativo como flexíveis.",
            [
                new ProfileRuleTemplate(
                    "transport-public",
                    "transport_mode",
                    "transporte-publico",
                    "Passagens de transporte público",
                    "Ônibus, metrô e trem formam o deslocamento essencial do cotidiano.",
                    "metro|onibus|trem|bilhete unico|cartao transporte|passagem",
                    "transport",
                    "essential",
                    null,
                    211),
                new ProfileRuleTemplate(
                    "transport-public-apps",
                    "transport_mode",
                    "transporte-publico",
                    "Corridas eventuais por aplicativo",
                    "Com transporte público como principal meio, corridas por aplicativo ficam como flexíveis.",
                    "corrida|uber|99|99app|99pop",
                    null,
                    "flexible",
                    null,
                    212)
            ]),
        new ProfileEntry(
            "transporte-aplicativo",
            "transport_mode",
            "Transporte por aplicativo",
            "Classifica corridas por aplicativo como gasto importante de mobilidade.",
            [
                new ProfileRuleTemplate(
                    "transport-app-rides",
                    "transport_mode",
                    "transporte-aplicativo",
                    "Corridas por aplicativo",
                    "Para quem se desloca principalmente por aplicativo, corridas são um gasto importante.",
                    "corrida|uber|99|99app|99pop|taxi",
                    "transport",
                    "important",
                    null,
                    211)
            ]),
        new ProfileEntry(
            "transporte-bicicleta-ape",
            "transport_mode",
            "Bicicleta ou a pé",
            "Coloca manutenção da bicicleta como essencial e corridas esporádicas como flexíveis.",
            [
                new ProfileRuleTemplate(
                    "transport-bike",
                    "transport_mode",
                    "transporte-bicicleta-ape",
                    "Manutenção da bicicleta",
                    "Manutenção da bicicleta é essencial para quem a usa como transporte principal.",
                    "bicicleta|bicicletaria|bike|ciclo",
                    "transport",
                    "essential",
                    null,
                    211),
                new ProfileRuleTemplate(
                    "transport-bike-apps",
                    "transport_mode",
                    "transporte-bicicleta-ape",
                    "Corridas esporádicas",
                    "Corridas ocasionais em dias de chuva ou longas distâncias entram como flexíveis.",
                    "corrida|uber|99|99app|99pop",
                    null,
                    "flexible",
                    null,
                    212)
            ])
    ];

    private sealed class YamlProfileDocument
    {
        public string? Id { get; set; }
        public string? Kind { get; set; }
        public string? Label { get; set; }
        public string? Description { get; set; }
        public List<YamlProfileRule>? Rules { get; set; }
    }

    private sealed class YamlProfileRule
    {
        public string? Id { get; set; }
        public string? Name { get; set; }
        public string? Explanation { get; set; }
        public string? MatchPattern { get; set; }
        public string? Category { get; set; }
        public string? Essentiality { get; set; }
        public string? Brand { get; set; }
        public int? Priority { get; set; }
    }
}
