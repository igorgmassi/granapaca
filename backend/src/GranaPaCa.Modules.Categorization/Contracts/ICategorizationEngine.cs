using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace GranaPaCa.Modules.Categorization.Contracts;

public sealed record CategorizationInput(
    Guid HouseholdId,
    string Description,
    string? MerchantCnpj,
    long AmountCents,
    string TxKind);

public sealed record CategorizationResult(
    string? Category,
    string? Essentiality,
    string? Brand,
    string DecidingLayer,
    Guid? DecidingRuleId,
    string? DecidingRuleName,
    string Explanation);

/// <summary>
/// Deterministic layered rule engine (RF-30, ADR-021): user rules -> profile rules -> system rules.
/// </summary>
public interface ICategorizationEngine
{
    Task<CategorizationResult> ClassifyAsync(
        CategorizationInput input,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<CategorizationResult>> ClassifyBatchAsync(
        Guid householdId,
        IReadOnlyList<CategorizationInput> inputs,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Implemented by Banking so Categorization can trigger reclassification when profile or user rules change
/// without touching manual adjustments (RF-08, RF-27).
/// </summary>
public interface ITransactionReclassifier
{
    Task<int> ReclassifyHouseholdAsync(Guid householdId, CancellationToken cancellationToken = default);

    Task<IReadOnlyDictionary<Guid, int>> CountRuleMatchesAsync(
        Guid householdId,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Normalizes merchant descriptions and CNPJs deterministically for matching similar transactions (RF-26).
/// </summary>
public static partial class MerchantNormalizer
{
    public static string? NormalizeCnpj(string? cnpj)
    {
        if (string.IsNullOrWhiteSpace(cnpj))
        {
            return null;
        }

        var digits = NonDigitsRegex().Replace(cnpj, string.Empty);
        return digits.Length == 14 ? digits : null;
    }

    public static string NormalizeDescription(string description)
    {
        if (string.IsNullOrWhiteSpace(description))
        {
            return string.Empty;
        }

        var formD = description.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(formD.Length);
        foreach (var ch in formD)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
            {
                sb.Append(char.ToLowerInvariant(ch));
            }
        }

        var cleaned = NonAlnumRegex().Replace(sb.ToString(), " ");
        cleaned = MultiSpaceRegex().Replace(cleaned, " ").Trim();
        return cleaned;
    }

    [GeneratedRegex("[^0-9]+")]
    private static partial Regex NonDigitsRegex();

    [GeneratedRegex("[^a-z0-9]+")]
    private static partial Regex NonAlnumRegex();

    [GeneratedRegex(@"\s+")]
    private static partial Regex MultiSpaceRegex();
}
