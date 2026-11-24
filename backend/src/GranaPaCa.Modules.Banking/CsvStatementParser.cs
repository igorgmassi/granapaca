using System.Globalization;
using System.Text;
using System.Text.Json;
using GranaPaCa.Modules.Categorization.Contracts;

namespace GranaPaCa.Modules.Banking;

internal static class CsvStatementParser
{
    private static readonly HashSet<string> DateHeaders = new(StringComparer.Ordinal)
    {
        "data",
        "date",
        "data lancamento",
        "data do lancamento",
        "data transacao",
        "data da transacao",
        "data movimento",
        "data operacao",
        "data compra",
        "data da compra",
        "dt",
        "dt lancamento",
        "occurred on"
    };

    private static readonly HashSet<string> DescriptionHeaders = new(StringComparer.Ordinal)
    {
        "descricao",
        "description",
        "historico",
        "lancamento",
        "estabelecimento",
        "titulo",
        "title",
        "memo",
        "detalhes",
        "nome",
        "discriminacao"
    };

    private static readonly HashSet<string> AmountHeaders = new(StringComparer.Ordinal)
    {
        "valor",
        "amount",
        "valor r",
        "valor brl",
        "valor em reais",
        "quantia",
        "montante",
        "valor total"
    };

    private static readonly HashSet<string> ExternalIdHeaders = new(StringComparer.Ordinal)
    {
        "id",
        "identificador",
        "fitid",
        "codigo",
        "codigo transacao",
        "external id"
    };

    private static readonly string[] DateFormats =
    [
        "dd/MM/yyyy",
        "d/M/yyyy",
        "yyyy-MM-dd",
        "dd-MM-yyyy",
        "d-M-yyyy"
    ];

    public static (bool Ok, string? Error, ParsedStatement? Statement) Parse(
        string content,
        TimeZoneInfo instanceTimeZone)
    {
        if (string.IsNullOrWhiteSpace(content))
        {
            return (false, "Arquivo CSV vazio.", null);
        }

        var cleaned = content.TrimStart('\uFEFF');

        if (!TryDetectDelimiterAndHeader(
                cleaned,
                out var delimiter,
                out var records,
                out var headerRowIndex,
                out var dateCol,
                out var descriptionCol,
                out var amountCol,
                out var externalIdCol))
        {
            return (false, "Cabeçalho CSV inválido: informe colunas de Data, Descrição e Valor.", null);
        }

        var transactions = new List<ParsedStatementTransaction>();
        var occurrenceCounts = new Dictionary<(DateOnly, long, string), int>();

        for (var i = headerRowIndex + 1; i < records.Count; i++)
        {
            var row = records[i];
            if (IsBlankRow(row))
            {
                continue;
            }

            var lineNumber = i + 1;
            var maxRequiredCol = Math.Max(dateCol, Math.Max(descriptionCol, amountCol));
            if (row.Count <= maxRequiredCol)
            {
                return (false, $"Linha {lineNumber} do CSV não possui todas as colunas esperadas.", null);
            }

            var rawDate = row[dateCol].Trim();
            var rawDescription = row[descriptionCol].Trim();
            var rawAmount = row[amountCol].Trim();
            var rawExternalId = externalIdCol >= 0 && externalIdCol < row.Count
                ? row[externalIdCol].Trim()
                : null;

            if (!TryParseCsvDate(rawDate, instanceTimeZone, out var occurredOn))
            {
                return (false, $"Data inválida na linha {lineNumber} do CSV: '{rawDate}'.", null);
            }

            if (string.IsNullOrWhiteSpace(rawDescription))
            {
                return (false, $"Descrição vazia na linha {lineNumber} do CSV.", null);
            }

            if (!TryParseBrazilianOrIsoAmount(rawAmount, out var amountCents, out var amountError))
            {
                return (false, $"Valor inválido na linha {lineNumber} do CSV: {amountError}", null);
            }

            string externalId;
            if (!string.IsNullOrWhiteSpace(rawExternalId))
            {
                externalId = $"csv:id:{rawExternalId}";
            }
            else
            {
                var normalizedDesc = MerchantNormalizer.NormalizeDescription(rawDescription);
                var key = (occurredOn, amountCents, normalizedDesc);
                var occurrenceIndex = occurrenceCounts.GetValueOrDefault(key, 0);
                occurrenceCounts[key] = occurrenceIndex + 1;
                externalId = $"csv:{StatementIdHelper.ComputeDeterministicHash(occurredOn, amountCents, rawDescription, occurrenceIndex)}";
            }

            var rawPayloadJson = JsonSerializer.Serialize(new
            {
                format = "csv",
                delimiter = delimiter.ToString(),
                lineNumber,
                date = rawDate,
                description = rawDescription,
                amount = rawAmount,
                externalId = rawExternalId
            });

            transactions.Add(new ParsedStatementTransaction(
                externalId,
                occurredOn,
                rawDescription,
                amountCents,
                rawPayloadJson));
        }

        if (transactions.Count == 0)
        {
            return (false, "Nenhuma transação encontrada no arquivo CSV.", null);
        }

        var statement = new ParsedStatement(
            "csv",
            BankId: null,
            AccountId: null,
            AccountKind: null,
            InstitutionName: null,
            LedgerBalanceCents: null,
            Transactions: transactions);

        return (true, null, statement);
    }

    private static bool TryDetectDelimiterAndHeader(
        string content,
        out char detectedDelimiter,
        out List<List<string>> parsedRecords,
        out int headerRowIndex,
        out int dateCol,
        out int descriptionCol,
        out int amountCol,
        out int externalIdCol)
    {
        detectedDelimiter = ';';
        parsedRecords = [];
        headerRowIndex = -1;
        dateCol = -1;
        descriptionCol = -1;
        amountCol = -1;
        externalIdCol = -1;

        var firstLine = GetFirstNonEmptyLine(content);
        var semicolonCount = CountUnquoted(firstLine, ';');
        var commaCount = CountUnquoted(firstLine, ',');

        char[] candidates = semicolonCount >= commaCount ? [';', ','] : [',', ';'];

        foreach (var candidate in candidates)
        {
            var records = ParseCsvRecords(content, candidate);
            var maxScan = Math.Min(records.Count, 15);

            for (var r = 0; r < maxScan; r++)
            {
                var row = records[r];
                if (row.Count < 3 || IsBlankRow(row))
                {
                    continue;
                }

                var dCol = -1;
                var descCol = -1;
                var amtCol = -1;
                var idCol = -1;

                for (var c = 0; c < row.Count; c++)
                {
                    var normHeader = MerchantNormalizer.NormalizeDescription(row[c]);
                    if (dCol < 0 && DateHeaders.Contains(normHeader))
                    {
                        dCol = c;
                    }
                    else if (descCol < 0 && DescriptionHeaders.Contains(normHeader))
                    {
                        descCol = c;
                    }
                    else if (amtCol < 0 && AmountHeaders.Contains(normHeader))
                    {
                        amtCol = c;
                    }
                    else if (idCol < 0 && ExternalIdHeaders.Contains(normHeader))
                    {
                        idCol = c;
                    }
                }

                if (dCol >= 0 && descCol >= 0 && amtCol >= 0)
                {
                    detectedDelimiter = candidate;
                    parsedRecords = records;
                    headerRowIndex = r;
                    dateCol = dCol;
                    descriptionCol = descCol;
                    amountCol = amtCol;
                    externalIdCol = idCol;
                    return true;
                }
            }
        }

        return false;
    }

    private static string GetFirstNonEmptyLine(string content)
    {
        using var reader = new StringReader(content);
        while (reader.ReadLine() is { } line)
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                return line;
            }
        }

        return string.Empty;
    }

    private static int CountUnquoted(string line, char target)
    {
        var inQuotes = false;
        var count = 0;
        foreach (var ch in line)
        {
            if (ch == '"')
            {
                inQuotes = !inQuotes;
            }
            else if (!inQuotes && ch == target)
            {
                count++;
            }
        }

        return count;
    }

    private static List<List<string>> ParseCsvRecords(string content, char delimiter)
    {
        var records = new List<List<string>>();
        var currentRow = new List<string>();
        var field = new StringBuilder();
        var inQuotes = false;

        for (var i = 0; i < content.Length; i++)
        {
            var ch = content[i];

            if (inQuotes)
            {
                if (ch == '"')
                {
                    if (i + 1 < content.Length && content[i + 1] == '"')
                    {
                        field.Append('"');
                        i++;
                    }
                    else
                    {
                        inQuotes = false;
                    }
                }
                else
                {
                    field.Append(ch);
                }

                continue;
            }

            if (ch == '"' && field.Length == 0)
            {
                inQuotes = true;
            }
            else if (ch == delimiter)
            {
                currentRow.Add(field.ToString());
                field.Clear();
            }
            else if (ch == '\r' || ch == '\n')
            {
                if (ch == '\r' && i + 1 < content.Length && content[i + 1] == '\n')
                {
                    i++;
                }

                currentRow.Add(field.ToString());
                field.Clear();
                records.Add(currentRow);
                currentRow = [];
            }
            else
            {
                field.Append(ch);
            }
        }

        if (field.Length > 0 || currentRow.Count > 0)
        {
            currentRow.Add(field.ToString());
            records.Add(currentRow);
        }

        return records;
    }

    private static bool IsBlankRow(List<string> row)
    {
        for (var i = 0; i < row.Count; i++)
        {
            if (!string.IsNullOrWhiteSpace(row[i]))
            {
                return false;
            }
        }

        return true;
    }

    private static bool TryParseCsvDate(
        string raw,
        TimeZoneInfo instanceTimeZone,
        out DateOnly date)
    {
        date = default;
        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        var trimmed = raw.Trim();
        if (DateOnly.TryParseExact(
                trimmed,
                DateFormats,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out date))
        {
            return true;
        }

        if (trimmed.Contains('T', StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                date = DateParser.ParseProviderDate(trimmed, instanceTimeZone);
                return true;
            }
            catch (FormatException)
            {
                return false;
            }
        }

        return false;
    }

    private static bool TryParseBrazilianOrIsoAmount(
        string raw,
        out long cents,
        out string? error)
    {
        cents = 0;
        error = null;

        if (string.IsNullOrWhiteSpace(raw))
        {
            error = "valor vazio.";
            return false;
        }

        var cleaned = raw.Trim()
            .Replace("R$", string.Empty, StringComparison.OrdinalIgnoreCase)
            .Replace("\u00A0", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal);

        var negative = false;
        if (cleaned.StartsWith('(') && cleaned.EndsWith(')') && cleaned.Length > 2)
        {
            negative = true;
            cleaned = cleaned[1..^1];
        }

        if (cleaned.StartsWith('-'))
        {
            negative = !negative;
            cleaned = cleaned[1..];
        }
        else if (cleaned.StartsWith('+'))
        {
            cleaned = cleaned[1..];
        }
        else if (cleaned.EndsWith('-'))
        {
            negative = !negative;
            cleaned = cleaned[..^1];
        }

        if (cleaned.Length == 0)
        {
            error = $"formato numérico inválido ('{raw}').";
            return false;
        }

        var lastDot = cleaned.LastIndexOf('.');
        var lastComma = cleaned.LastIndexOf(',');

        string normalized;
        if (lastDot >= 0 && lastComma >= 0)
        {
            if (lastComma > lastDot)
            {
                // Brazilian format: 1.234,56
                normalized = cleaned.Replace(".", string.Empty, StringComparison.Ordinal)
                    .Replace(',', '.');
            }
            else
            {
                // US/ISO format: 1,234.56
                normalized = cleaned.Replace(",", string.Empty, StringComparison.Ordinal);
            }
        }
        else if (lastComma >= 0)
        {
            var commaCount = cleaned.Count(c => c == ',');
            normalized = commaCount > 1
                ? cleaned.Replace(",", string.Empty, StringComparison.Ordinal)
                : cleaned.Replace(',', '.');
        }
        else if (lastDot >= 0)
        {
            var dotCount = cleaned.Count(c => c == '.');
            normalized = dotCount > 1
                ? cleaned.Replace(".", string.Empty, StringComparison.Ordinal)
                : cleaned;
        }
        else
        {
            normalized = cleaned;
        }

        if (negative)
        {
            normalized = "-" + normalized;
        }

        if (!decimal.TryParse(
                normalized,
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
}
