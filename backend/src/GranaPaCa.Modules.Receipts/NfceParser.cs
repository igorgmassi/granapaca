using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace GranaPaCa.Modules.Receipts;

internal sealed record NfceParseResult(
    string? AccessKey,
    string? State,
    string? IssuerName,
    string? IssuerCnpj,
    DateOnly? IssuedOn,
    long? TotalCents,
    string? QrPortalHost,
    string? Notice,
    IReadOnlyList<ParsedNfceItemDto> Items);

/// <summary>
/// Parses Brazilian NFC-e 4.00 XML (including SEFAZ-ES) and NFC-e QR Code URLs (ADR-022),
/// converting all monetary values through decimal into integer cents (ADR-013).
/// </summary>
internal static partial class NfceParser
{
    private static readonly IReadOnlyDictionary<string, string> IbgeUfCodes =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["11"] = "RO", ["12"] = "AC", ["13"] = "AM", ["14"] = "RR", ["15"] = "PA",
            ["16"] = "AP", ["17"] = "TO", ["21"] = "MA", ["22"] = "PI", ["23"] = "CE",
            ["24"] = "RN", ["25"] = "PB", ["26"] = "PE", ["27"] = "AL", ["28"] = "SE",
            ["29"] = "BA", ["31"] = "MG", ["32"] = "ES", ["33"] = "RJ", ["35"] = "SP",
            ["41"] = "PR", ["42"] = "SC", ["43"] = "RS", ["50"] = "MS", ["51"] = "MT",
            ["52"] = "GO", ["53"] = "DF"
        };

    private static readonly (string Category, string[] Keywords)[] ItemCategoryRules =
    [
        ("health", [
            "remedio", "medicamento", "dipirona", "paracetamol", "ibuprofeno", "vitamina",
            "curativo", "band aid", "farmacia", "drogaria", "protetor solar", "alcool gel",
            "termometro", "suplemento", "whey", "creatina", "colirio", "pomada", "xarope",
            "comprimido", "capsula", "antigripal", "analgesico", "creme dental", "escova dental",
            "fio dental", "enxaguante bucal"
        ]),
        ("housing", [
            "detergente", "sabao", "amaciante", "desinfetante", "agua sanitaria", "esponja",
            "vassoura", "rodo", "saco de lixo", "papel higienico", "papel toalha", "lampada",
            "pilha", "tomada", "parafuso", "limpeza", "limpa vidro", "inseticida", "aromatizador",
            "panela", "toalha", "lencol", "travesseiro", "vela", "fosforo", "botijao", "gas"
        ]),
        ("transport", [
            "gasolina", "etanol", "diesel", "gnv", "combustivel", "oleo motor", "pneu",
            "estacionamento", "pedagio", "lavagem", "auto peca", "aditivo"
        ]),
        ("education", [
            "livro", "caderno", "caneta", "lapis", "borracha", "mochila", "estojo",
            "papel a4", "sulfite", "apostila", "papelaria", "escolar"
        ]),
        ("leisure", [
            "ingresso", "cinema", "teatro", "brinquedo", "baralho", "bicicleta", "camping", "jogo"
        ]),
        ("shopping", [
            "camiseta", "calca", "tenis", "sapato", "meia", "vestido", "jaqueta", "bolsa",
            "cinto", "oculos", "relogio", "perfume", "hidratante", "shampoo", "condicionador",
            "sabonete", "desodorante", "maquiagem", "fone", "carregador", "mouse", "teclado",
            "roupa", "calcado", "armarinho"
        ]),
        ("services", [
            "frete", "entrega", "taxa", "servico", "instalacao", "manutencao", "conserto", "lavanderia"
        ]),
        ("food", [
            "arroz", "feijao", "leite", "pao", "cafe", "acucar", "carne", "frango", "peixe",
            "queijo", "presunto", "ovo", "ovos", "tomate", "banana", "maca", "laranja",
            "hortifruti", "biscoito", "bolacha", "refrigerante", "suco", "agua mineral",
            "cerveja", "vinho", "pizza", "lanche", "hamburguer", "salgado", "macarrao",
            "oleo", "azeite", "manteiga", "margarina", "iogurte", "chocolate", "sorvete",
            "padaria", "acougue", "fruta", "verdura", "legume", "farinha", "molho", "tempero",
            "cereal", "aveia", "granola", "bolo", "doce", "salada", "marmita", "refeicao",
            "batata", "cebola", "alho", "alface", "cenoura", "pepino", "melancia", "uva",
            "file", "patinho", "alcatra", "peito", "salsicha", "linguica", "bacon", "atum",
            "sardinha", "extrato", "achocolatado", "cha", "torrada", "requeijao", "creme de leite",
            "leite condensado", "milho", "ervilha", "azeitona", "vinagre", "sal "
        ])
    ];

    public static (bool Ok, string? Error, NfceParseResult? Result) Parse(string? xml, string? qrUrl)
    {
        var hasXml = !string.IsNullOrWhiteSpace(xml);
        var hasQr = !string.IsNullOrWhiteSpace(qrUrl);

        if (!hasXml && !hasQr)
        {
            return (false, "Informe o XML da NFC-e ou a URL do QR Code.", null);
        }

        NfceParseResult? xmlResult = null;
        if (hasXml)
        {
            var (ok, error, parsed) = ParseXml(xml!);
            if (!ok)
            {
                return (false, error, null);
            }

            xmlResult = parsed;
        }

        NfceParseResult? qrResult = null;
        if (hasQr)
        {
            var (ok, error, parsed) = ParseQrUrl(qrUrl!);
            if (!ok)
            {
                if (xmlResult is null)
                {
                    return (false, error, null);
                }
            }
            else
            {
                qrResult = parsed;
            }
        }

        if (xmlResult is not null)
        {
            var accessKey = xmlResult.AccessKey ?? qrResult?.AccessKey;
            var state = xmlResult.State ?? qrResult?.State ?? ResolveStateFromKey(accessKey);
            var issuerCnpj = xmlResult.IssuerCnpj ?? qrResult?.IssuerCnpj ?? ExtractCnpjFromKey(accessKey);
            var qrHost = xmlResult.QrPortalHost ?? qrResult?.QrPortalHost;

            return (true, null, xmlResult with
            {
                AccessKey = accessKey,
                State = state,
                IssuerCnpj = issuerCnpj,
                QrPortalHost = qrHost
            });
        }

        return (true, null, qrResult);
    }

    public static (bool Ok, string? Error, NfceParseResult? Result) ParseXml(string xml)
    {
        XDocument doc;
        try
        {
            var settings = new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                MaxCharactersInDocument = 10_000_000,
                IgnoreComments = true,
                IgnoreProcessingInstructions = true
            };

            using var stringReader = new StringReader(xml.Trim());
            using var xmlReader = XmlReader.Create(stringReader, settings);
            doc = XDocument.Load(xmlReader);
        }
        catch (Exception ex) when (ex is XmlException or InvalidOperationException)
        {
            return (false, "XML da NFC-e inválido ou malformado.", null);
        }

        var infNFe = doc.Descendants().FirstOrDefault(e => e.Name.LocalName == "infNFe");
        if (infNFe is null)
        {
            return (false, "Elemento <infNFe> não encontrado no XML da NFC-e.", null);
        }

        var chNFe = doc.Descendants()
            .FirstOrDefault(e => e.Name.LocalName == "chNFe")?.Value;

        var idAttr = infNFe.Attribute("Id")?.Value;
        var accessKey = Extract44DigitKey(chNFe) ?? Extract44DigitKey(idAttr);
        var state = ResolveStateFromKey(accessKey);

        var emit = Child(infNFe, "emit");
        var issuerName = ChildValue(emit, "xNome") ?? ChildValue(emit, "xFant");
        var issuerCnpj = CleanDigits(ChildValue(emit, "CNPJ")) ?? ExtractCnpjFromKey(accessKey);

        var ide = Child(infNFe, "ide");
        var rawDate = ChildValue(ide, "dhEmi") ?? ChildValue(ide, "dEmi");
        var issuedOn = TryParseNfceDate(rawDate);

        var icmsTot = Child(Child(infNFe, "total"), "ICMSTot");
        long? totalCents = null;
        if (TryParseDecimalCents(ChildValue(icmsTot, "vNF"), out var vNfCents, out var vNfOverflow))
        {
            totalCents = vNfCents;
        }
        else if (vNfOverflow)
        {
            return (false, "Valor total da NFC-e excede o limite suportado.", null);
        }
        else if (TryParseDecimalCents(ChildValue(icmsTot, "vProd"), out var vProdCents, out var vProdOverflow))
        {
            if (TryParseDecimalCents(ChildValue(icmsTot, "vDesc"), out var desc, out var vDescOverflow))
            {
                totalCents = Math.Max(0L, vProdCents - desc);
            }
            else if (vDescOverflow)
            {
                return (false, "Valor de desconto da NFC-e excede o limite suportado.", null);
            }
            else
            {
                totalCents = Math.Max(0L, vProdCents);
            }
        }
        else if (vProdOverflow)
        {
            return (false, "Valor dos produtos da NFC-e excede o limite suportado.", null);
        }

        var qrCodeText = doc.Descendants()
            .FirstOrDefault(e => e.Name.LocalName == "qrCode")?.Value;
        string? qrPortalHost = null;
        if (!string.IsNullOrWhiteSpace(qrCodeText) &&
            Uri.TryCreate(qrCodeText.Trim(), UriKind.Absolute, out var qrUri))
        {
            qrPortalHost = qrUri.Host;
        }

        var items = new List<ParsedNfceItemDto>();
        var detElements = infNFe.Elements().Where(e => e.Name.LocalName == "det").ToList();
        var fallbackIndex = 1;

        foreach (var det in detElements)
        {
            var prod = Child(det, "prod");
            if (prod is null)
            {
                continue;
            }

            var description = ChildValue(prod, "xProd")?.Trim();
            if (string.IsNullOrWhiteSpace(description))
            {
                continue;
            }

            var itemIndex = int.TryParse(det.Attribute("nItem")?.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedIdx) && parsedIdx > 0
                ? parsedIdx
                : fallbackIndex;
            fallbackIndex = Math.Max(fallbackIndex + 1, itemIndex + 1);

            var quantity = TryParseNfceDecimal(ChildValue(prod, "qCom"), out var qCom) && qCom > 0m
                ? Math.Round(qCom, 3, MidpointRounding.AwayFromZero)
                : 1m;

            var hasUnitPrice = TryParseDecimalCents(ChildValue(prod, "vUnCom"), out var unitPriceCents, out var unitOverflow);
            var hasItemTotal = TryParseDecimalCents(ChildValue(prod, "vProd"), out var itemTotalCents, out var totalOverflow);
            var hasDiscount = TryParseDecimalCents(ChildValue(prod, "vDesc"), out var itemDiscountCents, out var discountOverflow);
            if (unitOverflow || totalOverflow || discountOverflow)
            {
                return (false, $"Valor numérico do item #{itemIndex} da NFC-e excede o limite suportado.", null);
            }

            if (!hasDiscount)
            {
                itemDiscountCents = 0L;
            }

            try
            {
                if (!hasItemTotal && hasUnitPrice)
                {
                    itemTotalCents = decimal.ToInt64(Math.Round(quantity * unitPriceCents, 0, MidpointRounding.AwayFromZero));
                }

                if (itemDiscountCents > 0 && itemDiscountCents <= itemTotalCents)
                {
                    itemTotalCents -= itemDiscountCents;
                }

                if (!hasUnitPrice && itemTotalCents > 0 && quantity > 0m)
                {
                    unitPriceCents = decimal.ToInt64(Math.Round(itemTotalCents / quantity, 0, MidpointRounding.AwayFromZero));
                }
            }
            catch (OverflowException)
            {
                return (false, $"Valor numérico do item #{itemIndex} da NFC-e excede o limite suportado.", null);
            }

            var suggestedCategory = SuggestItemCategory(description, issuerName);
            items.Add(new ParsedNfceItemDto(
                itemIndex,
                description,
                quantity,
                unitPriceCents,
                itemTotalCents,
                suggestedCategory));
        }

        if (totalCents is null && items.Count > 0)
        {
            try
            {
                long runningSum = 0;
                foreach (var item in items)
                {
                    runningSum = checked(runningSum + item.TotalCents);
                }

                totalCents = runningSum;
            }
            catch (OverflowException)
            {
                return (false, "Soma dos itens da NFC-e excede o limite suportado.", null);
            }
        }

        return (true, null, new NfceParseResult(
            accessKey,
            state,
            issuerName,
            issuerCnpj,
            issuedOn,
            totalCents,
            qrPortalHost,
            null,
            items));
    }

    public static (bool Ok, string? Error, NfceParseResult? Result) ParseQrUrl(string qrUrl)
    {
        var trimmed = qrUrl.Trim();
        string? accessKey = null;
        string? qrPortalHost = null;
        long? totalCents = null;
        DateOnly? issuedOn = null;

        if (Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) &&
            (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps))
        {
            qrPortalHost = uri.Host;
            var queryParams = ParseQueryParameters(uri.Query);

            if (queryParams.TryGetValue("p", out var pValue) && !string.IsNullOrWhiteSpace(pValue))
            {
                var segments = pValue.Split('|');
                if (segments.Length > 0)
                {
                    accessKey = Extract44DigitKey(segments[0]);
                }

                // Offline NFC-e QR v2 layout: chNFe|nVersao|tpAmb|cDest(day)|vNF|digVal|cIdToken|cHashQRCode
                if (segments.Length >= 5)
                {
                    if (TryParseDecimalCents(segments[4], out var offlineTotal, out var offlineOverflow))
                    {
                        totalCents = offlineTotal;
                    }
                    else if (offlineOverflow)
                    {
                        return (false, "Valor total da NFC-e excede o limite suportado.", null);
                    }
                }

                if (segments.Length >= 4 &&
                    accessKey is not null &&
                    int.TryParse(segments[3], NumberStyles.Integer, CultureInfo.InvariantCulture, out var dayOfMonth))
                {
                    issuedOn = TryBuildDateFromKeyAndDay(accessKey, dayOfMonth);
                }
            }

            if (accessKey is null && queryParams.TryGetValue("chNFe", out var chNFeParam))
            {
                accessKey = Extract44DigitKey(chNFeParam);
            }

            if (totalCents is null && queryParams.TryGetValue("vNF", out var vNfParam))
            {
                if (TryParseDecimalCents(vNfParam, out var vNfCents, out var vNfOverflow))
                {
                    totalCents = vNfCents;
                }
                else if (vNfOverflow)
                {
                    return (false, "Valor total da NFC-e excede o limite suportado.", null);
                }
            }

            if (issuedOn is null && queryParams.TryGetValue("dhEmi", out var dhEmiParam))
            {
                issuedOn = TryParseNfceDate(dhEmiParam) ?? TryParseHexNfceDate(dhEmiParam);
            }
        }

        accessKey ??= Extract44DigitKey(trimmed);
        if (accessKey is null)
        {
            return (false, "Não foi possível extrair a chave de acesso de 44 dígitos da URL do QR Code da NFC-e.", null);
        }

        var state = ResolveStateFromKey(accessKey);
        var issuerCnpj = ExtractCnpjFromKey(accessKey);
        issuedOn ??= TryBuildDateFromKeyAndDay(accessKey, 1);

        var issuerLabel = state is not null
            ? $"NFC-e ({state})"
            : "NFC-e";

        var notice = state == "ES"
            ? "Chave da NFC-e (SEFAZ-ES) identificada pelo QR Code. Envie o XML para detalhar os itens do cupom."
            : "Chave da NFC-e identificada pelo QR Code. Envie o XML para detalhar os itens do cupom.";

        return (true, null, new NfceParseResult(
            accessKey,
            state,
            issuerLabel,
            issuerCnpj,
            issuedOn,
            totalCents,
            qrPortalHost,
            notice,
            []));
    }

    public static string SuggestItemCategory(string description, string? issuerName = null)
    {
        var normalized = FoldLower(description);
        foreach (var (category, keywords) in ItemCategoryRules)
        {
            if (keywords.Any(kw => normalized.Contains(kw, StringComparison.Ordinal)))
            {
                return category;
            }
        }

        if (!string.IsNullOrWhiteSpace(issuerName))
        {
            var normalizedIssuer = FoldLower(issuerName);
            if (normalizedIssuer.Contains("farmacia", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("drogaria", StringComparison.Ordinal))
            {
                return "health";
            }

            if (normalizedIssuer.Contains("supermercado", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("mercado", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("padaria", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("restaurante", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("hortifruti", StringComparison.Ordinal))
            {
                return "food";
            }

            if (normalizedIssuer.Contains("posto", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("combustivel", StringComparison.Ordinal))
            {
                return "transport";
            }

            if (normalizedIssuer.Contains("livraria", StringComparison.Ordinal) ||
                normalizedIssuer.Contains("papelaria", StringComparison.Ordinal))
            {
                return "education";
            }
        }

        return "other";
    }

    private static XElement? Child(XElement? parent, string localName) =>
        parent?.Elements().FirstOrDefault(e => e.Name.LocalName == localName);

    private static string? ChildValue(XElement? parent, string localName) =>
        Child(parent, localName)?.Value?.Trim();

    private static string? Extract44DigitKey(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var match = AccessKey44Regex().Match(raw);
        if (match.Success)
        {
            return match.Value;
        }

        var digits = CleanDigits(raw);
        return digits is { Length: 44 } ? digits : null;
    }

    private static string? ResolveStateFromKey(string? accessKey)
    {
        if (accessKey is not { Length: 44 })
        {
            return null;
        }

        var ufCode = accessKey[..2];
        return IbgeUfCodes.TryGetValue(ufCode, out var uf) ? uf : null;
    }

    private static string? ExtractCnpjFromKey(string? accessKey) =>
        accessKey is { Length: 44 } ? accessKey.Substring(6, 14) : null;

    private static DateOnly? TryBuildDateFromKeyAndDay(string accessKey, int day)
    {
        if (accessKey.Length != 44)
        {
            return null;
        }

        if (!int.TryParse(accessKey.Substring(2, 2), NumberStyles.Integer, CultureInfo.InvariantCulture, out var yy) ||
            !int.TryParse(accessKey.Substring(4, 2), NumberStyles.Integer, CultureInfo.InvariantCulture, out var mm) ||
            mm is < 1 or > 12)
        {
            return null;
        }

        var year = 2000 + yy;
        var maxDay = DateTime.DaysInMonth(year, mm);
        var clampedDay = Math.Clamp(day, 1, maxDay);
        return new DateOnly(year, mm, clampedDay);
    }

    private static DateOnly? TryParseNfceDate(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var trimmed = raw.Trim();
        if (trimmed.Length >= 10 &&
            DateOnly.TryParseExact(trimmed[..10], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var dateOnly))
        {
            return dateOnly;
        }

        if (DateTimeOffset.TryParse(trimmed, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dto))
        {
            return DateOnly.FromDateTime(dto.Date);
        }

        return null;
    }

    private static DateOnly? TryParseHexNfceDate(string raw)
    {
        if (raw.Length % 2 != 0 || raw.Length < 20)
        {
            return null;
        }

        try
        {
            var bytes = Convert.FromHexString(raw);
            var text = Encoding.UTF8.GetString(bytes);
            return TryParseNfceDate(text);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    private static bool TryParseNfceDecimal(string? raw, out decimal value)
    {
        value = 0m;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        var trimmed = raw.Trim();
        var sign = string.Empty;
        if (trimmed[0] is '+' or '-')
        {
            sign = trimmed[0] == '-' ? "-" : string.Empty;
            trimmed = trimmed[1..];
        }

        if (trimmed.Length == 0)
        {
            return false;
        }

        var lastDot = trimmed.LastIndexOf('.');
        var lastComma = trimmed.LastIndexOf(',');
        string normalized;

        if (lastDot >= 0 && lastComma >= 0)
        {
            if (lastComma > lastDot)
            {
                if (!BrazilianGroupedDecimalRegex().IsMatch(trimmed))
                {
                    return false;
                }

                normalized = trimmed.Replace(".", string.Empty, StringComparison.Ordinal).Replace(',', '.');
            }
            else
            {
                if (!UsGroupedDecimalRegex().IsMatch(trimmed))
                {
                    return false;
                }

                normalized = trimmed.Replace(",", string.Empty, StringComparison.Ordinal);
            }
        }
        else if (lastComma >= 0)
        {
            var commaCount = trimmed.Count(c => c == ',');
            if (commaCount == 1)
            {
                // Brazilian decimal separator (e.g. "45,50" -> 45.50, never 4550).
                normalized = trimmed.Replace(',', '.');
            }
            else if (UsMultiThousandsRegex().IsMatch(trimmed))
            {
                normalized = trimmed.Replace(",", string.Empty, StringComparison.Ordinal);
            }
            else
            {
                return false;
            }
        }
        else if (lastDot >= 0)
        {
            var dotCount = trimmed.Count(c => c == '.');
            if (dotCount == 1)
            {
                // Standard SEFAZ XML decimal (e.g. "45.50", "2.000", "12.5000").
                normalized = trimmed;
            }
            else if (BrazilianMultiThousandsRegex().IsMatch(trimmed))
            {
                normalized = trimmed.Replace(".", string.Empty, StringComparison.Ordinal);
            }
            else
            {
                return false;
            }
        }
        else
        {
            normalized = trimmed;
        }

        return decimal.TryParse(
            sign + normalized,
            NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
            CultureInfo.InvariantCulture,
            out value);
    }

    private static bool TryParseDecimalCents(string? raw, out long cents, out bool overflowed)
    {
        cents = 0;
        overflowed = false;
        if (!TryParseNfceDecimal(raw, out var dec))
        {
            return false;
        }

        try
        {
            cents = decimal.ToInt64(Math.Round(dec * 100m, 0, MidpointRounding.AwayFromZero));
            return true;
        }
        catch (OverflowException)
        {
            overflowed = true;
            return false;
        }
    }

    private static string? CleanDigits(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var digits = NonDigitsRegex().Replace(raw, string.Empty);
        return digits.Length == 0 ? null : digits;
    }

    private static Dictionary<string, string> ParseQueryParameters(string query)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(query))
        {
            return result;
        }

        var trimmed = query.TrimStart('?');
        foreach (var pair in trimmed.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var eqIdx = pair.IndexOf('=');
            if (eqIdx <= 0)
            {
                continue;
            }

            var key = Uri.UnescapeDataString(pair[..eqIdx]);
            var val = Uri.UnescapeDataString(pair[(eqIdx + 1)..]);
            result[key] = val;
        }

        return result;
    }

    private static string FoldLower(string text)
    {
        var formD = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(formD.Length);
        foreach (var ch in formD)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
            {
                sb.Append(char.ToLowerInvariant(ch));
            }
        }

        return sb.ToString();
    }

    [GeneratedRegex(@"(?<!\d)\d{44}(?!\d)", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex AccessKey44Regex();

    [GeneratedRegex("[^0-9]+", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex NonDigitsRegex();

    [GeneratedRegex(@"^\d{1,3}(?:\.\d{3})+,\d+$", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex BrazilianGroupedDecimalRegex();

    [GeneratedRegex(@"^\d{1,3}(?:,\d{3})+\.\d+$", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex UsGroupedDecimalRegex();

    [GeneratedRegex(@"^\d{1,3}(?:,\d{3}){2,}$", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex UsMultiThousandsRegex();

    [GeneratedRegex(@"^\d{1,3}(?:\.\d{3}){2,}$", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex BrazilianMultiThousandsRegex();
}
