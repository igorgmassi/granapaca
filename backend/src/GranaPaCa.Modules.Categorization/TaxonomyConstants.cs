namespace GranaPaCa.Modules.Categorization;

internal static class TaxonomyConstants
{
    public static readonly HashSet<string> AllowedCategories = new(StringComparer.Ordinal)
    {
        "housing",
        "food",
        "transport",
        "health",
        "education",
        "leisure",
        "shopping",
        "services",
        "other"
    };

    public static readonly HashSet<string> AllowedEssentialities = new(StringComparer.Ordinal)
    {
        "essential",
        "important",
        "flexible"
    };

    public static bool TryNormalizeCategory(string? value, out string? normalized)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            normalized = null;
            return true;
        }

        var candidate = value.Trim().ToLowerInvariant();
        if (AllowedCategories.Contains(candidate))
        {
            normalized = candidate;
            return true;
        }

        normalized = null;
        return false;
    }

    public static bool TryNormalizeEssentiality(string? value, out string? normalized)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            normalized = null;
            return true;
        }

        var candidate = value.Trim().ToLowerInvariant();
        if (AllowedEssentialities.Contains(candidate))
        {
            normalized = candidate;
            return true;
        }

        normalized = null;
        return false;
    }
}
