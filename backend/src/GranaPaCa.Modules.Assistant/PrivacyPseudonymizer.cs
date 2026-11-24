using System.Text.RegularExpressions;

namespace GranaPaCa.Modules.Assistant;

/// <summary>
/// Minimizes PII and pseudonymizes bank, account, and merchant names before any text leaves
/// the self-hosted instance to an external provider (ADR-023).
/// </summary>
internal sealed partial class PrivacyPseudonymizer
{
    private readonly Dictionary<string, string> _originalToToken = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _tokenToOriginal = new(StringComparer.Ordinal);
    private int _bankCounter;
    private int _accountCounter;
    private int _merchantCounter;

    public int RegisteredEntitiesCount => _tokenToOriginal.Count;

    public string RegisterBank(string? bankName) =>
        RegisterEntity(bankName, "BANCO", ref _bankCounter);

    public string RegisterAccount(string? accountName) =>
        RegisterEntity(accountName, "CONTA", ref _accountCounter);

    public string RegisterMerchant(string? merchantName) =>
        RegisterEntity(merchantName, "ESTAB", ref _merchantCounter);

    public string SanitizeAndPseudonymize(string? input)
    {
        if (string.IsNullOrEmpty(input))
        {
            return string.Empty;
        }

        var result = input;

        // Replace longer names first so overlapping phrases (e.g., "Banco Aurora Cartão" vs "Banco Aurora") stay intact.
        foreach (var pair in _originalToToken.OrderByDescending(kv => kv.Key.Length))
        {
            if (pair.Key.Length < 2)
            {
                continue;
            }

            result = Regex.Replace(
                result,
                Regex.Escape(pair.Key),
                pair.Value,
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        // Redact irreversible PII patterns (order matters: CNPJ 14-digit before CPF 11-digit, full cards before shorter masks).
        result = EmailRegex().Replace(result, "[EMAIL_OCULTO]");
        result = FormattedCnpjRegex().Replace(result, "[CNPJ_OCULTO]");
        result = FormattedCpfRegex().Replace(result, "[CPF_OCULTO]");
        result = CardNumberRegex().Replace(result, "[CARTAO_OCULTO]");
        result = MaskedCardRegex().Replace(result, "[CARTAO_OCULTO]");
        result = LabeledAccountOrCardRegex().Replace(result, "$1 [CONTA_OCULTA]");
        result = PhoneRegex().Replace(result, "[TELEFONE_OCULTO]");
        result = RawCnpjRegex().Replace(result, "[CNPJ_OCULTO]");
        result = RawCpfRegex().Replace(result, "[CPF_OCULTO]");
        result = AccountWithCheckDigitRegex().Replace(result, "[CONTA_OCULTA]");

        return result;
    }

    public string Restore(string? input)
    {
        if (string.IsNullOrEmpty(input) || _tokenToOriginal.Count == 0)
        {
            return input ?? string.Empty;
        }

        var result = input;
        foreach (var pair in _tokenToOriginal)
        {
            result = result.Replace(pair.Key, pair.Value, StringComparison.Ordinal);
        }

        return result;
    }

    private string RegisterEntity(string? rawName, string prefix, ref int counter)
    {
        if (string.IsNullOrWhiteSpace(rawName))
        {
            return string.Empty;
        }

        var trimmed = rawName.Trim();
        if (_originalToToken.TryGetValue(trimmed, out var existingToken))
        {
            return existingToken;
        }

        counter++;
        var token = $"[{prefix}_{counter}]";
        _originalToToken[trimmed] = token;
        _tokenToOriginal[token] = trimmed;
        return token;
    }

    [GeneratedRegex(@"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}", RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"\b\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}\b")]
    private static partial Regex FormattedCnpjRegex();

    [GeneratedRegex(@"\b\d{3}\.\d{3}\.\d{3}-\d{2}\b")]
    private static partial Regex FormattedCpfRegex();

    [GeneratedRegex(@"(?<!\d)\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{3,4}(?!\d)")]
    private static partial Regex CardNumberRegex();

    [GeneratedRegex(@"(?:\*{2,4}|[xX]{2,4})[\s\-]?(?:\*{2,4}|[xX]{2,4})?[\s\-]?\d{4}\b")]
    private static partial Regex MaskedCardRegex();

    [GeneratedRegex(@"\b(conta|ag[eê]ncia|ag\.?|cart[aã]o|final|c/c)\s*[:#\-]?\s*\d[\d.\-/\s]{3,18}[\dXx]\b", RegexOptions.IgnoreCase)]
    private static partial Regex LabeledAccountOrCardRegex();

    [GeneratedRegex(@"(?<!\d)(?:\+?55\s*)?(?:\(?\d{2}\)?\s*)(?:9\d{4}|\d{4})[\-\s]\d{4}(?!\d)")]
    private static partial Regex PhoneRegex();

    [GeneratedRegex(@"(?<!\d)\d{14}(?!\d)")]
    private static partial Regex RawCnpjRegex();

    [GeneratedRegex(@"(?<!\d)\d{11}(?!\d)")]
    private static partial Regex RawCpfRegex();

    [GeneratedRegex(@"(?<!\d)\d{5,10}-[\dXx](?!\d)")]
    private static partial Regex AccountWithCheckDigitRegex();
}
