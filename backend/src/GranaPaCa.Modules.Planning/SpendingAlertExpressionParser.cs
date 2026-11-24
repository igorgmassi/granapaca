using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using GranaPaCa.Modules.Categorization.Contracts;

namespace GranaPaCa.Modules.Planning;

internal sealed record ParsedAlertRule(
    string? Category,
    string? MerchantKeyword,
    long LimitCents);

/// <summary>
/// Parses Portuguese natural-language spending threshold rules such as
/// "me avise quando delivery passar de R$ 300" into category/keyword + exact integer cents (ADR-013).
/// </summary>
internal static partial class SpendingAlertExpressionParser
{
    private static readonly IReadOnlyDictionary<string, string> CategoryAliases =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["moradia"] = "housing",
            ["casa"] = "housing",
            ["aluguel"] = "housing",
            ["habitacao"] = "housing",
            ["housing"] = "housing",

            ["alimentacao"] = "food",
            ["comida"] = "food",
            ["mercado"] = "food",
            ["supermercado"] = "food",
            ["food"] = "food",

            ["transporte"] = "transport",
            ["combustivel"] = "transport",
            ["mobilidade"] = "transport",
            ["transport"] = "transport",

            ["saude"] = "health",
            ["medico"] = "health",
            ["health"] = "health",

            ["educacao"] = "education",
            ["estudos"] = "education",
            ["education"] = "education",

            ["lazer"] = "leisure",
            ["entretenimento"] = "leisure",
            ["diversao"] = "leisure",
            ["leisure"] = "leisure",

            ["compras"] = "shopping",
            ["vestuario"] = "shopping",
            ["shopping"] = "shopping",

            ["servicos"] = "services",
            ["assinaturas"] = "services",
            ["servicos e assinaturas"] = "services",
            ["services"] = "services",

            ["outros"] = "other",
            ["other"] = "other"
        };

    public static bool TryParse(string expression, out ParsedAlertRule? parsed)
    {
        parsed = null;
        if (string.IsNullOrWhiteSpace(expression))
        {
            return false;
        }

        var trimmed = expression.Trim();
        if (!TryExtractAmountCents(trimmed, out var limitCents) || limitCents <= 0)
        {
            return false;
        }

        var rawSubject = ExtractSubject(trimmed);
        if (string.IsNullOrWhiteSpace(rawSubject))
        {
            return false;
        }

        var normalized = CleanSubject(rawSubject);
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return false;
        }

        if (CategoryAliases.TryGetValue(normalized, out var category))
        {
            parsed = new ParsedAlertRule(category, null, limitCents);
            return true;
        }

        parsed = new ParsedAlertRule(null, normalized, limitCents);
        return true;
    }

    public static bool TryExtractAmountCents(string text, out long cents)
    {
        cents = 0;

        var currencyMatch = BrlAmountRegex().Match(text);
        if (currencyMatch.Success && TryParseBrazilianDecimal(currencyMatch.Groups[1].Value, out var value))
        {
            cents = DecimalToCents(value);
            return cents > 0;
        }

        var reaisMatch = ReaisSuffixRegex().Match(text);
        if (reaisMatch.Success && TryParseBrazilianDecimal(reaisMatch.Groups[1].Value, out value))
        {
            cents = DecimalToCents(value);
            return cents > 0;
        }

        var fallbackMatch = ThresholdNumberRegex().Match(text);
        if (fallbackMatch.Success && TryParseBrazilianDecimal(fallbackMatch.Groups[1].Value, out value))
        {
            cents = DecimalToCents(value);
            return cents > 0;
        }

        return false;
    }

    private static string? ExtractSubject(string text)
    {
        var whenMatch = SubjectBeforeVerbRegex().Match(text);
        if (whenMatch.Success)
        {
            return whenMatch.Groups[1].Value;
        }

        var comparisonMatch = SubjectBeforeOperatorRegex().Match(text);
        if (comparisonMatch.Success)
        {
            return comparisonMatch.Groups[1].Value;
        }

        var afterPrepositionMatch = SubjectAfterPrepositionRegex().Match(text);
        if (afterPrepositionMatch.Success)
        {
            return afterPrepositionMatch.Groups[1].Value;
        }

        return null;
    }

    private static string CleanSubject(string rawSubject)
    {
        var cleaned = LeadingFillerRegex().Replace(rawSubject.Trim(), string.Empty);
        cleaned = TrailingNoiseRegex().Replace(cleaned.Trim(), string.Empty);
        return MerchantNormalizer.NormalizeDescription(cleaned);
    }

    private static bool TryParseBrazilianDecimal(string rawNumber, out decimal value)
    {
        value = 0m;
        var token = rawNumber.Trim();
        if (token.Length == 0)
        {
            return false;
        }

        string normalized;
        var hasComma = token.Contains(',');
        var hasDot = token.Contains('.');

        if (hasComma && hasDot)
        {
            normalized = token.LastIndexOf(',') > token.LastIndexOf('.')
                ? token.Replace(".", string.Empty).Replace(',', '.')
                : token.Replace(",", string.Empty);
        }
        else if (hasComma)
        {
            normalized = token.Replace(',', '.');
        }
        else if (hasDot)
        {
            var lastDot = token.LastIndexOf('.');
            var digitsAfterDot = token.Length - lastDot - 1;
            normalized = digitsAfterDot == 3
                ? token.Replace(".", string.Empty)
                : token;
        }
        else
        {
            normalized = token;
        }

        return decimal.TryParse(
            normalized,
            NumberStyles.AllowDecimalPoint,
            CultureInfo.InvariantCulture,
            out value) && value > 0m;
    }

    private static long DecimalToCents(decimal value) =>
        decimal.ToInt64(Math.Round(value * 100m, 0, MidpointRounding.AwayFromZero));

    public static string RemoveDiacriticsLower(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

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

    [GeneratedRegex(@"R\$\s*(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)", RegexOptions.IgnoreCase)]
    private static partial Regex BrlAmountRegex();

    [GeneratedRegex(@"(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*(?:reais|real|brl)\b", RegexOptions.IgnoreCase)]
    private static partial Regex ReaisSuffixRegex();

    [GeneratedRegex(@"(?:passar(?:em)?\s+de|ultrapassar(?:em)?|exceder(?:em)?|chegar(?:em)?\s+(?:a|em)|atingir(?:em)?|superar(?:em)?|acima\s+de|mais\s+de|>=|>)\s*(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)", RegexOptions.IgnoreCase)]
    private static partial Regex ThresholdNumberRegex();

    [GeneratedRegex(@"(?:quando|se)\s+(?:eu\s+)?(?:(?:os|meus|o)\s+)?(?:gastos?\s+(?:com|em|de|no|na)\s+)?(.+?)\s+(?:passar(?:em)?|ultrapassar(?:em)?|exceder(?:em)?|chegar(?:em)?|atingir(?:em)?|superar(?:em)?|for(?:em)?|ficar(?:em)?|>=|>)", RegexOptions.IgnoreCase)]
    private static partial Regex SubjectBeforeVerbRegex();

    [GeneratedRegex(@"^\s*(?:alerta\s+(?:de|para)\s+)?([a-zA-ZÀ-ÿ0-9\s-]{2,50}?)\s*(?:>=|>|acima\s+de)\s*(?:R\$|\d)", RegexOptions.IgnoreCase)]
    private static partial Regex SubjectBeforeOperatorRegex();

    [GeneratedRegex(@"(?:em|com|no|na)\s+([a-zA-ZÀ-ÿ0-9\s-]{2,40})\s*[.!?]*$", RegexOptions.IgnoreCase)]
    private static partial Regex SubjectAfterPrepositionRegex();

    [GeneratedRegex(@"^(?:me\s+avise\s+|avisar\s+|alerta\s+|alertar\s+)?(?:quando\s+|se\s+)?(?:os\s+|meus\s+|o\s+|a\s+)?(?:gastos?\s+)?(?:com\s+|em\s+|de\s+|no\s+|na\s+|do\s+|da\s+)?", RegexOptions.IgnoreCase)]
    private static partial Regex LeadingFillerRegex();

    [GeneratedRegex(@"\s+(?:no\s+m[eê]s|neste\s+m[eê]s|por\s+m[eê]s|mensal|mensais)$", RegexOptions.IgnoreCase)]
    private static partial Regex TrailingNoiseRegex();
}
