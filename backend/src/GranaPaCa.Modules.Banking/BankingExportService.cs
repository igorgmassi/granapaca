using System.Data;
using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using Dapper;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class BankingExportService(
    NpgsqlDataSource dataSource,
    BankingAnalyticsService analytics,
    IConfiguration configuration)
{
    private const string CsvHeader =
        "Data;Descrição;Descrição Original;Conta;Banco;Tipo;Forma de Pagamento;Categoria;Essencialidade;Atípica;Tags;Valor (R$)";

    private static readonly UTF8Encoding Utf8WithBom = new(encoderShouldEmitUTF8Identifier: true);

    private static readonly JsonSerializerOptions BackupJsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    private static readonly string[] PortugueseMonthNames =
    [
        "Janeiro",
        "Fevereiro",
        "Março",
        "Abril",
        "Maio",
        "Junho",
        "Julho",
        "Agosto",
        "Setembro",
        "Outubro",
        "Novembro",
        "Dezembro"
    ];

    private readonly TimeZoneInfo _instanceTimeZone = DateParser.ResolveInstanceTimeZone(configuration);

    public async Task<(bool Ok, string? Error, byte[]? Bytes, string FileName)> ExportTransactionsCsvAsync(
        Guid householdId,
        DateOnly? from,
        DateOnly? to,
        CancellationToken cancellationToken)
    {
        if (from.HasValue && to.HasValue && from.Value > to.Value)
        {
            return (false, "A data inicial não pode ser posterior à data final.", null, string.Empty);
        }

        var where = new StringBuilder("WHERE te.household_id = @HouseholdId");
        var parameters = new DynamicParameters();
        parameters.Add("HouseholdId", householdId);

        if (from.HasValue)
        {
            where.Append(" AND te.occurred_on >= @From");
            parameters.Add("From", from.Value);
        }

        if (to.HasValue)
        {
            where.Append(" AND te.occurred_on <= @To");
            parameters.Add("To", to.Value);
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var rows = (await connection.QueryAsync<CsvTransactionRow>(new CommandDefinition(
            $"""
            SELECT
                te.id AS Id,
                te.occurred_on AS OccurredOn,
                te.effective_description AS EffectiveDescription,
                te.original_description AS OriginalDescription,
                te.account_name AS AccountName,
                te.institution_name AS InstitutionName,
                te.effective_kind AS EffectiveKind,
                te.effective_payment_method AS EffectivePaymentMethod,
                te.effective_category AS EffectiveCategory,
                te.effective_essentiality AS EffectiveEssentiality,
                te.effective_is_atypical AS EffectiveIsAtypical,
                te.amount_cents AS AmountCents
            FROM banking.transaction_effective te
            {where}
            ORDER BY te.occurred_on DESC, te.id DESC
            """,
            parameters,
            cancellationToken: cancellationToken))).ToList();

        var tagsByTx = await BankingQueries.LoadTagsByTransactionIdsAsync(
            connection,
            rows.Select(r => r.Id).ToArray(),
            cancellationToken);

        var sb = new StringBuilder();
        sb.Append(CsvHeader);
        sb.Append("\r\n");

        foreach (var row in rows)
        {
            var tagsText = tagsByTx.TryGetValue(row.Id, out var tags)
                ? string.Join(", ", tags)
                : string.Empty;

            var categoryLabel = row.EffectiveCategory is null
                ? BankingTaxonomy.GetCategoryLabel("uncategorized")
                : BankingTaxonomy.GetCategoryLabel(row.EffectiveCategory);

            var textFields = new[]
            {
                row.OccurredOn.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture),
                row.EffectiveDescription,
                row.OriginalDescription,
                row.AccountName,
                row.InstitutionName,
                BankingTaxonomy.GetKindLabel(row.EffectiveKind),
                BankingTaxonomy.GetPaymentMethodLabel(row.EffectivePaymentMethod),
                categoryLabel,
                BankingTaxonomy.GetEssentialityLabel(row.EffectiveEssentiality),
                row.EffectiveIsAtypical ? "Sim" : "Não",
                tagsText
            };

            for (var i = 0; i < textFields.Length; i++)
            {
                if (i > 0)
                {
                    sb.Append(';');
                }

                sb.Append(EscapeCsvTextField(textFields[i]));
            }

            // Preserve numeric monetary column ("Valor (R$)") intact without formula-neutralizing prefix.
            sb.Append(';');
            sb.Append(EscapeCsvField(MoneyConverter.FormatCsvBrl(row.AmountCents)));

            sb.Append("\r\n");
        }

        var preamble = Utf8WithBom.GetPreamble();
        var body = Utf8WithBom.GetBytes(sb.ToString());
        var payload = new byte[preamble.Length + body.Length];
        Buffer.BlockCopy(preamble, 0, payload, 0, preamble.Length);
        Buffer.BlockCopy(body, 0, payload, preamble.Length, body.Length);

        return (true, null, payload, "granapaca-transacoes.csv");
    }

    public async Task<(byte[] Bytes, string FileName)> ExportBackupJsonAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var dbTx = await connection.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);

        await connection.ExecuteAsync(new CommandDefinition(
            "SET TRANSACTION READ ONLY",
            transaction: dbTx,
            cancellationToken: cancellationToken));

        var exportedAt = (await connection.ExecuteScalarAsync<DateTimeOffset>(new CommandDefinition(
            "SELECT now()",
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToUniversalTime();

        var param = new { HouseholdId = householdId };

        var connections = (await connection.QueryAsync<ExportBackupConnectionDto>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                provider AS Provider,
                external_item_id AS ExternalItemId,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
                status AS Status,
                consent_expires_at AS ConsentExpiresAt,
                last_synced_at AS LastSyncedAt,
                last_error_code AS LastErrorCode,
                consecutive_failures AS ConsecutiveFailures,
                created_at AS CreatedAt
            FROM banking.connection
            WHERE household_id = @HouseholdId
            ORDER BY created_at ASC, id ASC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var accounts = (await connection.QueryAsync<ExportBackupAccountDto>(new CommandDefinition(
            """
            SELECT
                a.id AS Id,
                a.connection_id AS ConnectionId,
                a.external_account_id AS ExternalAccountId,
                a.name AS Name,
                a.kind AS Kind,
                a.last_four_digits AS LastFourDigits,
                a.currency AS Currency,
                a.opening_balance_cents AS OpeningBalanceCents,
                COALESCE(
                    (SELECT bs.balance_cents
                     FROM banking.balance_snapshot bs
                     WHERE bs.account_id = a.id
                     ORDER BY bs.captured_at DESC, bs.id DESC
                     LIMIT 1),
                    a.opening_balance_cents
                ) AS CurrentBalanceCents,
                a.created_at AS CreatedAt
            FROM banking.account a
            WHERE a.household_id = @HouseholdId
            ORDER BY a.created_at ASC, a.id ASC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var cardBills = (await connection.QueryAsync<ExportBackupCardBillDto>(new CommandDefinition(
            """
            SELECT
                cb.id AS Id,
                cb.account_id AS AccountId,
                cb.external_bill_id AS ExternalBillId,
                cb.period_month AS PeriodMonth,
                cb.closing_on AS ClosingOn,
                cb.due_on AS DueOn,
                cb.total_cents AS TotalCents,
                cb.is_open AS IsOpen,
                cb.updated_at AS UpdatedAt
            FROM banking.card_bill cb
            JOIN banking.account a ON a.id = cb.account_id
            WHERE a.household_id = @HouseholdId
            ORDER BY cb.period_month DESC, cb.due_on DESC, cb.id ASC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var tags = (await connection.QueryAsync<ExportBackupTagDto>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                name AS Name,
                color AS Color,
                created_at AS CreatedAt
            FROM banking.tag
            WHERE household_id = @HouseholdId
            ORDER BY lower(name) ASC, id ASC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var adjustments = (await connection.QueryAsync<ExportBackupAdjustmentDto>(new CommandDefinition(
            """
            SELECT
                adj.id AS Id,
                adj.transaction_id AS TransactionId,
                adj.field_name AS FieldName,
                adj.old_value AS OldValue,
                adj.new_value AS NewValue,
                adj.reason AS Reason,
                adj.undoes_id AS UndoesId,
                adj.created_at AS CreatedAt
            FROM banking.adjustment adj
            JOIN banking.transaction t ON t.id = adj.transaction_id
            WHERE t.household_id = @HouseholdId
            ORDER BY adj.created_at ASC, adj.id ASC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var splits = (await connection.QueryAsync<ExportBackupSplitDto>(new CommandDefinition(
            """
            SELECT
                s.id AS Id,
                s.transaction_id AS TransactionId,
                s.part_index AS PartIndex,
                s.description AS Description,
                s.amount_cents AS AmountCents,
                s.category AS Category,
                s.essentiality AS Essentiality,
                s.created_at AS CreatedAt
            FROM banking.transaction_split s
            JOIN banking.transaction t ON t.id = s.transaction_id
            WHERE t.household_id = @HouseholdId
            ORDER BY s.transaction_id ASC, s.part_index ASC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var txRows = (await connection.QueryAsync<BackupTransactionRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                account_id AS AccountId,
                account_name AS AccountName,
                account_kind AS AccountKind,
                connection_id AS BankId,
                institution_name AS InstitutionName,
                version_number AS VersionNumber,
                occurred_on AS OccurredOn,
                purchase_on AS PurchaseOn,
                original_description AS OriginalDescription,
                merchant_cnpj AS MerchantCnpj,
                amount_cents AS AmountCents,
                currency AS Currency,
                status AS Status,
                bill_id AS BillId,
                installment_number AS InstallmentNumber,
                installment_total AS InstallmentTotal,
                ingested_at AS IngestedAt,
                effective_description AS EffectiveDescription,
                effective_kind AS EffectiveKind,
                effective_category AS EffectiveCategory,
                effective_essentiality AS EffectiveEssentiality,
                effective_brand AS EffectiveBrand,
                original_payment_method AS OriginalPaymentMethod,
                effective_payment_method AS EffectivePaymentMethod,
                effective_is_atypical AS EffectiveIsAtypical,
                classified_kind AS ClassifiedKind,
                classified_category AS ClassifiedCategory,
                classified_essentiality AS ClassifiedEssentiality,
                classified_brand AS ClassifiedBrand,
                deciding_layer AS DecidingLayer,
                deciding_rule_id AS DecidingRuleId,
                deciding_rule_name AS DecidingRuleName,
                explanation AS Explanation,
                has_manual_adjustments AS HasManualAdjustments
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
            ORDER BY occurred_on DESC, id DESC
            """,
            param,
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var tagsByTx = await BankingQueries.LoadTagsByTransactionIdsAsync(
            connection,
            txRows.Select(r => r.Id).ToArray(),
            cancellationToken,
            dbTx);

        await dbTx.CommitAsync(cancellationToken);

        var splitsByTx = splits
            .GroupBy(s => s.TransactionId)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<ExportBackupSplitDto>)g.ToList());

        var adjustmentsByTx = adjustments
            .GroupBy(a => a.TransactionId)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<ExportBackupAdjustmentDto>)g.ToList());

        var transactions = txRows
            .Select(r => new ExportBackupTransactionDto(
                r.Id,
                r.AccountId,
                r.AccountName,
                r.AccountKind,
                r.BankId,
                r.InstitutionName,
                r.Currency,
                r.Status,
                r.BillId,
                r.InstallmentNumber,
                r.InstallmentTotal,
                r.HasManualAdjustments,
                r.IngestedAt,
                new TransactionOriginalFieldsDto(
                    r.OriginalDescription,
                    r.MerchantCnpj,
                    r.OccurredOn,
                    r.PurchaseOn,
                    r.AmountCents,
                    r.VersionNumber,
                    r.OriginalPaymentMethod),
                new TransactionEffectiveFieldsDto(
                    r.EffectiveDescription,
                    r.EffectiveKind,
                    r.EffectiveCategory,
                    r.EffectiveEssentiality,
                    r.EffectiveBrand,
                    r.EffectivePaymentMethod,
                    r.EffectiveIsAtypical),
                new TransactionClassificationDto(
                    r.ClassifiedKind,
                    r.ClassifiedCategory,
                    r.ClassifiedEssentiality,
                    r.ClassifiedBrand,
                    r.DecidingLayer,
                    r.DecidingRuleId,
                    r.DecidingRuleName,
                    r.Explanation),
                tagsByTx.TryGetValue(r.Id, out var txTags) ? txTags : [],
                splitsByTx.TryGetValue(r.Id, out var txSplits) ? txSplits : [],
                adjustmentsByTx.TryGetValue(r.Id, out var txAdjs) ? txAdjs : []))
            .ToList();

        var backup = new ExportBackupResponse(
            "1.0",
            exportedAt,
            householdId,
            connections,
            accounts,
            cardBills,
            tags,
            transactions,
            adjustments,
            splits);

        var bytes = JsonSerializer.SerializeToUtf8Bytes(backup, BackupJsonOptions);
        var fileName = $"granapaca-backup-{exportedAt:yyyyMMdd}.json";
        return (bytes, fileName);
    }

    public async Task<(bool Ok, string? Error, string? Html)> ExportMonthlyReportHtmlAsync(
        Guid householdId,
        string? month,
        CancellationToken cancellationToken)
    {
        DateOnly monthStart;
        if (string.IsNullOrWhiteSpace(month))
        {
            var today = DateParser.TodayInTimeZone(_instanceTimeZone);
            monthStart = new DateOnly(today.Year, today.Month, 1);
        }
        else if (!DateOnly.TryParseExact(
            month.Trim() + "-01",
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out monthStart))
        {
            return (false, "Mês inválido; use o formato YYYY-MM.", null);
        }

        var metrics = await analytics.GetMonthMetricsAsync(householdId, monthStart, cancellationToken);
        var transactions = await analytics.GetTransactionsInRangeAsync(
            householdId,
            monthStart,
            monthStart.AddMonths(1),
            cancellationToken);

        var monthTitle = $"{PortugueseMonthNames[monthStart.Month - 1]} de {monthStart.Year}";
        var generatedAt = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, _instanceTimeZone)
            .ToString("dd/MM/yyyy 'às' HH:mm", CultureInfo.InvariantCulture);

        var totalEssentialityBase = metrics.SpentCents > 0 ? metrics.SpentCents : 0L;
        var essentialPct = ComputePercent(metrics.EssentialSpentCents, totalEssentialityBase);
        var importantPct = ComputePercent(metrics.ImportantSpentCents, totalEssentialityBase);
        var flexiblePct = ComputePercent(metrics.FlexibleSpentCents, totalEssentialityBase);
        var unclassifiedEssentialityCents = Math.Max(
            0L,
            metrics.SpentCents - metrics.EssentialSpentCents - metrics.ImportantSpentCents - metrics.FlexibleSpentCents);
        var unclassifiedPct = ComputePercent(unclassifiedEssentialityCents, totalEssentialityBase);

        var sb = new StringBuilder(8192);
        sb.Append("""
            <!DOCTYPE html>
            <html lang="pt-BR">
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
            """);
        sb.Append($"  <title>GranaPaCá — Relatório de {Html(monthTitle)}</title>\n");
        sb.Append("""
              <style>
                :root {
                  --bg: #FAF7F2;
                  --card: #FFFFFF;
                  --ink: #1F1B18;
                  --muted: #6E655E;
                  --border: #E6DDD2;
                  --accent: #A0521A;
                  --positive: #1F6E4A;
                  --negative: #A6322B;
                  --bar-bg: #EFE7DD;
                }
                * { box-sizing: border-box; }
                body {
                  margin: 0;
                  padding: 32px 24px;
                  background: var(--bg);
                  color: var(--ink);
                  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                  line-height: 1.45;
                }
                .container { max-width: 980px; margin: 0 auto; }
                header {
                  display: flex;
                  justify-content: space-between;
                  align-items: baseline;
                  flex-wrap: wrap;
                  gap: 12px;
                  border-bottom: 2px solid var(--accent);
                  padding-bottom: 14px;
                  margin-bottom: 24px;
                }
                h1 { margin: 0; font-size: 24px; color: var(--ink); }
                .subtitle { color: var(--muted); font-size: 13px; }
                h2 {
                  margin: 28px 0 12px;
                  font-size: 16px;
                  text-transform: uppercase;
                  letter-spacing: 0.04em;
                  color: var(--accent);
                }
                .grid {
                  display: grid;
                  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
                  gap: 12px;
                }
                .card {
                  background: var(--card);
                  border: 1px solid var(--border);
                  border-radius: 10px;
                  padding: 14px 16px;
                }
                .card-label { font-size: 12px; color: var(--muted); margin-bottom: 4px; }
                .card-value { font-size: 20px; font-weight: 700; font-variant-numeric: tabular-nums; }
                .positive { color: var(--positive); }
                .negative { color: var(--negative); }
                .panel {
                  background: var(--card);
                  border: 1px solid var(--border);
                  border-radius: 10px;
                  padding: 16px;
                }
                .rule-row { margin-bottom: 12px; }
                .rule-row:last-child { margin-bottom: 0; }
                .rule-header {
                  display: flex;
                  justify-content: space-between;
                  font-size: 13px;
                  margin-bottom: 4px;
                }
                .bar-track {
                  height: 10px;
                  background: var(--bar-bg);
                  border-radius: 999px;
                  overflow: hidden;
                }
                .bar-fill {
                  height: 100%;
                  background: var(--accent);
                  border-radius: 999px;
                }
                table {
                  width: 100%;
                  border-collapse: collapse;
                  background: var(--card);
                  border: 1px solid var(--border);
                  border-radius: 10px;
                  overflow: hidden;
                  font-size: 13px;
                }
                th, td {
                  padding: 9px 10px;
                  border-bottom: 1px solid var(--border);
                  text-align: left;
                  vertical-align: top;
                }
                th {
                  background: #F4EDE4;
                  font-weight: 600;
                  font-size: 12px;
                  color: var(--muted);
                }
                tr:last-child td { border-bottom: none; }
                .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
                .badge {
                  display: inline-block;
                  padding: 1px 6px;
                  border-radius: 999px;
                  font-size: 11px;
                  background: #F4E4D8;
                  color: var(--accent);
                  margin-left: 4px;
                }
                .empty { color: var(--muted); font-size: 13px; margin: 8px 0 0; }
                footer {
                  margin-top: 28px;
                  font-size: 12px;
                  color: var(--muted);
                  text-align: center;
                }
                @media print {
                  body { background: #FFFFFF; padding: 0; }
                  .card, .panel, table { break-inside: avoid; }
                  tr { break-inside: avoid; }
                }
              </style>
            </head>
            <body>
              <div class="container">
                <header>
            """);

        sb.Append($"      <h1>GranaPaCá — Relatório Mensal ({Html(monthTitle)})</h1>\n");
        sb.Append($"      <div class=\"subtitle\">Referência: {Html(metrics.Month)} · Gerado em {Html(generatedAt)}</div>\n");
        sb.Append("    </header>\n\n");

        sb.Append("    <h2>Resumo do mês</h2>\n");
        sb.Append("    <div class=\"grid\">\n");
        AppendSummaryCard(sb, "Saldo em contas", MoneyConverter.FormatBrl(metrics.BalanceCents), metrics.BalanceCents >= 0 ? "positive" : "negative");
        AppendSummaryCard(sb, "Receitas", MoneyConverter.FormatBrl(metrics.ReceivedCents), "positive");
        AppendSummaryCard(sb, "Despesas", MoneyConverter.FormatBrl(metrics.SpentCents), "negative");
        AppendSummaryCard(sb, "Sobra do mês", MoneyConverter.FormatBrl(metrics.LeftoverCents), metrics.LeftoverCents >= 0 ? "positive" : "negative");
        AppendSummaryCard(sb, "Fatura em aberto", MoneyConverter.FormatBrl(metrics.CardBillCents), string.Empty);
        AppendSummaryCard(sb, "Gastos atípicos", MoneyConverter.FormatBrl(metrics.AtypicalSpentCents), string.Empty);
        sb.Append("    </div>\n\n");

        sb.Append("    <h2>Regra 50/30/20 — Essencialidade</h2>\n");
        sb.Append("    <div class=\"panel\">\n");
        AppendRuleBar(sb, "Essenciais (meta 50%)", metrics.EssentialSpentCents, essentialPct);
        AppendRuleBar(sb, "Importantes (meta 30%)", metrics.ImportantSpentCents, importantPct);
        AppendRuleBar(sb, "Flexíveis (meta 20%)", metrics.FlexibleSpentCents, flexiblePct);
        if (unclassifiedEssentialityCents > 0)
        {
            AppendRuleBar(sb, "Sem essencialidade definida", unclassifiedEssentialityCents, unclassifiedPct);
        }

        sb.Append("    </div>\n\n");

        sb.Append("    <h2>Gastos por categoria</h2>\n");
        if (metrics.SpentByCategoryCents.Count == 0)
        {
            sb.Append("    <p class=\"empty\">Nenhuma despesa registrada neste mês.</p>\n");
        }
        else
        {
            sb.Append("    <table>\n");
            sb.Append("      <thead><tr><th>Categoria</th><th class=\"num\">Valor</th><th class=\"num\">Participação</th></tr></thead>\n");
            sb.Append("      <tbody>\n");
            var totalCat = metrics.SpentByCategoryCents.Values.Sum();
            foreach (var (catKey, catCents) in metrics.SpentByCategoryCents)
            {
                var share = ComputePercent(catCents, totalCat);
                sb.Append("        <tr>");
                sb.Append($"<td>{Html(BankingTaxonomy.GetCategoryLabel(catKey))}</td>");
                sb.Append($"<td class=\"num\">{Html(MoneyConverter.FormatBrl(catCents))}</td>");
                sb.Append($"<td class=\"num\">{share.ToString("0.0", CultureInfo.InvariantCulture).Replace('.', ',')}%</td>");
                sb.Append("</tr>\n");
            }

            sb.Append("      </tbody>\n");
            sb.Append("    </table>\n");
        }

        sb.Append("\n    <h2>Lançamentos do mês</h2>\n");
        if (transactions.Count == 0)
        {
            sb.Append("    <p class=\"empty\">Nenhum lançamento encontrado neste mês.</p>\n");
        }
        else
        {
            sb.Append("    <table>\n");
            sb.Append("      <thead><tr><th>Data</th><th>Descrição</th><th>Conta / Banco</th><th>Pagamento</th><th>Categoria</th><th>Essencialidade</th><th>Tags</th><th class=\"num\">Valor</th></tr></thead>\n");
            sb.Append("      <tbody>\n");

            foreach (var tx in transactions)
            {
                var dateText = tx.OccurredOn.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
                var accountText = $"{tx.AccountName} ({tx.InstitutionName})";
                var paymentText = BankingTaxonomy.GetPaymentMethodLabel(tx.PaymentMethod);
                var categoryText = tx.Category is null
                    ? BankingTaxonomy.GetCategoryLabel("uncategorized")
                    : BankingTaxonomy.GetCategoryLabel(tx.Category);
                var essentialityText = BankingTaxonomy.GetEssentialityLabel(tx.Essentiality);
                var tagsText = tx.Tags.Count > 0 ? string.Join(", ", tx.Tags) : string.Empty;
                var amountClass = tx.AmountCents < 0 ? "num negative" : "num positive";
                var atypicalBadge = tx.IsAtypical ? "<span class=\"badge\">Atípica</span>" : string.Empty;

                sb.Append("        <tr>");
                sb.Append($"<td>{Html(dateText)}</td>");
                sb.Append($"<td>{Html(tx.Description)}{atypicalBadge}</td>");
                sb.Append($"<td>{Html(accountText)}</td>");
                sb.Append($"<td>{Html(paymentText)}</td>");
                sb.Append($"<td>{Html(categoryText)}</td>");
                sb.Append($"<td>{Html(essentialityText)}</td>");
                sb.Append($"<td>{Html(tagsText)}</td>");
                sb.Append($"<td class=\"{amountClass}\">{Html(MoneyConverter.FormatBrl(tx.AmountCents))}</td>");
                sb.Append("</tr>\n");
            }

            sb.Append("      </tbody>\n");
            sb.Append("    </table>\n");
        }

        sb.Append("""
                <footer>Relatório gerado localmente pela sua instância do GranaPaCá.</footer>
              </div>
            </body>
            </html>
            """);

        return (true, null, sb.ToString());
    }

    private static void AppendSummaryCard(StringBuilder sb, string label, string value, string cssClass)
    {
        var classAttr = string.IsNullOrEmpty(cssClass) ? "card-value" : $"card-value {cssClass}";
        sb.Append("      <div class=\"card\">");
        sb.Append($"<div class=\"card-label\">{Html(label)}</div>");
        sb.Append($"<div class=\"{classAttr}\">{Html(value)}</div>");
        sb.Append("</div>\n");
    }

    private static void AppendRuleBar(StringBuilder sb, string label, long cents, decimal percent)
    {
        var clampedWidth = Math.Clamp(percent, 0m, 100m).ToString("0.#", CultureInfo.InvariantCulture);
        var pctLabel = percent.ToString("0.0", CultureInfo.InvariantCulture).Replace('.', ',');
        sb.Append("      <div class=\"rule-row\">\n");
        sb.Append($"        <div class=\"rule-header\"><span>{Html(label)}</span><span>{Html(MoneyConverter.FormatBrl(cents))} ({pctLabel}%)</span></div>\n");
        sb.Append($"        <div class=\"bar-track\"><div class=\"bar-fill\" style=\"width:{clampedWidth}%\"></div></div>\n");
        sb.Append("      </div>\n");
    }

    private static decimal ComputePercent(long partCents, long totalCents)
    {
        if (totalCents <= 0 || partCents <= 0)
        {
            return 0m;
        }

        return Math.Round((decimal)partCents * 100m / totalCents, 1);
    }

    private static string Html(string? text) =>
        string.IsNullOrEmpty(text) ? string.Empty : WebUtility.HtmlEncode(text);

    private static string EscapeCsvTextField(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        var sanitized = NeedsFormulaNeutralization(value) ? "'" + value : value;
        return EscapeCsvField(sanitized);
    }

    private static bool NeedsFormulaNeutralization(string value)
    {
        var first = value[0];
        if (first is '=' or '+' or '-' or '@' or '\t' or '\r')
        {
            return true;
        }

        var trimmedStart = value.AsSpan().TrimStart(' ');
        return !trimmedStart.IsEmpty && trimmedStart[0] is '=' or '+' or '-' or '@';
    }

    private static string EscapeCsvField(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        var needsQuotes = value.IndexOfAny([';', ',', '"', '\r', '\n']) >= 0;
        if (!needsQuotes)
        {
            return value;
        }

        return $"\"{value.Replace("\"", "\"\"", StringComparison.Ordinal)}\"";
    }

    private sealed record CsvTransactionRow(
        Guid Id,
        DateOnly OccurredOn,
        string EffectiveDescription,
        string OriginalDescription,
        string AccountName,
        string InstitutionName,
        string EffectiveKind,
        string? EffectivePaymentMethod,
        string? EffectiveCategory,
        string? EffectiveEssentiality,
        bool EffectiveIsAtypical,
        long AmountCents);

    private sealed record BackupTransactionRow(
        Guid Id,
        Guid AccountId,
        string AccountName,
        string AccountKind,
        Guid BankId,
        string InstitutionName,
        int VersionNumber,
        DateOnly OccurredOn,
        DateOnly? PurchaseOn,
        string OriginalDescription,
        string? MerchantCnpj,
        long AmountCents,
        string Currency,
        string Status,
        Guid? BillId,
        int? InstallmentNumber,
        int? InstallmentTotal,
        DateTimeOffset IngestedAt,
        string EffectiveDescription,
        string EffectiveKind,
        string? EffectiveCategory,
        string? EffectiveEssentiality,
        string? EffectiveBrand,
        string? OriginalPaymentMethod,
        string? EffectivePaymentMethod,
        bool EffectiveIsAtypical,
        string? ClassifiedKind,
        string? ClassifiedCategory,
        string? ClassifiedEssentiality,
        string? ClassifiedBrand,
        string DecidingLayer,
        Guid? DecidingRuleId,
        string? DecidingRuleName,
        string Explanation,
        bool HasManualAdjustments);
}

internal sealed record ExportBackupConnectionDto(
    Guid Id,
    string Provider,
    string ExternalItemId,
    string InstitutionName,
    string BrandColor,
    string Status,
    DateTimeOffset? ConsentExpiresAt,
    DateTimeOffset? LastSyncedAt,
    string? LastErrorCode,
    int ConsecutiveFailures,
    DateTimeOffset CreatedAt);

internal sealed record ExportBackupAccountDto(
    Guid Id,
    Guid ConnectionId,
    string ExternalAccountId,
    string Name,
    string Kind,
    string? LastFourDigits,
    string Currency,
    long OpeningBalanceCents,
    long CurrentBalanceCents,
    DateTimeOffset CreatedAt);

internal sealed record ExportBackupCardBillDto(
    Guid Id,
    Guid AccountId,
    string ExternalBillId,
    DateOnly PeriodMonth,
    DateOnly ClosingOn,
    DateOnly DueOn,
    long TotalCents,
    bool IsOpen,
    DateTimeOffset UpdatedAt);

internal sealed record ExportBackupTagDto(
    Guid Id,
    string Name,
    string Color,
    DateTimeOffset CreatedAt);

internal sealed record ExportBackupAdjustmentDto(
    Guid Id,
    Guid TransactionId,
    string FieldName,
    string? OldValue,
    string? NewValue,
    string? Reason,
    Guid? UndoesId,
    DateTimeOffset CreatedAt);

internal sealed record ExportBackupSplitDto(
    Guid Id,
    Guid TransactionId,
    int PartIndex,
    string Description,
    long AmountCents,
    string? Category,
    string? Essentiality,
    DateTimeOffset CreatedAt);

internal sealed record ExportBackupTransactionDto(
    Guid Id,
    Guid AccountId,
    string AccountName,
    string AccountKind,
    Guid BankId,
    string InstitutionName,
    string Currency,
    string Status,
    Guid? BillId,
    int? InstallmentNumber,
    int? InstallmentTotal,
    bool HasManualAdjustments,
    DateTimeOffset IngestedAt,
    TransactionOriginalFieldsDto Original,
    TransactionEffectiveFieldsDto Effective,
    TransactionClassificationDto Classification,
    IReadOnlyList<string> Tags,
    IReadOnlyList<ExportBackupSplitDto> Splits,
    IReadOnlyList<ExportBackupAdjustmentDto> Adjustments);

internal sealed record ExportBackupResponse(
    string SchemaVersion,
    DateTimeOffset ExportedAt,
    Guid HouseholdId,
    IReadOnlyList<ExportBackupConnectionDto> Connections,
    IReadOnlyList<ExportBackupAccountDto> Accounts,
    IReadOnlyList<ExportBackupCardBillDto> CardBills,
    IReadOnlyList<ExportBackupTagDto> Tags,
    IReadOnlyList<ExportBackupTransactionDto> Transactions,
    IReadOnlyList<ExportBackupAdjustmentDto> Adjustments,
    IReadOnlyList<ExportBackupSplitDto> Splits);
