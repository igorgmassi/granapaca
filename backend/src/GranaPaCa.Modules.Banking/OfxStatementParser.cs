using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using GranaPaCa.Modules.Categorization.Contracts;

namespace GranaPaCa.Modules.Banking;

internal sealed record ParsedStatement(
    string Format,
    string? BankId,
    string? AccountId,
    string? AccountKind,
    string? InstitutionName,
    long? LedgerBalanceCents,
    IReadOnlyList<ParsedStatementTransaction> Transactions);

internal sealed record ParsedStatementTransaction(
    string ExternalId,
    DateOnly OccurredOn,
    string Description,
    long AmountCents,
    string RawPayloadJson);

internal static class StatementIdHelper
{
    public static string ComputeDeterministicHash(
        DateOnly occurredOn,
        long amountCents,
        string description,
        int occurrenceIndex)
    {
        var normalizedDescription = MerchantNormalizer.NormalizeDescription(description);
        var canonical = string.Join(
            '|',
            occurredOn.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            amountCents.ToString(CultureInfo.InvariantCulture),
            normalizedDescription,
            occurrenceIndex.ToString(CultureInfo.InvariantCulture));

        var hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
        return Convert.ToHexStringLower(hashBytes);
    }

    public static string Slugify(string? value, string fallback)
    {
        var normalized = string.IsNullOrWhiteSpace(value)
            ? string.Empty
            : MerchantNormalizer.NormalizeDescription(value);
        if (string.IsNullOrEmpty(normalized))
        {
            return fallback;
        }

        return normalized.Replace(' ', '-');
    }
}

internal static partial class OfxStatementParser
{
    public static (bool Ok, string? Error, ParsedStatement? Statement) Parse(
        string content,
        TimeZoneInfo instanceTimeZone)
    {
        if (string.IsNullOrWhiteSpace(content))
        {
            return (false, "Arquivo OFX vazio.", null);
        }

        var cleaned = content.TrimStart('\uFEFF');
        var ofxStart = cleaned.IndexOf("<OFX", StringComparison.OrdinalIgnoreCase);
        if (ofxStart < 0)
        {
            return (false, "Arquivo OFX inválido: tag <OFX> não encontrada.", null);
        }

        var body = XmlCommentRegex().Replace(cleaned[ofxStart..], string.Empty);

        var curdef = GetLeafTag(body, "CURDEF");
        if (!string.IsNullOrWhiteSpace(curdef) &&
            !string.Equals(curdef, "BRL", StringComparison.OrdinalIgnoreCase))
        {
            return (false, $"Moeda não suportada no arquivo OFX ('{curdef}'): apenas BRL é aceito.", null);
        }

        var isCreditCard = body.Contains("<CREDITCARDMSGSRSV1", StringComparison.OrdinalIgnoreCase) ||
                           body.Contains("<CCSTMTTRNRS", StringComparison.OrdinalIgnoreCase) ||
                           body.Contains("<CCSTMTRS", StringComparison.OrdinalIgnoreCase) ||
                           body.Contains("<CCACCTFROM", StringComparison.OrdinalIgnoreCase);

        var accountBlock = GetBlock(body, "CCACCTFROM") ?? GetBlock(body, "BANKACCTFROM") ?? body;
        var bankId = GetLeafTag(accountBlock, "BANKID");
        var accountId = GetLeafTag(accountBlock, "ACCTID");
        var acctType = GetLeafTag(accountBlock, "ACCTTYPE");

        var fiBlock = GetBlock(body, "FI");
        var orgName = fiBlock is not null ? GetLeafTag(fiBlock, "ORG") : GetLeafTag(body, "ORG");

        var detectedKind = ResolveAccountKind(isCreditCard, acctType);

        long? ledgerBalanceCents = null;
        var balanceBlock = GetBlock(body, "LEDGERBAL") ?? GetBlock(body, "AVAILBAL");
        var rawBalance = balanceBlock is not null ? GetLeafTag(balanceBlock, "BALAMT") : null;
        if (!string.IsNullOrWhiteSpace(rawBalance))
        {
            if (!TryParseOfxAmount(rawBalance, out var balCents, out var balError))
            {
                return (false, $"Saldo OFX inválido: {balError}", null);
            }

            ledgerBalanceCents = balCents;
        }

        var txBlocks = ExtractTransactionBlocks(body);
        if (txBlocks.Count == 0)
        {
            return (false, "Nenhuma transação encontrada no arquivo OFX.", null);
        }

        var transactions = new List<ParsedStatementTransaction>(txBlocks.Count);
        var fallbackOccurrences = new Dictionary<(DateOnly, long, string), int>();

        for (var index = 0; index < txBlocks.Count; index++)
        {
            var block = txBlocks[index];
            var txNumber = index + 1;

            var trnType = GetLeafTag(block, "TRNTYPE");
            var dtPostedRaw = GetLeafTag(block, "DTPOSTED");
            var trnAmtRaw = GetLeafTag(block, "TRNAMT");
            var fitId = GetLeafTag(block, "FITID");
            var name = GetLeafTag(block, "NAME");
            var memo = GetLeafTag(block, "MEMO");

            if (string.IsNullOrWhiteSpace(dtPostedRaw))
            {
                return (false, $"Transação OFX #{txNumber} sem data (<DTPOSTED>).", null);
            }

            if (!TryParseOfxDate(dtPostedRaw, instanceTimeZone, out var occurredOn))
            {
                return (false, $"Data inválida na transação OFX #{txNumber}: '{dtPostedRaw}'.", null);
            }

            if (string.IsNullOrWhiteSpace(trnAmtRaw))
            {
                return (false, $"Transação OFX #{txNumber} sem valor (<TRNAMT>).", null);
            }

            if (!TryParseOfxAmount(trnAmtRaw, out var amountCents, out var amountError))
            {
                return (false, $"Valor inválido na transação OFX #{txNumber}: {amountError}", null);
            }

            var description = BuildDescription(name, memo, trnType);

            string externalId;
            if (!string.IsNullOrWhiteSpace(fitId))
            {
                externalId = $"ofx:{fitId}";
            }
            else
            {
                var normDesc = MerchantNormalizer.NormalizeDescription(description);
                var key = (occurredOn, amountCents, normDesc);
                var occurrenceIndex = fallbackOccurrences.GetValueOrDefault(key, 0);
                fallbackOccurrences[key] = occurrenceIndex + 1;
                externalId = $"ofx:hash:{StatementIdHelper.ComputeDeterministicHash(occurredOn, amountCents, description, occurrenceIndex)}";
            }

            var rawPayloadJson = JsonSerializer.Serialize(new
            {
                format = "ofx",
                trnType,
                dtPosted = dtPostedRaw,
                trnAmt = trnAmtRaw,
                fitId,
                name,
                memo
            });

            transactions.Add(new ParsedStatementTransaction(
                externalId,
                occurredOn,
                description,
                amountCents,
                rawPayloadJson));
        }

        var statement = new ParsedStatement(
            "ofx",
            bankId,
            accountId,
            detectedKind,
            orgName,
            ledgerBalanceCents,
            transactions);

        return (true, null, statement);
    }

    private static string ResolveAccountKind(bool isCreditCard, string? acctType)
    {
        if (isCreditCard)
        {
            return "credit_card";
        }

        return acctType?.Trim().ToUpperInvariant() switch
        {
            "SAVINGS" => "savings",
            "CREDITLINE" or "CREDITCARD" => "credit_card",
            _ => "checking"
        };
    }

    private static List<string> ExtractTransactionBlocks(string body)
    {
        var matches = ClosedStmtTrnRegex().Matches(body);
        if (matches.Count > 0)
        {
            var result = new List<string>(matches.Count);
            foreach (Match match in matches)
            {
                result.Add(match.Groups[1].Value);
            }

            return result;
        }

        // Fallback for SGML dialects that omit </STMTTRN>.
        var tranList = GetBlock(body, "BANKTRANLIST") ?? body;
        var openMatches = OpenStmtTrnRegex().Matches(tranList);
        if (openMatches.Count == 0)
        {
            return [];
        }

        var blocks = new List<string>(openMatches.Count);
        for (var i = 0; i < openMatches.Count; i++)
        {
            var start = openMatches[i].Index + openMatches[i].Length;
            var end = i + 1 < openMatches.Count ? openMatches[i + 1].Index : tranList.Length;
            blocks.Add(tranList[start..end]);
        }

        return blocks;
    }

    private static string? GetBlock(string source, string tagName)
    {
        var openTag = $"<{tagName}>";
        var closeTag = $"</{tagName}>";
        var start = source.IndexOf(openTag, StringComparison.OrdinalIgnoreCase);
        if (start < 0)
        {
            return null;
        }

        var contentStart = start + openTag.Length;
        var end = source.IndexOf(closeTag, contentStart, StringComparison.OrdinalIgnoreCase);
        return end < 0 ? source[contentStart..] : source[contentStart..end];
    }

    private static string? GetLeafTag(string block, string tagName)
    {
        var pattern = $@"<{Regex.Escape(tagName)}>\s*([^<]*)";
        var match = Regex.Match(block, pattern, RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (!match.Success)
        {
            return null;
        }

        var decoded = WebUtility.HtmlDecode(match.Groups[1].Value);
        var collapsed = CollapseWhitespaceRegex().Replace(decoded, " ").Trim();
        return collapsed.Length == 0 ? null : collapsed;
    }

    private static string BuildDescription(string? name, string? memo, string? trnType)
    {
        if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(memo))
        {
            if (memo.Contains(name, StringComparison.OrdinalIgnoreCase))
            {
                return memo;
            }

            if (name.Contains(memo, StringComparison.OrdinalIgnoreCase))
            {
                return name;
            }

            return $"{name} - {memo}";
        }

        if (!string.IsNullOrWhiteSpace(name))
        {
            return name;
        }

        if (!string.IsNullOrWhiteSpace(memo))
        {
            return memo;
        }

        return !string.IsNullOrWhiteSpace(trnType) ? trnType : "Lançamento OFX";
    }

    private static bool TryParseOfxDate(
        string raw,
        TimeZoneInfo instanceTimeZone,
        out DateOnly date)
    {
        date = default;
        var trimmed = raw.Trim();
        var match = OfxDateRegex().Match(trimmed);
        if (!match.Success)
        {
            return false;
        }

        if (!int.TryParse(match.Groups[1].Value, CultureInfo.InvariantCulture, out var year) ||
            !int.TryParse(match.Groups[2].Value, CultureInfo.InvariantCulture, out var month) ||
            !int.TryParse(match.Groups[3].Value, CultureInfo.InvariantCulture, out var day))
        {
            return false;
        }

        DateOnly baseDate;
        try
        {
            baseDate = new DateOnly(year, month, day);
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }

        if (!match.Groups[4].Success)
        {
            // Pure YYYYMMDD calendar date (ADR-015).
            date = baseDate;
            return true;
        }

        var hour = int.Parse(match.Groups[4].Value, CultureInfo.InvariantCulture);
        var minute = int.Parse(match.Groups[5].Value, CultureInfo.InvariantCulture);
        var second = int.Parse(match.Groups[6].Value, CultureInfo.InvariantCulture);
        if (hour > 23 || minute > 59 || second > 59)
        {
            return false;
        }

        if (!match.Groups[7].Success)
        {
            date = baseDate;
            return true;
        }

        if (!TryParseOfxOffset(match.Groups[7].Value, out var offset))
        {
            return false;
        }

        // UTC midnight preserves the calendar day without shifting backward (ADR-015).
        if (offset == TimeSpan.Zero && hour == 0 && minute == 0 && second == 0)
        {
            date = baseDate;
            return true;
        }

        var dto = new DateTimeOffset(year, month, day, hour, minute, second, offset);
        var local = TimeZoneInfo.ConvertTime(dto, instanceTimeZone);
        date = DateOnly.FromDateTime(local.Date);
        return true;
    }

    private static bool TryParseOfxOffset(string rawOffset, out TimeSpan offset)
    {
        offset = TimeSpan.Zero;
        var trimmed = rawOffset.Trim();
        if (trimmed.Length == 0)
        {
            return false;
        }

        var sign = 1;
        if (trimmed[0] == '-')
        {
            sign = -1;
            trimmed = trimmed[1..];
        }
        else if (trimmed[0] == '+')
        {
            trimmed = trimmed[1..];
        }

        if (trimmed.Contains(':'))
        {
            var parts = trimmed.Split(':');
            if (parts.Length == 2 &&
                int.TryParse(parts[0], CultureInfo.InvariantCulture, out var h) &&
                int.TryParse(parts[1], CultureInfo.InvariantCulture, out var m) &&
                h <= 14 && m <= 59)
            {
                offset = new TimeSpan(sign * h, sign * m, 0);
                return true;
            }

            return false;
        }

        if (decimal.TryParse(trimmed, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var hoursDec) &&
            hoursDec <= 14m)
        {
            var totalMinutes = (int)Math.Round(hoursDec * 60m, MidpointRounding.AwayFromZero);
            offset = TimeSpan.FromMinutes(sign * totalMinutes);
            return true;
        }

        return false;
    }

    private static bool TryParseOfxAmount(string raw, out long cents, out string? error)
    {
        cents = 0;
        error = null;
        var trimmed = raw.Trim().Replace(" ", string.Empty, StringComparison.Ordinal);
        if (trimmed.Length == 0)
        {
            error = "valor vazio.";
            return false;
        }

        // Standard OFX uses '.' as decimal separator, though some Brazilian exports emit ','.
        if (trimmed.Contains(',') && !trimmed.Contains('.') && trimmed.Count(c => c == ',') == 1)
        {
            trimmed = trimmed.Replace(',', '.');
        }

        if (!decimal.TryParse(
                trimmed,
                NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture,
                out var amount))
        {
            error = $"formato numérico inválido ('{raw}').";
            return false;
        }

        try
        {
            cents = MoneyConverter.ConvertDecimalToCents(amount);
            return true;
        }
        catch (InvalidOperationException)
        {
            error = $"valor '{raw}' contém fração de centavo (ADR-013).";
            return false;
        }
    }

    [GeneratedRegex(@"<!--.*?-->", RegexOptions.Singleline)]
    private static partial Regex XmlCommentRegex();

    [GeneratedRegex(@"<STMTTRN>(.*?)</STMTTRN>", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex ClosedStmtTrnRegex();

    [GeneratedRegex(@"<STMTTRN>", RegexOptions.IgnoreCase)]
    private static partial Regex OpenStmtTrnRegex();

    [GeneratedRegex(@"\s+")]
    private static partial Regex CollapseWhitespaceRegex();

    [GeneratedRegex(@"^(\d{4})(\d{2})(\d{2})(?:(\d{2})(\d{2})(\d{2})(?:\.\d+)?)?(?:\[([+-]?\d+(?:[:.]\d+)?)(?::[^\]]*)?\])?$")]
    private static partial Regex OfxDateRegex();
}
