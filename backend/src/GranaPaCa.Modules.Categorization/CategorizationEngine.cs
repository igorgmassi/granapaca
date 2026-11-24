using Dapper;
using GranaPaCa.Modules.Categorization.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Categorization;

internal sealed class CategorizationEngine(NpgsqlDataSource dataSource) : ICategorizationEngine
{
    private static readonly IReadOnlyList<SystemRuleEntry> SystemDictionary =
    [
        new(
            "Moradia fixa",
            "aluguel|condominio|iptu|financiamento imobiliario",
            "housing",
            "essential",
            "Classificada como Moradia (essencial) pelo dicionário do sistema."),
        new(
            "Contas básicas da casa",
            "conta de luz|energia|eletricidade|agua|saneamento|conta de gas|gas encanado",
            "housing",
            "essential",
            "Classificada como Moradia (essencial) pelo dicionário do sistema."),
        new(
            "Mercado e padaria",
            "supermercado|hipermercado|mercado|atacadao|atacarejo|hortifruti|acougue|feira|padaria",
            "food",
            "essential",
            "Classificada como Alimentação (essencial) pelo dicionário do sistema."),
        new(
            "Restaurante e refeições fora",
            "restaurante|lanchonete|pizzaria|hamburgueria|churrascaria|ifood|delivery|cafeteria|bistro",
            "food",
            "flexible",
            "Classificada como Alimentação (flexível) pelo dicionário do sistema."),
        new(
            "Transporte público",
            "metro|onibus|bilhete unico|trem|transporte publico|passagem",
            "transport",
            "essential",
            "Classificada como Transporte (essencial) pelo dicionário do sistema."),
        new(
            "Transporte e mobilidade",
            "posto|combustivel|gasolina|etanol|uber|99|99app|99pop|corrida|taxi|estacionamento|pedagio|oficina|mecanica",
            "transport",
            "important",
            "Classificada como Transporte (importante) pelo dicionário do sistema."),
        new(
            "Saúde e farmácia",
            "farmacia|drogaria|clinica|hospital|laboratorio|medico|dentista|plano de saude|consulta|exame",
            "health",
            "essential",
            "Classificada como Saúde (essencial) pelo dicionário do sistema."),
        new(
            "Academia e atividade física",
            "academia|pilates|crossfit|natacao",
            "health",
            "important",
            "Classificada como Saúde (importante) pelo dicionário do sistema."),
        new(
            "Ensino formal",
            "escola|faculdade|universidade|creche|mensalidade escolar",
            "education",
            "essential",
            "Classificada como Educação (essencial) pelo dicionário do sistema."),
        new(
            "Livros e cursos",
            "livraria|curso|livro|apostila|treinamento|papelaria|idiomas",
            "education",
            "important",
            "Classificada como Educação (importante) pelo dicionário do sistema."),
        new(
            "Lazer e entretenimento",
            "cinema|teatro|show|ingresso|parque|museu|viagem|hotel|pousada|airbnb",
            "leisure",
            "flexible",
            "Classificada como Lazer (flexível) pelo dicionário do sistema."),
        new(
            "Equipamentos e eletrônicos",
            "notebook|computador|monitor|eletronico|eletrodomestico",
            "shopping",
            "important",
            "Classificada como Compras (importante) pelo dicionário do sistema."),
        new(
            "Compras e vestuário",
            "loja|roupa|vestuario|calcado|tenis|shopping|magazine|presente",
            "shopping",
            "flexible",
            "Classificada como Compras (flexível) pelo dicionário do sistema."),
        new(
            "Internet e telefonia",
            "internet|fibra|banda larga|telefone|celular|telefonia|plano movel",
            "services",
            "essential",
            "Classificada como Serviços e assinaturas (essencial) pelo dicionário do sistema."),
        new(
            "Streaming e assinaturas",
            "streaming|assinatura|netflix|spotify|disney|prime video|globoplay|youtube|icloud",
            "services",
            "flexible",
            "Classificada como Serviços e assinaturas (flexível) pelo dicionário do sistema.")
    ];

    public async Task<CategorizationResult> ClassifyAsync(
        CategorizationInput input,
        CancellationToken cancellationToken = default)
    {
        var results = await ClassifyBatchAsync(input.HouseholdId, [input], cancellationToken);
        return results[0];
    }

    public async Task<IReadOnlyList<CategorizationResult>> ClassifyBatchAsync(
        Guid householdId,
        IReadOnlyList<CategorizationInput> inputs,
        CancellationToken cancellationToken = default)
    {
        if (inputs.Count == 0)
        {
            return [];
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rules = (await connection.QueryAsync<StoredRule>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                layer AS Layer,
                priority AS Priority,
                name AS Name,
                explanation AS Explanation,
                match_cnpj AS MatchCnpj,
                match_merchant_normalized AS MatchMerchantNormalized,
                match_pattern AS MatchPattern,
                category AS Category,
                essentiality AS Essentiality,
                brand AS Brand
            FROM categorization.rule
            WHERE household_id = @HouseholdId
              AND is_active = true
              AND layer IN ('user', 'profile')
            ORDER BY
                CASE layer WHEN 'user' THEN 1 WHEN 'profile' THEN 2 ELSE 3 END,
                priority ASC,
                created_at ASC,
                id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var userRules = rules.Where(r => r.Layer == "user").ToList();
        var profileRules = rules.Where(r => r.Layer == "profile").ToList();

        var results = new List<CategorizationResult>(inputs.Count);
        foreach (var input in inputs)
        {
            results.Add(ClassifySingle(input, userRules, profileRules));
        }

        return results;
    }

    private static CategorizationResult ClassifySingle(
        CategorizationInput input,
        IReadOnlyList<StoredRule> userRules,
        IReadOnlyList<StoredRule> profileRules)
    {
        if (!string.Equals(input.TxKind, "expense", StringComparison.Ordinal) &&
            !string.Equals(input.TxKind, "refund", StringComparison.Ordinal))
        {
            return new CategorizationResult(
                Category: null,
                Essentiality: null,
                Brand: null,
                DecidingLayer: "system",
                DecidingRuleId: null,
                DecidingRuleName: null,
                Explanation: "Movimento não entra nos gastos.");
        }

        var normalizedDescription = MerchantNormalizer.NormalizeDescription(input.Description);
        var normalizedCnpj = MerchantNormalizer.NormalizeCnpj(input.MerchantCnpj);
        var systemMatch = MatchSystemDictionary(normalizedDescription);

        string? category = null;
        string? essentiality = null;
        string? brand = null;

        string? decidingLayer = null;
        Guid? decidingRuleId = null;
        string? decidingRuleName = null;
        string? explanation = null;

        // Layer 1: user rules
        foreach (var rule in userRules)
        {
            if (!MatchesRule(rule, normalizedDescription, normalizedCnpj, category ?? systemMatch?.Category))
            {
                continue;
            }

            var contributed = ApplyRuleFields(rule, ref category, ref essentiality, ref brand);
            if (contributed && decidingLayer is null)
            {
                decidingLayer = "user";
                decidingRuleId = rule.Id;
                decidingRuleName = rule.Name;
                explanation = rule.Explanation;
            }
        }

        // Layer 2: profile rules
        foreach (var rule in profileRules)
        {
            if (!MatchesRule(rule, normalizedDescription, normalizedCnpj, category ?? systemMatch?.Category))
            {
                continue;
            }

            var contributed = ApplyRuleFields(rule, ref category, ref essentiality, ref brand);
            if (contributed && decidingLayer is null)
            {
                decidingLayer = "profile";
                decidingRuleId = rule.Id;
                decidingRuleName = rule.Name;
                explanation = rule.Explanation;
            }
        }

        // Layer 3: deterministic system dictionary
        if (systemMatch is not null)
        {
            var contributed = false;
            if (category is null && systemMatch.Category is not null)
            {
                category = systemMatch.Category;
                contributed = true;
            }

            if (essentiality is null && systemMatch.Essentiality is not null)
            {
                essentiality = systemMatch.Essentiality;
                contributed = true;
            }

            if (contributed && decidingLayer is null)
            {
                decidingLayer = "system";
                decidingRuleId = null;
                decidingRuleName = systemMatch.RuleName;
                explanation = systemMatch.Explanation;
            }
        }

        if (decidingLayer is null)
        {
            return new CategorizationResult(
                Category: null,
                Essentiality: null,
                Brand: null,
                DecidingLayer: "none",
                DecidingRuleId: null,
                DecidingRuleName: null,
                Explanation: "Nenhuma regra alcançou esta transação; enviada para revisão.");
        }

        return new CategorizationResult(
            Category: category,
            Essentiality: essentiality,
            Brand: brand,
            DecidingLayer: decidingLayer,
            DecidingRuleId: decidingRuleId,
            DecidingRuleName: decidingRuleName,
            Explanation: explanation!);
    }

    private static bool ApplyRuleFields(
        StoredRule rule,
        ref string? category,
        ref string? essentiality,
        ref string? brand)
    {
        var contributed = false;

        if (category is null && !string.IsNullOrWhiteSpace(rule.Category))
        {
            category = rule.Category;
            contributed = true;
        }

        if (essentiality is null && !string.IsNullOrWhiteSpace(rule.Essentiality))
        {
            essentiality = rule.Essentiality;
            contributed = true;
        }

        if (brand is null && !string.IsNullOrWhiteSpace(rule.Brand))
        {
            brand = rule.Brand;
            contributed = true;
        }

        return contributed;
    }

    private static bool MatchesRule(
        StoredRule rule,
        string normalizedDescription,
        string? normalizedCnpj,
        string? candidateCategory)
    {
        if (!string.IsNullOrWhiteSpace(rule.MatchCnpj) &&
            normalizedCnpj is not null &&
            string.Equals(rule.MatchCnpj, normalizedCnpj, StringComparison.Ordinal))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(rule.MatchMerchantNormalized) &&
            string.Equals(rule.MatchMerchantNormalized, normalizedDescription, StringComparison.Ordinal))
        {
            return true;
        }

        if (!string.IsNullOrWhiteSpace(rule.MatchPattern) &&
            PatternMatches(normalizedDescription, rule.MatchPattern, candidateCategory))
        {
            return true;
        }

        return false;
    }

    private static SystemRuleEntry? MatchSystemDictionary(string normalizedDescription)
    {
        if (string.IsNullOrEmpty(normalizedDescription))
        {
            return null;
        }

        foreach (var entry in SystemDictionary)
        {
            if (PatternMatches(normalizedDescription, entry.MatchPattern, candidateCategory: null))
            {
                return entry;
            }
        }

        return null;
    }

    internal static bool PatternMatches(
        string normalizedDescription,
        string matchPattern,
        string? candidateCategory)
    {
        var paddedDescription = $" {normalizedDescription} ";
        var segments = matchPattern.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        foreach (var rawSegment in segments)
        {
            if (rawSegment.StartsWith("category:", StringComparison.OrdinalIgnoreCase))
            {
                var targetCategory = rawSegment["category:".Length..].Trim();
                if (!string.IsNullOrEmpty(candidateCategory) &&
                    string.Equals(candidateCategory, targetCategory, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }

                continue;
            }

            var normalizedSegment = MerchantNormalizer.NormalizeDescription(rawSegment);
            if (string.IsNullOrEmpty(normalizedSegment))
            {
                continue;
            }

            if (normalizedSegment.Length <= 2)
            {
                if (paddedDescription.Contains($" {normalizedSegment} ", StringComparison.Ordinal))
                {
                    return true;
                }
            }
            else if (normalizedDescription.Contains(normalizedSegment, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private sealed record StoredRule(
        Guid Id,
        string Layer,
        int Priority,
        string Name,
        string Explanation,
        string? MatchCnpj,
        string? MatchMerchantNormalized,
        string? MatchPattern,
        string? Category,
        string? Essentiality,
        string? Brand);

    private sealed record SystemRuleEntry(
        string RuleName,
        string MatchPattern,
        string Category,
        string Essentiality,
        string Explanation);
}
