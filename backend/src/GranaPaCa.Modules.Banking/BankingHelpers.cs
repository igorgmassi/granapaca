using System.Data;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Dapper;
using Microsoft.Extensions.Configuration;

namespace GranaPaCa.Modules.Banking;

internal static class MoneyConverter
{
    /// <summary>
    /// Converts a provider decimal amount to integer cents, rejecting any fractional cent (ADR-013).
    /// </summary>
    public static long ConvertDecimalToCents(decimal amount)
    {
        var scaled = amount * 100m;
        var truncated = decimal.Truncate(scaled);
        if (scaled != truncated)
        {
            throw new InvalidOperationException("Monetary value contains fractional cents (ADR-013).");
        }

        return decimal.ToInt64(truncated);
    }
}

internal static class DateParser
{
    public const string DefaultTimeZoneId = "America/Sao_Paulo";

    public static TimeZoneInfo ResolveInstanceTimeZone(IConfiguration configuration)
    {
        var configured = configuration["Banking:TimeZone"]
            ?? configuration["TZ"]
            ?? DefaultTimeZoneId;

        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(configured);
        }
        catch (TimeZoneNotFoundException)
        {
            return TimeZoneInfo.FindSystemTimeZoneById(DefaultTimeZoneId);
        }
    }

    public static DateOnly TodayInTimeZone(TimeZoneInfo timeZone)
    {
        var localNow = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, timeZone);
        return DateOnly.FromDateTime(localNow.Date);
    }

    /// <summary>
    /// Parses a provider date according to ADR-015:
    /// pure calendar dates and UTC midnight (00:00:00Z) preserve their calendar day without shifting backward;
    /// timestamps with a time component convert to the instance timezone.
    /// </summary>
    public static DateOnly ParseProviderDate(string rawDate, TimeZoneInfo instanceTimeZone)
    {
        if (string.IsNullOrWhiteSpace(rawDate))
        {
            throw new FormatException("Provider date value is empty.");
        }

        var trimmed = rawDate.Trim();
        if (trimmed.Length == 10 &&
            DateOnly.TryParseExact(trimmed, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var pureDate))
        {
            return pureDate;
        }

        var parsed = DateTimeOffset.Parse(trimmed, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
        var utc = parsed.ToUniversalTime();
        if (utc.TimeOfDay == TimeSpan.Zero)
        {
            return DateOnly.FromDateTime(utc.Date);
        }

        var local = TimeZoneInfo.ConvertTime(utc, instanceTimeZone);
        return DateOnly.FromDateTime(local.Date);
    }
}

internal sealed class DateOnlyTypeHandler : SqlMapper.TypeHandler<DateOnly>
{
    public override void SetValue(IDbDataParameter parameter, DateOnly value)
    {
        parameter.DbType = DbType.Date;
        parameter.Value = value;
    }

    public override DateOnly Parse(object value) => value switch
    {
        DateOnly dateOnly => dateOnly,
        DateTime dateTime => DateOnly.FromDateTime(dateTime),
        DateTimeOffset dto => DateOnly.FromDateTime(dto.Date),
        _ => DateOnly.Parse(value.ToString() ?? string.Empty, CultureInfo.InvariantCulture)
    };
}

internal static class ContentHashCalculator
{
    public static string ComputeTransactionHash(
        DateOnly occurredOn,
        DateOnly? purchaseOn,
        string description,
        string? merchantCnpj,
        long amountCents,
        string currency,
        string status,
        Guid? billId,
        int? installmentNumber,
        int? installmentTotal,
        bool isRemoved)
    {
        var canonical = string.Join(
            '|',
            occurredOn.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            purchaseOn?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? string.Empty,
            description,
            merchantCnpj ?? string.Empty,
            amountCents.ToString(CultureInfo.InvariantCulture),
            currency,
            status,
            billId?.ToString("D") ?? string.Empty,
            installmentNumber?.ToString(CultureInfo.InvariantCulture) ?? string.Empty,
            installmentTotal?.ToString(CultureInfo.InvariantCulture) ?? string.Empty,
            isRemoved ? "1" : "0");

        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
        return Convert.ToHexStringLower(bytes);
    }
}

internal static class BankingTaxonomy
{
    public static readonly Dictionary<string, string> CategoryLabels = new(StringComparer.Ordinal)
    {
        ["housing"] = "Moradia",
        ["food"] = "Alimentação",
        ["transport"] = "Transporte",
        ["health"] = "Saúde",
        ["education"] = "Educação",
        ["leisure"] = "Lazer",
        ["shopping"] = "Compras",
        ["services"] = "Serviços e assinaturas",
        ["other"] = "Outros",
        ["uncategorized"] = "Sem categoria"
    };

    public static readonly HashSet<string> EditableCategories = new(StringComparer.Ordinal)
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

    public static readonly HashSet<string> Essentialities = new(StringComparer.Ordinal)
    {
        "essential",
        "important",
        "flexible"
    };

    public static readonly HashSet<string> TransactionKinds = new(StringComparer.Ordinal)
    {
        "expense",
        "income",
        "own_transfer",
        "card_payment",
        "refund",
        "withdrawal",
        "investment",
        "redemption"
    };

    public static string GetCategoryLabel(string category) =>
        CategoryLabels.TryGetValue(category, out var label) ? label : category;

    public static string? ExtractLastFourDigits(string? rawNumber)
    {
        if (string.IsNullOrWhiteSpace(rawNumber))
        {
            return null;
        }

        var digits = new string(rawNumber.Where(char.IsAsciiDigit).ToArray());
        if (digits.Length == 0)
        {
            return null;
        }

        return digits.Length <= 4 ? digits : digits[^4..];
    }
}
