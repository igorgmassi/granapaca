using System.Data;
using System.Globalization;
using System.Text.RegularExpressions;
using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using GranaPaCa.Modules.Categorization.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed partial class BankingDeltaSyncService(
    NpgsqlDataSource dataSource,
    ICategorizationDeltaReader categorizationDeltaReader,
    IAlertsDeltaReader alertsDeltaReader)
{
    public async Task<(bool Ok, string? ErrorCode, string? Error, SyncChangesResponse? Data)> GetChangesAsync(
        Guid householdId,
        string? rawCursor,
        CancellationToken cancellationToken)
    {
        DateTimeOffset? parsedCursor = null;
        string? normalizedInputCursor = null;

        if (!string.IsNullOrWhiteSpace(rawCursor))
        {
            if (!TryParseCursor(rawCursor, out var dto))
            {
                return (
                    false,
                    "invalid_cursor",
                    "Cursor de sincronização inválido; informe um timestamp ISO-8601 em UTC.",
                    null);
            }

            parsedCursor = dto;
            normalizedInputCursor = FormatCursor(dto);
        }

        var isFullSync = !parsedCursor.HasValue;

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);

        await connection.ExecuteAsync(new CommandDefinition(
            "SET TRANSACTION READ ONLY",
            transaction: transaction,
            cancellationToken: cancellationToken));

        var watermark = await connection.QuerySingleAsync<WatermarkRow>(new CommandDefinition(
            """
            SELECT
                now() AS ServerTime,
                (
                    SELECT min(xact_start)
                    FROM pg_stat_activity
                    WHERE datname = current_database()
                      AND backend_type = 'client backend'
                      AND state <> 'idle'
                      AND xact_start IS NOT NULL
                      AND pid <> pg_backend_pid()
                ) AS OldestActiveXactStart
            """,
            transaction: transaction,
            cancellationToken: cancellationToken));

        var serverTime = watermark.ServerTime.ToUniversalTime();
        if (parsedCursor.HasValue && parsedCursor.Value > serverTime)
        {
            await transaction.CommitAsync(cancellationToken);
            return (
                false,
                "cursor_in_future",
                "Cursor de sincronização está no futuro; execute uma ressincronização completa sem cursor.",
                null);
        }

        var oldestActiveXact = watermark.OldestActiveXactStart?.ToUniversalTime();
        var hasConcurrentActiveTx = oldestActiveXact.HasValue && oldestActiveXact.Value <= serverTime;
        var safeWatermark = hasConcurrentActiveTx
            ? oldestActiveXact!.Value.AddMicroseconds(-1)
            : serverTime;

        var parameters = new DynamicParameters();
        parameters.Add("HouseholdId", householdId);
        if (parsedCursor.HasValue)
        {
            parameters.Add("Cursor", parsedCursor.Value);
        }

        var connectionsSql = parsedCursor.HasValue
            ? """
              WITH connection_state AS (
                  SELECT
                      id,
                      provider,
                      external_item_id,
                      institution_name,
                      brand_color,
                      status,
                      last_synced_at,
                      consent_expires_at,
                      last_error_code,
                      consecutive_failures,
                      GREATEST(
                          created_at,
                          updated_at,
                          COALESCE(last_synced_at, created_at),
                          COALESCE(first_failure_at, created_at)
                      ) AS updated_at
                  FROM banking.connection
                  WHERE household_id = @HouseholdId
              )
              SELECT
                  id AS Id,
                  provider AS Provider,
                  external_item_id AS ExternalItemId,
                  institution_name AS InstitutionName,
                  brand_color AS BrandColor,
                  status AS Status,
                  last_synced_at AS LastSyncedAt,
                  consent_expires_at AS ConsentExpiresAt,
                  last_error_code AS LastErrorCode,
                  consecutive_failures AS ConsecutiveFailures,
                  updated_at AS UpdatedAt
              FROM connection_state
              WHERE updated_at > @Cursor
              ORDER BY updated_at ASC, id ASC
              """
            : """
              SELECT
                  id AS Id,
                  provider AS Provider,
                  external_item_id AS ExternalItemId,
                  institution_name AS InstitutionName,
                  brand_color AS BrandColor,
                  status AS Status,
                  last_synced_at AS LastSyncedAt,
                  consent_expires_at AS ConsentExpiresAt,
                  last_error_code AS LastErrorCode,
                  consecutive_failures AS ConsecutiveFailures,
                  GREATEST(
                      created_at,
                      updated_at,
                      COALESCE(last_synced_at, created_at),
                      COALESCE(first_failure_at, created_at)
                  ) AS UpdatedAt
              FROM banking.connection
              WHERE household_id = @HouseholdId
              ORDER BY UpdatedAt ASC, id ASC
              """;

        var connections = (await connection.QueryAsync<SyncConnectionDto>(new CommandDefinition(
            connectionsSql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();

        var accountsSql = parsedCursor.HasValue
            ? """
              WITH account_state AS (
                  SELECT
                      a.id,
                      a.connection_id,
                      a.external_account_id,
                      a.name,
                      a.kind,
                      a.last_four_digits,
                      a.currency,
                      a.opening_balance_cents,
                      COALESCE(snap.balance_cents, a.opening_balance_cents) AS balance_cents,
                      GREATEST(a.created_at, a.updated_at, COALESCE(snap.captured_at, a.created_at)) AS updated_at
                  FROM banking.account a
                  LEFT JOIN LATERAL (
                      SELECT bs.balance_cents, bs.captured_at
                      FROM banking.balance_snapshot bs
                      WHERE bs.account_id = a.id
                      ORDER BY bs.captured_at DESC, bs.id DESC
                      LIMIT 1
                  ) snap ON true
                  WHERE a.household_id = @HouseholdId
              )
              SELECT
                  id AS Id,
                  connection_id AS ConnectionId,
                  external_account_id AS ExternalAccountId,
                  name AS Name,
                  kind AS Kind,
                  last_four_digits AS LastFourDigits,
                  currency AS Currency,
                  opening_balance_cents AS OpeningBalanceCents,
                  balance_cents AS BalanceCents,
                  updated_at AS UpdatedAt
              FROM account_state
              WHERE updated_at > @Cursor
              ORDER BY updated_at ASC, id ASC
              """
            : """
              WITH account_state AS (
                  SELECT
                      a.id,
                      a.connection_id,
                      a.external_account_id,
                      a.name,
                      a.kind,
                      a.last_four_digits,
                      a.currency,
                      a.opening_balance_cents,
                      COALESCE(snap.balance_cents, a.opening_balance_cents) AS balance_cents,
                      GREATEST(a.created_at, a.updated_at, COALESCE(snap.captured_at, a.created_at)) AS updated_at
                  FROM banking.account a
                  LEFT JOIN LATERAL (
                      SELECT bs.balance_cents, bs.captured_at
                      FROM banking.balance_snapshot bs
                      WHERE bs.account_id = a.id
                      ORDER BY bs.captured_at DESC, bs.id DESC
                      LIMIT 1
                  ) snap ON true
                  WHERE a.household_id = @HouseholdId
              )
              SELECT
                  id AS Id,
                  connection_id AS ConnectionId,
                  external_account_id AS ExternalAccountId,
                  name AS Name,
                  kind AS Kind,
                  last_four_digits AS LastFourDigits,
                  currency AS Currency,
                  opening_balance_cents AS OpeningBalanceCents,
                  balance_cents AS BalanceCents,
                  updated_at AS UpdatedAt
              FROM account_state
              ORDER BY updated_at ASC, id ASC
              """;

        var accounts = (await connection.QueryAsync<SyncAccountDto>(new CommandDefinition(
            accountsSql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();

        var cardBillsSql = parsedCursor.HasValue
            ? """
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
                AND cb.updated_at > @Cursor
              ORDER BY cb.updated_at ASC, cb.id ASC
              """
            : """
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
              ORDER BY cb.updated_at ASC, cb.id ASC
              """;

        var cardBills = (await connection.QueryAsync<SyncCardBillDto>(new CommandDefinition(
            cardBillsSql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();

        var transactionsWhere = parsedCursor.HasValue ? "WHERE updated_at > @Cursor" : string.Empty;
        var transactionsSql = $"""
            WITH tx_changes AS (
                SELECT
                    te.id,
                    te.account_id,
                    te.account_name,
                    te.account_kind,
                    te.connection_id AS bank_id,
                    te.institution_name,
                    te.brand_color,
                    te.version_number,
                    te.occurred_on,
                    te.purchase_on,
                    te.effective_description AS description,
                    te.original_description,
                    te.merchant_cnpj,
                    te.amount_cents,
                    te.currency,
                    te.status,
                    te.effective_kind AS kind,
                    te.effective_category AS category,
                    te.effective_essentiality AS essentiality,
                    te.effective_brand AS brand,
                    te.effective_payment_method AS payment_method,
                    te.effective_is_atypical AS is_atypical,
                    te.bill_id,
                    te.installment_number,
                    te.installment_total,
                    te.has_manual_adjustments,
                    te.deciding_layer,
                    te.deciding_rule_name,
                    te.explanation,
                    te.ingested_at,
                    GREATEST(
                        te.ingested_at,
                        COALESCE(cl.classified_at, te.ingested_at),
                        COALESCE(adj.latest_adjustment_at, te.ingested_at)
                    ) AS updated_at
                FROM banking.transaction_effective te
                LEFT JOIN banking.classification cl ON cl.transaction_id = te.id
                LEFT JOIN LATERAL (
                    SELECT MAX(a.created_at) AS latest_adjustment_at
                    FROM banking.adjustment a
                    WHERE a.transaction_id = te.id
                ) adj ON true
                WHERE te.household_id = @HouseholdId
            )
            SELECT
                id AS Id,
                account_id AS AccountId,
                account_name AS AccountName,
                account_kind AS AccountKind,
                bank_id AS BankId,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
                version_number AS VersionNumber,
                occurred_on AS OccurredOn,
                purchase_on AS PurchaseOn,
                description AS Description,
                original_description AS OriginalDescription,
                merchant_cnpj AS MerchantCnpj,
                amount_cents AS AmountCents,
                currency AS Currency,
                status AS Status,
                kind AS Kind,
                category AS Category,
                essentiality AS Essentiality,
                brand AS Brand,
                payment_method AS PaymentMethod,
                is_atypical AS IsAtypical,
                bill_id AS BillId,
                installment_number AS InstallmentNumber,
                installment_total AS InstallmentTotal,
                has_manual_adjustments AS HasManualAdjustments,
                deciding_layer AS DecidingLayer,
                deciding_rule_name AS DecidingRuleName,
                explanation AS Explanation,
                ingested_at AS IngestedAt,
                updated_at AS UpdatedAt
            FROM tx_changes
            {transactionsWhere}
            ORDER BY updated_at ASC, id ASC
            """;

        var transactions = (await connection.QueryAsync<SyncTransactionDto>(new CommandDefinition(
            transactionsSql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();

        var removedRows = parsedCursor.HasValue
            ? (await connection.QueryAsync<RemovedTransactionRow>(new CommandDefinition(
                """
                WITH latest_version AS (
                    SELECT DISTINCT ON (v.transaction_id)
                        v.transaction_id,
                        v.is_removed,
                        v.ingested_at
                    FROM banking.transaction_version v
                    JOIN banking.transaction t ON t.id = v.transaction_id
                    WHERE t.household_id = @HouseholdId
                    ORDER BY v.transaction_id, v.version_number DESC
                )
                SELECT
                    transaction_id AS TransactionId,
                    ingested_at AS IngestedAt
                FROM latest_version
                WHERE is_removed = true
                  AND ingested_at > @Cursor
                ORDER BY ingested_at ASC, transaction_id ASC
                """,
                parameters,
                transaction: transaction,
                cancellationToken: cancellationToken))).ToList()
            : [];

        var adjustmentsSql = parsedCursor.HasValue
            ? """
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
                AND adj.created_at > @Cursor
              ORDER BY adj.created_at ASC, adj.id ASC
              """
            : """
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
              """;

        var adjustments = (await connection.QueryAsync<SyncAdjustmentDto>(new CommandDefinition(
            adjustmentsSql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();

        var rules = await categorizationDeltaReader.GetRuleChangesAsync(
            householdId,
            parsedCursor,
            connection,
            transaction,
            cancellationToken);

        var alerts = await alertsDeltaReader.GetAlertChangesAsync(
            householdId,
            parsedCursor,
            connection,
            transaction,
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        // Hold nextCursor at or below the oldest concurrent active transaction so uncommitted writes
        // whose now() timestamp precedes this snapshot are never skipped on the next delta poll.
        var nextCursorTimestamp = safeWatermark;
        if (!hasConcurrentActiveTx)
        {
            foreach (var item in connections)
            {
                if (item.UpdatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.UpdatedAt;
                }
            }

            foreach (var item in accounts)
            {
                if (item.UpdatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.UpdatedAt;
                }
            }

            foreach (var item in cardBills)
            {
                if (item.UpdatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.UpdatedAt;
                }
            }

            foreach (var item in transactions)
            {
                if (item.UpdatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.UpdatedAt;
                }
            }

            foreach (var item in removedRows)
            {
                if (item.IngestedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.IngestedAt;
                }
            }

            foreach (var item in adjustments)
            {
                if (item.CreatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.CreatedAt;
                }
            }

            foreach (var item in rules)
            {
                if (item.UpdatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.UpdatedAt;
                }
            }

            foreach (var item in alerts)
            {
                if (item.UpdatedAt > nextCursorTimestamp)
                {
                    nextCursorTimestamp = item.UpdatedAt;
                }
            }
        }
        else if (parsedCursor.HasValue && parsedCursor.Value > nextCursorTimestamp)
        {
            nextCursorTimestamp = parsedCursor.Value;
        }

        var response = new SyncChangesResponse(
            normalizedInputCursor,
            FormatCursor(nextCursorTimestamp),
            serverTime,
            isFullSync,
            FullResyncRequired: false,
            connections,
            accounts,
            cardBills,
            transactions,
            removedRows.Select(r => r.TransactionId).ToList(),
            adjustments,
            rules,
            alerts);

        return (true, null, null, response);
    }

    private static bool TryParseCursor(string rawCursor, out DateTimeOffset utcCursor)
    {
        utcCursor = default;
        var trimmed = rawCursor.Trim();
        if (!IsoUtcCursorRegex().IsMatch(trimmed))
        {
            return false;
        }

        if (!DateTimeOffset.TryParse(
                trimmed,
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out var parsed))
        {
            return false;
        }

        utcCursor = parsed.ToUniversalTime();
        return true;
    }

    private static string FormatCursor(DateTimeOffset utcTimestamp) =>
        utcTimestamp.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'", CultureInfo.InvariantCulture);

    [GeneratedRegex(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex IsoUtcCursorRegex();

    private sealed record WatermarkRow(DateTimeOffset ServerTime, DateTimeOffset? OldestActiveXactStart);

    private sealed record RemovedTransactionRow(Guid TransactionId, DateTimeOffset IngestedAt);
}

internal sealed record SyncConnectionDto(
    Guid Id,
    string Provider,
    string ExternalItemId,
    string InstitutionName,
    string BrandColor,
    string Status,
    DateTimeOffset? LastSyncedAt,
    DateTimeOffset? ConsentExpiresAt,
    string? LastErrorCode,
    int ConsecutiveFailures,
    DateTimeOffset UpdatedAt);

internal sealed record SyncAccountDto(
    Guid Id,
    Guid ConnectionId,
    string ExternalAccountId,
    string Name,
    string Kind,
    string? LastFourDigits,
    string Currency,
    long OpeningBalanceCents,
    long BalanceCents,
    DateTimeOffset UpdatedAt);

internal sealed record SyncCardBillDto(
    Guid Id,
    Guid AccountId,
    string ExternalBillId,
    DateOnly PeriodMonth,
    DateOnly ClosingOn,
    DateOnly DueOn,
    long TotalCents,
    bool IsOpen,
    DateTimeOffset UpdatedAt);

internal sealed record SyncTransactionDto(
    Guid Id,
    Guid AccountId,
    string AccountName,
    string AccountKind,
    Guid BankId,
    string InstitutionName,
    string BrandColor,
    int VersionNumber,
    DateOnly OccurredOn,
    DateOnly? PurchaseOn,
    string Description,
    string OriginalDescription,
    string? MerchantCnpj,
    long AmountCents,
    string Currency,
    string Status,
    string Kind,
    string? Category,
    string? Essentiality,
    string? Brand,
    string? PaymentMethod,
    bool IsAtypical,
    Guid? BillId,
    int? InstallmentNumber,
    int? InstallmentTotal,
    bool HasManualAdjustments,
    string DecidingLayer,
    string? DecidingRuleName,
    string Explanation,
    DateTimeOffset IngestedAt,
    DateTimeOffset UpdatedAt);

internal sealed record SyncAdjustmentDto(
    Guid Id,
    Guid TransactionId,
    string FieldName,
    string? OldValue,
    string? NewValue,
    string? Reason,
    Guid? UndoesId,
    DateTimeOffset CreatedAt);

internal sealed record SyncChangesResponse(
    string? Cursor,
    string NextCursor,
    DateTimeOffset ServerTime,
    bool IsFullSync,
    bool FullResyncRequired,
    IReadOnlyList<SyncConnectionDto> Connections,
    IReadOnlyList<SyncAccountDto> Accounts,
    IReadOnlyList<SyncCardBillDto> CardBills,
    IReadOnlyList<SyncTransactionDto> Transactions,
    IReadOnlyList<Guid> RemovedTransactionIds,
    IReadOnlyList<SyncAdjustmentDto> Adjustments,
    IReadOnlyList<SyncRuleDto> Rules,
    IReadOnlyList<SyncAlertDto> Alerts);
