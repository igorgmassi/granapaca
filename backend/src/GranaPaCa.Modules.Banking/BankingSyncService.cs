using System.Text;
using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Banking.Providers;
using GranaPaCa.Modules.Categorization.Contracts;
using GranaPaCa.Modules.Keyring.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class BankingSyncService(
    NpgsqlDataSource dataSource,
    SyntheticBankProvider syntheticProvider,
    PluggyBankProvider pluggyProvider,
    ICategorizationEngine categorizationEngine,
    IEnvelopeEncryptor envelopeEncryptor,
    IAlertPublisher alertPublisher,
    IConfiguration configuration,
    ILogger<BankingSyncService> logger) : IBankingSyncTrigger, ITransactionReclassifier
{
    private const string RawPayloadPurpose = "banking.raw_payload";
    private const int MaxImportBytes = 5 * 1024 * 1024;
    private static readonly HashSet<string> AllowedAccountKinds =
        new(StringComparer.Ordinal) { "checking", "savings", "credit_card" };
    private readonly TimeZoneInfo _instanceTimeZone = DateParser.ResolveInstanceTimeZone(configuration);

    public async Task<SyncSummary> SyncHouseholdAsync(
        Guid householdId,
        CancellationToken cancellationToken = default)
    {
        var connections = await LoadConnectionsAsync(householdId, cancellationToken);

        if (!pluggyProvider.IsConfigured && connections.Count == 0)
        {
            await EnsureSyntheticConnectionsAsync(householdId, cancellationToken);
            connections = await LoadConnectionsAsync(householdId, cancellationToken);
        }

        var connectionsProcessed = 0;
        var accountsSynced = 0;
        var transactionsInserted = 0;
        var transactionsVersioned = 0;
        var transactionsRemoved = 0;
        var failedConnections = 0;

        foreach (var conn in connections)
        {
            IBankProvider? provider = conn.Provider switch
            {
                "synthetic" => syntheticProvider,
                "pluggy" => pluggyProvider,
                _ => null
            };

            if (provider is null)
            {
                continue;
            }

            if (!provider.IsConfigured)
            {
                await RecordConnectionFailureAsync(conn.Id, "provider_not_configured", cancellationToken);
                var failedConn = await LoadConnectionByIdAsync(conn.Id, cancellationToken);
                if (failedConn is not null)
                {
                    await EvaluateConnectionAlertsAsync(failedConn, cancellationToken);
                }

                failedConnections++;
                logger.LogWarning(
                    "Sync skipped: provider={Provider} connectionId={ConnectionId} errorCode=provider_not_configured",
                    conn.Provider,
                    conn.Id);
                continue;
            }

            ProviderConnectionData fetched;
            try
            {
                fetched = await provider.FetchConnectionAsync(conn.ExternalItemId, cancellationToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                var errorCode = ClassifyErrorCode(ex);
                await RecordConnectionFailureAsync(conn.Id, errorCode, cancellationToken);
                var failedConn = await LoadConnectionByIdAsync(conn.Id, cancellationToken);
                if (failedConn is not null)
                {
                    await EvaluateConnectionAlertsAsync(failedConn, cancellationToken);
                }

                failedConnections++;
                logger.LogWarning(
                    "Connection sync failed: provider={Provider} connectionId={ConnectionId} errorCode={ErrorCode}",
                    conn.Provider,
                    conn.Id,
                    errorCode);
                continue;
            }

            var now = DateTimeOffset.UtcNow;
            var effectiveConsentExpiresAt = conn.Provider == "synthetic"
                ? (conn.ConsentExpiresAt ?? fetched.ConsentExpiresAt)
                : fetched.ConsentExpiresAt;

            var effectiveStatus = fetched.Status;
            if (effectiveConsentExpiresAt.HasValue && effectiveConsentExpiresAt.Value <= now)
            {
                effectiveStatus = "expired";
            }

            await UpdateConnectionAfterFetchAsync(
                conn.Id,
                fetched.InstitutionName,
                fetched.BrandColor,
                effectiveStatus,
                effectiveConsentExpiresAt,
                fetched.LastErrorCode,
                cancellationToken);

            foreach (var account in fetched.Accounts)
            {
                var ingest = await IngestAccountAsync(householdId, conn.Id, account, cancellationToken);
                accountsSynced++;
                transactionsInserted += ingest.Inserted;
                transactionsVersioned += ingest.Versioned;
                transactionsRemoved += ingest.Removed;
            }

            var updatedConn = await LoadConnectionByIdAsync(conn.Id, cancellationToken);
            if (updatedConn is not null)
            {
                await EvaluateConnectionAlertsAsync(updatedConn, cancellationToken);
            }

            connectionsProcessed++;
        }

        var (_, transfersLinked) = await ReclassifyAndLinkInternalAsync(householdId, cancellationToken);

        logger.LogInformation(
            "Household sync finished: connections={Connections} accounts={Accounts} inserted={Inserted} versioned={Versioned} removed={Removed} transfers={Transfers} failed={Failed}",
            connectionsProcessed,
            accountsSynced,
            transactionsInserted,
            transactionsVersioned,
            transactionsRemoved,
            transfersLinked,
            failedConnections);

        return new SyncSummary(
            connectionsProcessed,
            accountsSynced,
            transactionsInserted,
            transactionsVersioned,
            transactionsRemoved,
            transfersLinked,
            failedConnections);
    }

    public async Task<int> ReclassifyHouseholdAsync(
        Guid householdId,
        CancellationToken cancellationToken = default)
    {
        var (classifiedCount, _) = await ReclassifyAndLinkInternalAsync(householdId, cancellationToken);
        return classifiedCount;
    }

    public async Task<IReadOnlyDictionary<Guid, int>> CountRuleMatchesAsync(
        Guid householdId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<RuleMatchRow>(new CommandDefinition(
            """
            SELECT
                deciding_rule_id AS RuleId,
                COUNT(*)::int AS MatchCount
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND deciding_rule_id IS NOT NULL
            GROUP BY deciding_rule_id
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken));

        return rows.ToDictionary(r => r.RuleId, r => r.MatchCount);
    }

    public async Task<(bool Ok, string? Error, ImportResponse? Data)> ImportStatementAsync(
        Guid householdId,
        string format,
        ImportStatementRequest? request,
        CancellationToken cancellationToken = default)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.Content))
        {
            return (false, "Conteúdo do arquivo é obrigatório.", null);
        }

        if (Encoding.UTF8.GetByteCount(request.Content) > MaxImportBytes)
        {
            return (false, "O arquivo excede o limite máximo de 5 MB.", null);
        }

        string? requestedKind = null;
        if (!string.IsNullOrWhiteSpace(request.AccountKind))
        {
            requestedKind = request.AccountKind.Trim().ToLowerInvariant();
            if (!AllowedAccountKinds.Contains(requestedKind))
            {
                return (false, "Tipo de conta inválido; use checking, savings ou credit_card.", null);
            }
        }

        var (parseOk, parseError, statement) = format switch
        {
            "ofx" => OfxStatementParser.Parse(request.Content, _instanceTimeZone),
            "csv" => CsvStatementParser.Parse(request.Content, _instanceTimeZone),
            _ => (false, "Formato de importação não suportado.", null)
        };

        if (!parseOk || statement is null)
        {
            return (false, parseError ?? "Não foi possível ler o arquivo enviado.", null);
        }

        var institutionName = !string.IsNullOrWhiteSpace(request.InstitutionName)
            ? request.InstitutionName.Trim()
            : !string.IsNullOrWhiteSpace(statement.InstitutionName)
                ? statement.InstitutionName.Trim()
                : !string.IsNullOrWhiteSpace(statement.BankId)
                    ? $"Banco {statement.BankId.Trim()}"
                    : format == "ofx" ? "Importação OFX" : "Importação CSV";

        var accountKind = requestedKind ?? statement.AccountKind ?? "checking";

        var accountName = !string.IsNullOrWhiteSpace(request.AccountName)
            ? request.AccountName.Trim()
            : accountKind switch
            {
                "credit_card" => "Cartão importado",
                "savings" => "Poupança importada",
                _ => "Conta importada"
            };

        var institutionSlug = StatementIdHelper.Slugify(institutionName, "arquivo");
        var externalItemId = $"file:{institutionSlug}";
        var externalAccountId = !string.IsNullOrWhiteSpace(statement.AccountId)
            ? $"file:{accountKind}:{statement.AccountId.Trim()}"
            : $"file:{accountKind}:{StatementIdHelper.Slugify(accountName, "conta")}";

        var seenFileExternalIds = new HashSet<string>(StringComparer.Ordinal);
        var uniqueTransactions = new List<ProviderTransactionData>(statement.Transactions.Count);
        var inFileDuplicates = 0;

        foreach (var tx in statement.Transactions)
        {
            if (!seenFileExternalIds.Add(tx.ExternalId))
            {
                inFileDuplicates++;
                continue;
            }

            uniqueTransactions.Add(new ProviderTransactionData(
                Source: "file",
                ExternalId: tx.ExternalId,
                OccurredOn: tx.OccurredOn,
                PurchaseOn: null,
                Description: tx.Description,
                MerchantCnpj: null,
                AmountCents: tx.AmountCents,
                Currency: "BRL",
                Status: "posted",
                ExternalBillId: null,
                InstallmentNumber: null,
                InstallmentTotal: null,
                RawPayloadJson: tx.RawPayloadJson));
        }

        Guid connectionId;
        await using (var conn = await dataSource.OpenConnectionAsync(cancellationToken))
        {
            connectionId = await conn.ExecuteScalarAsync<Guid>(new CommandDefinition(
                """
                INSERT INTO banking.connection (
                    id,
                    household_id,
                    provider,
                    external_item_id,
                    institution_name,
                    brand_color,
                    status,
                    last_synced_at
                )
                VALUES (
                    @Id,
                    @HouseholdId,
                    'file',
                    @ExternalItemId,
                    @InstitutionName,
                    '#A0521A',
                    'up_to_date',
                    now()
                )
                ON CONFLICT (household_id, provider, external_item_id) DO UPDATE
                SET institution_name = EXCLUDED.institution_name,
                    status = 'up_to_date',
                    last_synced_at = now(),
                    updated_at = now()
                RETURNING id
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    HouseholdId = householdId,
                    ExternalItemId = externalItemId,
                    InstitutionName = institutionName
                },
                cancellationToken: cancellationToken));
        }

        var providerAccount = new ProviderAccountData(
            ExternalAccountId: externalAccountId,
            Name: accountName,
            Kind: accountKind,
            LastFourDigits: BankingTaxonomy.ExtractLastFourDigits(statement.AccountId),
            Currency: "BRL",
            OpeningBalanceCents: 0,
            CurrentBalanceCents: statement.LedgerBalanceCents ?? 0,
            Bills: [],
            Transactions: uniqueTransactions);

        var ingest = await IngestAccountAsync(
            householdId,
            connectionId,
            providerAccount,
            cancellationToken,
            markMissingAsRemoved: false,
            recordBalanceSnapshot: statement.LedgerBalanceCents.HasValue);

        var (_, transfersLinked) = await ReclassifyAndLinkInternalAsync(householdId, cancellationToken);

        var uncategorizedCount = 0;
        if (ingest.SeenTransactionIds.Count > 0)
        {
            await using var conn = await dataSource.OpenConnectionAsync(cancellationToken);
            uncategorizedCount = await conn.ExecuteScalarAsync<int>(new CommandDefinition(
                """
                SELECT COUNT(*)::int
                FROM banking.transaction_effective
                WHERE household_id = @HouseholdId
                  AND id = ANY(@TransactionIds)
                  AND effective_kind IN ('expense', 'refund')
                  AND effective_category IS NULL
                """,
                new
                {
                    HouseholdId = householdId,
                    TransactionIds = ingest.SeenTransactionIds.ToArray()
                },
                cancellationToken: cancellationToken));
        }

        var skippedDuplicates = ingest.SkippedDuplicates + inFileDuplicates;

        logger.LogInformation(
            "File statement imported: format={Format} inserted={Inserted} skippedDuplicates={SkippedDuplicates} transfersLinked={TransfersLinked} uncategorized={Uncategorized}",
            format,
            ingest.Inserted,
            skippedDuplicates,
            transfersLinked,
            uncategorizedCount);

        return (
            true,
            null,
            new ImportResponse(
                connectionId,
                ingest.AccountId,
                ingest.Inserted,
                skippedDuplicates,
                transfersLinked,
                uncategorizedCount));
    }

    private async Task<List<ConnectionRow>> LoadConnectionsAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        return (await connection.QueryAsync<ConnectionRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                household_id AS HouseholdId,
                provider AS Provider,
                external_item_id AS ExternalItemId,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
                status AS Status,
                consent_expires_at AS ConsentExpiresAt,
                last_synced_at AS LastSyncedAt,
                last_error_code AS LastErrorCode,
                consecutive_failures AS ConsecutiveFailures,
                first_failure_at AS FirstFailureAt
            FROM banking.connection
            WHERE household_id = @HouseholdId
            ORDER BY created_at ASC, id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();
    }

    private async Task<ConnectionRow?> LoadConnectionByIdAsync(
        Guid connectionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<ConnectionRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                household_id AS HouseholdId,
                provider AS Provider,
                external_item_id AS ExternalItemId,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
                status AS Status,
                consent_expires_at AS ConsentExpiresAt,
                last_synced_at AS LastSyncedAt,
                last_error_code AS LastErrorCode,
                consecutive_failures AS ConsecutiveFailures,
                first_failure_at AS FirstFailureAt
            FROM banking.connection
            WHERE id = @ConnectionId
            """,
            new { ConnectionId = connectionId },
            cancellationToken: cancellationToken));
    }

    private async Task EnsureSyntheticConnectionsAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        foreach (var (externalItemId, institutionName, brandColor) in SyntheticBankProvider.DefaultConnections)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.connection (
                    id,
                    household_id,
                    provider,
                    external_item_id,
                    institution_name,
                    brand_color,
                    status
                )
                VALUES (
                    @Id,
                    @HouseholdId,
                    'synthetic',
                    @ExternalItemId,
                    @InstitutionName,
                    @BrandColor,
                    'up_to_date'
                )
                ON CONFLICT (household_id, provider, external_item_id) DO NOTHING
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    HouseholdId = householdId,
                    ExternalItemId = externalItemId,
                    InstitutionName = institutionName,
                    BrandColor = brandColor
                },
                cancellationToken: cancellationToken));
        }
    }

    private async Task RecordConnectionFailureAsync(
        Guid connectionId,
        string errorCode,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE banking.connection
            SET status = 'error',
                last_error_code = @ErrorCode,
                consecutive_failures = consecutive_failures + 1,
                first_failure_at = COALESCE(first_failure_at, now()),
                updated_at = now()
            WHERE id = @ConnectionId
            """,
            new { ConnectionId = connectionId, ErrorCode = errorCode },
            cancellationToken: cancellationToken));
    }

    private async Task UpdateConnectionAfterFetchAsync(
        Guid connectionId,
        string institutionName,
        string brandColor,
        string status,
        DateTimeOffset? consentExpiresAt,
        string? lastErrorCode,
        CancellationToken cancellationToken)
    {
        var consentExpiresAtUtc = consentExpiresAt?.ToUniversalTime();
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        if (string.Equals(status, "up_to_date", StringComparison.Ordinal))
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE banking.connection
                SET institution_name = @InstitutionName,
                    brand_color = @BrandColor,
                    status = @Status,
                    consent_expires_at = @ConsentExpiresAt,
                    last_synced_at = now(),
                    last_error_code = NULL,
                    consecutive_failures = 0,
                    first_failure_at = NULL,
                    updated_at = now()
                WHERE id = @ConnectionId
                """,
                new
                {
                    ConnectionId = connectionId,
                    InstitutionName = institutionName,
                    BrandColor = brandColor,
                    Status = status,
                    ConsentExpiresAt = consentExpiresAtUtc
                },
                cancellationToken: cancellationToken));
        }
        else if (string.Equals(status, "error", StringComparison.Ordinal))
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE banking.connection
                SET institution_name = @InstitutionName,
                    brand_color = @BrandColor,
                    status = @Status,
                    consent_expires_at = @ConsentExpiresAt,
                    last_error_code = @LastErrorCode,
                    consecutive_failures = consecutive_failures + 1,
                    first_failure_at = COALESCE(first_failure_at, now()),
                    updated_at = now()
                WHERE id = @ConnectionId
                """,
                new
                {
                    ConnectionId = connectionId,
                    InstitutionName = institutionName,
                    BrandColor = brandColor,
                    Status = status,
                    ConsentExpiresAt = consentExpiresAtUtc,
                    LastErrorCode = lastErrorCode
                },
                cancellationToken: cancellationToken));
        }
        else
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE banking.connection
                SET institution_name = @InstitutionName,
                    brand_color = @BrandColor,
                    status = @Status,
                    consent_expires_at = @ConsentExpiresAt,
                    last_synced_at = now(),
                    last_error_code = @LastErrorCode,
                    updated_at = now()
                WHERE id = @ConnectionId
                """,
                new
                {
                    ConnectionId = connectionId,
                    InstitutionName = institutionName,
                    BrandColor = brandColor,
                    Status = status,
                    ConsentExpiresAt = consentExpiresAtUtc,
                    LastErrorCode = lastErrorCode
                },
                cancellationToken: cancellationToken));
        }
    }

    private async Task<AccountIngestCounts> IngestAccountAsync(
        Guid householdId,
        Guid connectionId,
        ProviderAccountData account,
        CancellationToken cancellationToken,
        bool markMissingAsRemoved = true,
        bool recordBalanceSnapshot = true)
    {
        await using var dbConn = await dataSource.OpenConnectionAsync(cancellationToken);

        // 1. Upsert account
        var accountId = await dbConn.ExecuteScalarAsync<Guid>(new CommandDefinition(
            """
            INSERT INTO banking.account (
                id,
                household_id,
                connection_id,
                external_account_id,
                name,
                kind,
                last_four_digits,
                currency,
                opening_balance_cents
            )
            VALUES (
                @Id,
                @HouseholdId,
                @ConnectionId,
                @ExternalAccountId,
                @Name,
                @Kind,
                @LastFourDigits,
                @Currency,
                @OpeningBalanceCents
            )
            ON CONFLICT (connection_id, external_account_id) DO UPDATE
            SET name = EXCLUDED.name,
                kind = EXCLUDED.kind,
                last_four_digits = COALESCE(EXCLUDED.last_four_digits, banking.account.last_four_digits),
                opening_balance_cents = EXCLUDED.opening_balance_cents,
                updated_at = CASE
                    WHEN banking.account.name IS DISTINCT FROM EXCLUDED.name
                      OR banking.account.kind IS DISTINCT FROM EXCLUDED.kind
                      OR banking.account.last_four_digits IS DISTINCT FROM COALESCE(EXCLUDED.last_four_digits, banking.account.last_four_digits)
                      OR banking.account.opening_balance_cents IS DISTINCT FROM EXCLUDED.opening_balance_cents
                    THEN now()
                    ELSE banking.account.updated_at
                END
            RETURNING id
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                ConnectionId = connectionId,
                account.ExternalAccountId,
                account.Name,
                account.Kind,
                account.LastFourDigits,
                account.Currency,
                account.OpeningBalanceCents
            },
            cancellationToken: cancellationToken));

        // 2. Append balance snapshot when provided by the feed
        if (recordBalanceSnapshot)
        {
            await dbConn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.balance_snapshot (id, account_id, balance_cents)
                VALUES (@Id, @AccountId, @BalanceCents)
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    AccountId = accountId,
                    BalanceCents = account.CurrentBalanceCents
                },
                cancellationToken: cancellationToken));
        }

        // 3. Upsert card bills (encrypting raw payload with AAD bound to exact billId)
        var existingBills = (await dbConn.QueryAsync<ExistingBillRow>(new CommandDefinition(
            """
            SELECT id AS Id, external_bill_id AS ExternalBillId
            FROM banking.card_bill
            WHERE account_id = @AccountId
            """,
            new { AccountId = accountId },
            cancellationToken: cancellationToken)))
            .ToDictionary(b => b.ExternalBillId, b => b.Id, StringComparer.Ordinal);

        var billIdMap = new Dictionary<string, Guid>(existingBills, StringComparer.Ordinal);

        foreach (var bill in account.Bills)
        {
            var billId = billIdMap.TryGetValue(bill.ExternalBillId, out var existingId)
                ? existingId
                : Guid.CreateVersion7();

            var encryptedBill = await envelopeEncryptor.EncryptAsync(
                householdId,
                RawPayloadPurpose,
                Encoding.UTF8.GetBytes(bill.RawPayloadJson),
                "banking.card_bill",
                "raw_payload_enc",
                billId,
                cancellationToken);

            await dbConn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.card_bill (
                    id,
                    account_id,
                    external_bill_id,
                    period_month,
                    closing_on,
                    due_on,
                    total_cents,
                    is_open,
                    raw_payload_enc,
                    updated_at
                )
                VALUES (
                    @Id,
                    @AccountId,
                    @ExternalBillId,
                    @PeriodMonth,
                    @ClosingOn,
                    @DueOn,
                    @TotalCents,
                    @IsOpen,
                    @RawPayloadEnc,
                    now()
                )
                ON CONFLICT (account_id, external_bill_id) DO UPDATE
                SET period_month = EXCLUDED.period_month,
                    closing_on = EXCLUDED.closing_on,
                    due_on = EXCLUDED.due_on,
                    total_cents = EXCLUDED.total_cents,
                    is_open = EXCLUDED.is_open,
                    raw_payload_enc = EXCLUDED.raw_payload_enc,
                    updated_at = now()
                """,
                new
                {
                    Id = billId,
                    AccountId = accountId,
                    bill.ExternalBillId,
                    bill.PeriodMonth,
                    bill.ClosingOn,
                    bill.DueOn,
                    bill.TotalCents,
                    bill.IsOpen,
                    RawPayloadEnc = encryptedBill
                },
                cancellationToken: cancellationToken));

            billIdMap[bill.ExternalBillId] = billId;
        }

        // 4. Load existing transaction sources and latest versions for append-only ingestion (ADR-012)
        var existingSources = (await dbConn.QueryAsync<ExistingSourceRow>(new CommandDefinition(
            """
            SELECT
                transaction_id AS TransactionId,
                source AS Source,
                external_id AS ExternalId
            FROM banking.transaction_source
            WHERE account_id = @AccountId
            """,
            new { AccountId = accountId },
            cancellationToken: cancellationToken)))
            .ToDictionary(s => (s.Source, s.ExternalId), s => s.TransactionId);

        var latestVersions = (await dbConn.QueryAsync<LatestVersionRow>(new CommandDefinition(
            """
            SELECT DISTINCT ON (v.transaction_id)
                v.transaction_id AS TransactionId,
                v.version_number AS VersionNumber,
                v.content_hash AS ContentHash,
                v.occurred_on AS OccurredOn,
                v.purchase_on AS PurchaseOn,
                v.description AS Description,
                v.merchant_cnpj AS MerchantCnpj,
                v.amount_cents AS AmountCents,
                v.currency AS Currency,
                v.status AS Status,
                v.bill_id AS BillId,
                v.installment_number AS InstallmentNumber,
                v.installment_total AS InstallmentTotal,
                v.is_removed AS IsRemoved
            FROM banking.transaction_version v
            JOIN banking.transaction t ON t.id = v.transaction_id
            WHERE t.account_id = @AccountId
            ORDER BY v.transaction_id, v.version_number DESC
            """,
            new { AccountId = accountId },
            cancellationToken: cancellationToken)))
            .ToDictionary(v => v.TransactionId);

        var knownIncoming = new List<(Guid TransactionId, ProviderTransactionData Tx)>();
        var newIncoming = new List<ProviderTransactionData>();
        var seenTransactionIds = new HashSet<Guid>();

        foreach (var tx in account.Transactions)
        {
            if (existingSources.TryGetValue((tx.Source, tx.ExternalId), out var existingTxId))
            {
                knownIncoming.Add((existingTxId, tx));
                seenTransactionIds.Add(existingTxId);
            }
            else
            {
                newIncoming.Add(tx);
            }
        }

        // Candidate disappeared pending transactions on this account for pending->posted matching (ADR-012).
        var unclaimedPending = latestVersions.Values
            .Where(v => !v.IsRemoved &&
                        string.Equals(v.Status, "pending", StringComparison.Ordinal) &&
                        !seenTransactionIds.Contains(v.TransactionId))
            .ToList();

        var inserted = 0;
        var versioned = 0;
        var removed = 0;
        var skippedDuplicates = 0;

        var pendingInserts = new List<(Guid TxId, ProviderTransactionData Tx, Guid? BillId, int VersionNumber, string ContentHash, Guid VersionId, byte[] RawEnc, bool IsNewTx, bool NeedsSourceLink)>();

        foreach (var (txId, tx) in knownIncoming)
        {
            Guid? billId = tx.ExternalBillId is not null && billIdMap.TryGetValue(tx.ExternalBillId, out var mappedBill)
                ? mappedBill
                : null;

            var normalizedCnpj = MerchantNormalizer.NormalizeCnpj(tx.MerchantCnpj);
            var contentHash = ContentHashCalculator.ComputeTransactionHash(
                tx.OccurredOn,
                tx.PurchaseOn,
                tx.Description,
                normalizedCnpj,
                tx.AmountCents,
                tx.Currency,
                tx.Status,
                billId,
                tx.InstallmentNumber,
                tx.InstallmentTotal,
                isRemoved: false);

            if (!latestVersions.TryGetValue(txId, out var latest))
            {
                var versionId = Guid.CreateVersion7();
                var rawEnc = await envelopeEncryptor.EncryptAsync(
                    householdId,
                    RawPayloadPurpose,
                    Encoding.UTF8.GetBytes(tx.RawPayloadJson),
                    "banking.transaction_version",
                    "raw_payload_enc",
                    versionId,
                    cancellationToken);

                pendingInserts.Add((txId, tx, billId, 1, contentHash, versionId, rawEnc, false, false));
                versioned++;
            }
            else if (!string.Equals(latest.ContentHash, contentHash, StringComparison.Ordinal) || latest.IsRemoved)
            {
                var versionId = Guid.CreateVersion7();
                var rawEnc = await envelopeEncryptor.EncryptAsync(
                    householdId,
                    RawPayloadPurpose,
                    Encoding.UTF8.GetBytes(tx.RawPayloadJson),
                    "banking.transaction_version",
                    "raw_payload_enc",
                    versionId,
                    cancellationToken);

                pendingInserts.Add((txId, tx, billId, latest.VersionNumber + 1, contentHash, versionId, rawEnc, false, false));
                versioned++;
            }
            else
            {
                skippedDuplicates++;
            }
        }

        foreach (var tx in newIncoming)
        {
            Guid? billId = tx.ExternalBillId is not null && billIdMap.TryGetValue(tx.ExternalBillId, out var mappedBill)
                ? mappedBill
                : null;

            var normalizedCnpj = MerchantNormalizer.NormalizeCnpj(tx.MerchantCnpj);
            var contentHash = ContentHashCalculator.ComputeTransactionHash(
                tx.OccurredOn,
                tx.PurchaseOn,
                tx.Description,
                normalizedCnpj,
                tx.AmountCents,
                tx.Currency,
                tx.Status,
                billId,
                tx.InstallmentNumber,
                tx.InstallmentTotal,
                isRemoved: false);

            // Try pending -> posted match: same account, identical amount_cents, within +/-3 days.
            var matchedPending = unclaimedPending
                .Where(p => p.AmountCents == tx.AmountCents &&
                            Math.Abs(tx.OccurredOn.DayNumber - p.OccurredOn.DayNumber) <= 3)
                .OrderBy(p => Math.Abs(tx.OccurredOn.DayNumber - p.OccurredOn.DayNumber))
                .FirstOrDefault();

            if (matchedPending is not null)
            {
                unclaimedPending.Remove(matchedPending);
                seenTransactionIds.Add(matchedPending.TransactionId);

                var versionId = Guid.CreateVersion7();
                var rawEnc = await envelopeEncryptor.EncryptAsync(
                    householdId,
                    RawPayloadPurpose,
                    Encoding.UTF8.GetBytes(tx.RawPayloadJson),
                    "banking.transaction_version",
                    "raw_payload_enc",
                    versionId,
                    cancellationToken);

                pendingInserts.Add((
                    matchedPending.TransactionId,
                    tx,
                    billId,
                    matchedPending.VersionNumber + 1,
                    contentHash,
                    versionId,
                    rawEnc,
                    IsNewTx: false,
                    NeedsSourceLink: true));
                versioned++;
            }
            else
            {
                var txId = Guid.CreateVersion7();
                var versionId = Guid.CreateVersion7();
                var rawEnc = await envelopeEncryptor.EncryptAsync(
                    householdId,
                    RawPayloadPurpose,
                    Encoding.UTF8.GetBytes(tx.RawPayloadJson),
                    "banking.transaction_version",
                    "raw_payload_enc",
                    versionId,
                    cancellationToken);

                seenTransactionIds.Add(txId);
                pendingInserts.Add((
                    txId,
                    tx,
                    billId,
                    1,
                    contentHash,
                    versionId,
                    rawEnc,
                    IsNewTx: true,
                    NeedsSourceLink: true));
                inserted++;
            }
        }

        // Transactions that vanished from full provider feeds get an appended removal version (ADR-012).
        var removals = markMissingAsRemoved
            ? latestVersions.Values
                .Where(v => !v.IsRemoved && !seenTransactionIds.Contains(v.TransactionId))
                .ToList()
            : [];

        if (pendingInserts.Count == 0 && removals.Count == 0)
        {
            return new AccountIngestCounts(accountId, 0, 0, 0, skippedDuplicates, seenTransactionIds.ToList());
        }

        await using var dbTx = await dbConn.BeginTransactionAsync(cancellationToken);

        foreach (var item in pendingInserts)
        {
            if (item.IsNewTx)
            {
                await dbConn.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO banking.transaction (id, household_id, account_id)
                    VALUES (@Id, @HouseholdId, @AccountId)
                    """,
                    new { Id = item.TxId, HouseholdId = householdId, AccountId = accountId },
                    transaction: dbTx,
                    cancellationToken: cancellationToken));
            }

            if (item.NeedsSourceLink)
            {
                await dbConn.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO banking.transaction_source (id, transaction_id, account_id, source, external_id)
                    VALUES (@Id, @TransactionId, @AccountId, @Source, @ExternalId)
                    ON CONFLICT (account_id, source, external_id) DO NOTHING
                    """,
                    new
                    {
                        Id = Guid.CreateVersion7(),
                        TransactionId = item.TxId,
                        AccountId = accountId,
                        item.Tx.Source,
                        item.Tx.ExternalId
                    },
                    transaction: dbTx,
                    cancellationToken: cancellationToken));
            }

            await dbConn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.transaction_version (
                    id,
                    transaction_id,
                    version_number,
                    content_hash,
                    occurred_on,
                    purchase_on,
                    description,
                    merchant_cnpj,
                    amount_cents,
                    currency,
                    status,
                    bill_id,
                    installment_number,
                    installment_total,
                    is_removed,
                    raw_payload_enc
                )
                VALUES (
                    @Id,
                    @TransactionId,
                    @VersionNumber,
                    @ContentHash,
                    @OccurredOn,
                    @PurchaseOn,
                    @Description,
                    @MerchantCnpj,
                    @AmountCents,
                    @Currency,
                    @Status,
                    @BillId,
                    @InstallmentNumber,
                    @InstallmentTotal,
                    false,
                    @RawPayloadEnc
                )
                """,
                new
                {
                    Id = item.VersionId,
                    TransactionId = item.TxId,
                    item.VersionNumber,
                    item.ContentHash,
                    item.Tx.OccurredOn,
                    item.Tx.PurchaseOn,
                    item.Tx.Description,
                    MerchantCnpj = MerchantNormalizer.NormalizeCnpj(item.Tx.MerchantCnpj),
                    item.Tx.AmountCents,
                    item.Tx.Currency,
                    item.Tx.Status,
                    item.BillId,
                    item.Tx.InstallmentNumber,
                    item.Tx.InstallmentTotal,
                    RawPayloadEnc = item.RawEnc
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));
        }

        foreach (var vanish in removals)
        {
            var removedHash = ContentHashCalculator.ComputeTransactionHash(
                vanish.OccurredOn,
                vanish.PurchaseOn,
                vanish.Description,
                vanish.MerchantCnpj,
                vanish.AmountCents,
                vanish.Currency,
                vanish.Status,
                vanish.BillId,
                vanish.InstallmentNumber,
                vanish.InstallmentTotal,
                isRemoved: true);

            await dbConn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.transaction_version (
                    id,
                    transaction_id,
                    version_number,
                    content_hash,
                    occurred_on,
                    purchase_on,
                    description,
                    merchant_cnpj,
                    amount_cents,
                    currency,
                    status,
                    bill_id,
                    installment_number,
                    installment_total,
                    is_removed,
                    raw_payload_enc
                )
                VALUES (
                    @Id,
                    @TransactionId,
                    @VersionNumber,
                    @ContentHash,
                    @OccurredOn,
                    @PurchaseOn,
                    @Description,
                    @MerchantCnpj,
                    @AmountCents,
                    @Currency,
                    @Status,
                    @BillId,
                    @InstallmentNumber,
                    @InstallmentTotal,
                    true,
                    NULL
                )
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    vanish.TransactionId,
                    VersionNumber = vanish.VersionNumber + 1,
                    ContentHash = removedHash,
                    vanish.OccurredOn,
                    vanish.PurchaseOn,
                    vanish.Description,
                    vanish.MerchantCnpj,
                    vanish.AmountCents,
                    vanish.Currency,
                    vanish.Status,
                    vanish.BillId,
                    vanish.InstallmentNumber,
                    vanish.InstallmentTotal
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));

            removed++;
        }

        await dbTx.CommitAsync(cancellationToken);
        return new AccountIngestCounts(accountId, inserted, versioned, removed, skippedDuplicates, seenTransactionIds.ToList());
    }

    private async Task<(int ClassifiedCount, int TransfersLinked)> ReclassifyAndLinkInternalAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var activeTransactions = (await connection.QueryAsync<ActiveTransactionRow>(new CommandDefinition(
            """
            WITH latest AS (
                SELECT DISTINCT ON (v.transaction_id)
                    v.transaction_id,
                    v.occurred_on,
                    v.description,
                    v.merchant_cnpj,
                    v.amount_cents,
                    v.is_removed
                FROM banking.transaction_version v
                ORDER BY v.transaction_id, v.version_number DESC
            )
            SELECT
                t.id AS TransactionId,
                t.account_id AS AccountId,
                a.kind AS AccountKind,
                lv.occurred_on AS OccurredOn,
                lv.description AS Description,
                lv.merchant_cnpj AS MerchantCnpj,
                lv.amount_cents AS AmountCents
            FROM banking.transaction t
            JOIN latest lv ON lv.transaction_id = t.id AND lv.is_removed = false
            JOIN banking.account a ON a.id = t.account_id
            WHERE t.household_id = @HouseholdId
            ORDER BY lv.occurred_on ASC, t.id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        if (activeTransactions.Count == 0)
        {
            return (0, 0);
        }

        var existingLinks = (await connection.QueryAsync<TransferLinkRow>(new CommandDefinition(
            """
            SELECT
                outflow_transaction_id AS OutflowTransactionId,
                inflow_transaction_id AS InflowTransactionId
            FROM banking.transfer_link
            WHERE household_id = @HouseholdId
              AND is_active = true
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var linkedTxIds = new HashSet<Guid>();
        foreach (var link in existingLinks)
        {
            linkedTxIds.Add(link.OutflowTransactionId);
            linkedTxIds.Add(link.InflowTransactionId);
        }

        // Pair unlinked opposite-sign movements across two distinct non-card accounts within +/-2 days (ADR-014).
        var newLinks = new List<(Guid OutflowId, Guid InflowId)>();
        var outflows = activeTransactions
            .Where(t => !linkedTxIds.Contains(t.TransactionId) &&
                        t.AccountKind != "credit_card" &&
                        t.AmountCents < 0 &&
                        IsTransferCandidate(t))
            .ToList();

        var inflows = activeTransactions
            .Where(t => !linkedTxIds.Contains(t.TransactionId) &&
                        t.AccountKind != "credit_card" &&
                        t.AmountCents > 0 &&
                        IsTransferCandidate(t))
            .ToList();

        foreach (var outflow in outflows)
        {
            if (linkedTxIds.Contains(outflow.TransactionId))
            {
                continue;
            }

            var match = inflows
                .Where(inflow => !linkedTxIds.Contains(inflow.TransactionId) &&
                                 inflow.AccountId != outflow.AccountId &&
                                 inflow.AmountCents == -outflow.AmountCents &&
                                 Math.Abs(inflow.OccurredOn.DayNumber - outflow.OccurredOn.DayNumber) <= 2)
                .OrderBy(inflow => Math.Abs(inflow.OccurredOn.DayNumber - outflow.OccurredOn.DayNumber))
                .ThenBy(inflow => inflow.TransactionId)
                .FirstOrDefault();

            if (match is not null)
            {
                linkedTxIds.Add(outflow.TransactionId);
                linkedTxIds.Add(match.TransactionId);
                newLinks.Add((outflow.TransactionId, match.TransactionId));
            }
        }

        var txKinds = new List<string>(activeTransactions.Count);
        var inputs = new List<CategorizationInput>(activeTransactions.Count);

        foreach (var tx in activeTransactions)
        {
            var txKind = DetermineMovementKind(tx, linkedTxIds.Contains(tx.TransactionId));
            txKinds.Add(txKind);
            inputs.Add(new CategorizationInput(
                householdId,
                tx.Description,
                tx.MerchantCnpj,
                tx.AmountCents,
                txKind));
        }

        var results = await categorizationEngine.ClassifyBatchAsync(householdId, inputs, cancellationToken);

        await using var dbTx = await connection.BeginTransactionAsync(cancellationToken);

        var transfersLinked = 0;
        foreach (var (outflowId, inflowId) in newLinks)
        {
            var rows = await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.transfer_link (
                    id,
                    household_id,
                    outflow_transaction_id,
                    inflow_transaction_id,
                    is_active
                )
                VALUES (
                    @Id,
                    @HouseholdId,
                    @OutflowId,
                    @InflowId,
                    true
                )
                ON CONFLICT DO NOTHING
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    HouseholdId = householdId,
                    OutflowId = outflowId,
                    InflowId = inflowId
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));

            transfersLinked += rows;
        }

        for (var i = 0; i < activeTransactions.Count; i++)
        {
            var tx = activeTransactions[i];
            var txKind = txKinds[i];
            var result = results[i];

            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.classification (
                    transaction_id,
                    tx_kind,
                    category,
                    essentiality,
                    brand,
                    deciding_layer,
                    deciding_rule_id,
                    deciding_rule_name,
                    explanation,
                    classified_at
                )
                VALUES (
                    @TransactionId,
                    @TxKind,
                    @Category,
                    @Essentiality,
                    @Brand,
                    @DecidingLayer,
                    @DecidingRuleId,
                    @DecidingRuleName,
                    @Explanation,
                    now()
                )
                ON CONFLICT (transaction_id) DO UPDATE
                SET tx_kind = EXCLUDED.tx_kind,
                    category = EXCLUDED.category,
                    essentiality = EXCLUDED.essentiality,
                    brand = EXCLUDED.brand,
                    deciding_layer = EXCLUDED.deciding_layer,
                    deciding_rule_id = EXCLUDED.deciding_rule_id,
                    deciding_rule_name = EXCLUDED.deciding_rule_name,
                    explanation = EXCLUDED.explanation,
                    classified_at = now()
                WHERE banking.classification.tx_kind IS DISTINCT FROM EXCLUDED.tx_kind
                   OR banking.classification.category IS DISTINCT FROM EXCLUDED.category
                   OR banking.classification.essentiality IS DISTINCT FROM EXCLUDED.essentiality
                   OR banking.classification.brand IS DISTINCT FROM EXCLUDED.brand
                   OR banking.classification.deciding_layer IS DISTINCT FROM EXCLUDED.deciding_layer
                   OR banking.classification.deciding_rule_id IS DISTINCT FROM EXCLUDED.deciding_rule_id
                   OR banking.classification.deciding_rule_name IS DISTINCT FROM EXCLUDED.deciding_rule_name
                   OR banking.classification.explanation IS DISTINCT FROM EXCLUDED.explanation
                """,
                new
                {
                    tx.TransactionId,
                    TxKind = txKind,
                    result.Category,
                    result.Essentiality,
                    result.Brand,
                    result.DecidingLayer,
                    result.DecidingRuleId,
                    result.DecidingRuleName,
                    result.Explanation
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));
        }

        await dbTx.CommitAsync(cancellationToken);
        return (activeTransactions.Count, transfersLinked);
    }

    private async Task EvaluateConnectionAlertsAsync(
        ConnectionRow connection,
        CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var expiringKey = $"consent_expiring:{connection.Id}";
        var expiredKey = $"consent_expired:{connection.Id}";
        var failingKey = $"sync_failing_48h:{connection.Id}";

        var isExpired = string.Equals(connection.Status, "expired", StringComparison.Ordinal) ||
                        (connection.ConsentExpiresAt.HasValue && connection.ConsentExpiresAt.Value <= now);

        var isExpiringSoon = !isExpired &&
                             connection.ConsentExpiresAt.HasValue &&
                             connection.ConsentExpiresAt.Value <= now.AddDays(30);

        var isFailing48h = connection.FirstFailureAt.HasValue &&
                           connection.FirstFailureAt.Value <= now.AddHours(-48);

        if (isExpiringSoon)
        {
            var daysLeft = Math.Max(1, (int)Math.Ceiling((connection.ConsentExpiresAt!.Value - now).TotalDays));
            await alertPublisher.RaiseAsync(
                new AlertRequest(
                    connection.HouseholdId,
                    expiringKey,
                    "consent_expiring",
                    "warning",
                    $"Consentimento de {connection.InstitutionName} vence em breve",
                    $"O consentimento Open Finance de {connection.InstitutionName} vence em {daysLeft} dia(s). Renove para manter a sincronização em dia.",
                    $"/banks/{connection.Id}"),
                cancellationToken);
        }
        else
        {
            await alertPublisher.ResolveAsync(connection.HouseholdId, expiringKey, cancellationToken);
        }

        if (isExpired)
        {
            await alertPublisher.RaiseAsync(
                new AlertRequest(
                    connection.HouseholdId,
                    expiredKey,
                    "consent_expired",
                    "error",
                    $"Consentimento de {connection.InstitutionName} expirado",
                    $"A conexão com {connection.InstitutionName} expirou. Renove o consentimento para voltar a receber transações.",
                    $"/banks/{connection.Id}"),
                cancellationToken);
        }
        else
        {
            await alertPublisher.ResolveAsync(connection.HouseholdId, expiredKey, cancellationToken);
        }

        if (isFailing48h)
        {
            await alertPublisher.RaiseAsync(
                new AlertRequest(
                    connection.HouseholdId,
                    failingKey,
                    "sync_failing_48h",
                    "error",
                    $"Falha contínua ao sincronizar {connection.InstitutionName}",
                    $"Não foi possível atualizar {connection.InstitutionName} há mais de 48 horas. Verifique a conexão bancária.",
                    $"/banks/{connection.Id}"),
                cancellationToken);
        }
        else
        {
            await alertPublisher.ResolveAsync(connection.HouseholdId, failingKey, cancellationToken);
        }
    }

    private static bool IsTransferCandidate(ActiveTransactionRow tx)
    {
        var norm = MerchantNormalizer.NormalizeDescription(tx.Description);

        // Exclude clear non-transfer movements
        if (norm.Contains("fatura", StringComparison.Ordinal) ||
            norm.Contains("salario", StringComparison.Ordinal) ||
            norm.Contains("freelance", StringComparison.Ordinal) ||
            norm.Contains("saque", StringComparison.Ordinal) ||
            norm.Contains("aplicacao", StringComparison.Ordinal) ||
            norm.Contains("resgate", StringComparison.Ordinal) ||
            norm.Contains("cdb", StringComparison.Ordinal))
        {
            return false;
        }

        return norm.Contains("transferencia", StringComparison.Ordinal) ||
               norm.Contains("transf", StringComparison.Ordinal) ||
               norm.Contains("pix", StringComparison.Ordinal) ||
               norm.Contains("ted", StringComparison.Ordinal) ||
               norm.Contains("doc", StringComparison.Ordinal) ||
               norm.Contains("poupanca", StringComparison.Ordinal) ||
               norm.Contains("conta corrente", StringComparison.Ordinal);
    }

    private static string DetermineMovementKind(ActiveTransactionRow tx, bool isLinkedTransfer)
    {
        if (isLinkedTransfer)
        {
            return "own_transfer";
        }

        var norm = MerchantNormalizer.NormalizeDescription(tx.Description);

        if (string.Equals(tx.AccountKind, "credit_card", StringComparison.Ordinal))
        {
            if (tx.AmountCents > 0)
            {
                if (norm.Contains("estorno", StringComparison.Ordinal) ||
                    norm.Contains("reembolso", StringComparison.Ordinal) ||
                    norm.Contains("refund", StringComparison.Ordinal) ||
                    norm.Contains("devolucao", StringComparison.Ordinal) ||
                    norm.Contains("cashback", StringComparison.Ordinal))
                {
                    return "refund";
                }

                if (norm.Contains("pagamento", StringComparison.Ordinal) ||
                    norm.Contains("fatura", StringComparison.Ordinal) ||
                    norm.Contains("pagto", StringComparison.Ordinal))
                {
                    return "card_payment";
                }

                return "refund";
            }

            return "expense";
        }

        if (norm.Contains("pagamento da fatura", StringComparison.Ordinal) ||
            norm.Contains("pagamento fatura", StringComparison.Ordinal) ||
            norm.Contains("fatura do cartao", StringComparison.Ordinal) ||
            norm.Contains("fatura cartao", StringComparison.Ordinal) ||
            norm.Contains("pgto fatura", StringComparison.Ordinal) ||
            norm.Contains("pagto cartao", StringComparison.Ordinal))
        {
            return "card_payment";
        }

        if (norm.Contains("saque", StringComparison.Ordinal) ||
            norm.Contains("banco24horas", StringComparison.Ordinal) ||
            norm.Contains("caixa eletronico", StringComparison.Ordinal) ||
            $" {norm} ".Contains(" atm ", StringComparison.Ordinal))
        {
            return "withdrawal";
        }

        if (tx.AmountCents < 0 &&
            (norm.Contains("aplicacao", StringComparison.Ordinal) ||
             norm.Contains("cdb", StringComparison.Ordinal) ||
             norm.Contains("tesouro", StringComparison.Ordinal) ||
             norm.Contains("rdb", StringComparison.Ordinal) ||
             norm.Contains("investimento", StringComparison.Ordinal) ||
             norm.Contains("lci", StringComparison.Ordinal) ||
             norm.Contains("lca", StringComparison.Ordinal)))
        {
            return "investment";
        }

        if (tx.AmountCents > 0 &&
            (norm.Contains("resgate", StringComparison.Ordinal) ||
             norm.Contains("cdb", StringComparison.Ordinal) ||
             norm.Contains("tesouro", StringComparison.Ordinal) ||
             norm.Contains("investimento", StringComparison.Ordinal)))
        {
            return "redemption";
        }

        if (tx.AmountCents > 0 &&
            (norm.Contains("estorno", StringComparison.Ordinal) ||
             norm.Contains("reembolso", StringComparison.Ordinal) ||
             norm.Contains("refund", StringComparison.Ordinal) ||
             norm.Contains("devolucao", StringComparison.Ordinal)))
        {
            return "refund";
        }

        return tx.AmountCents > 0 ? "income" : "expense";
    }

    private static string ClassifyErrorCode(Exception ex) => ex switch
    {
        HttpRequestException httpEx when httpEx.StatusCode is not null => $"http_{(int)httpEx.StatusCode}",
        HttpRequestException => "provider_network_error",
        TaskCanceledException => "provider_timeout",
        _ => "sync_error"
    };

    private sealed record ConnectionRow(
        Guid Id,
        Guid HouseholdId,
        string Provider,
        string ExternalItemId,
        string InstitutionName,
        string BrandColor,
        string Status,
        DateTimeOffset? ConsentExpiresAt,
        DateTimeOffset? LastSyncedAt,
        string? LastErrorCode,
        int ConsecutiveFailures,
        DateTimeOffset? FirstFailureAt);

    private sealed record ExistingBillRow(Guid Id, string ExternalBillId);

    private sealed record ExistingSourceRow(Guid TransactionId, string Source, string ExternalId);

    private sealed record LatestVersionRow(
        Guid TransactionId,
        int VersionNumber,
        string ContentHash,
        DateOnly OccurredOn,
        DateOnly? PurchaseOn,
        string Description,
        string? MerchantCnpj,
        long AmountCents,
        string Currency,
        string Status,
        Guid? BillId,
        int? InstallmentNumber,
        int? InstallmentTotal,
        bool IsRemoved);

    private sealed record ActiveTransactionRow(
        Guid TransactionId,
        Guid AccountId,
        string AccountKind,
        DateOnly OccurredOn,
        string Description,
        string? MerchantCnpj,
        long AmountCents);

    private sealed record TransferLinkRow(Guid OutflowTransactionId, Guid InflowTransactionId);

    private sealed record RuleMatchRow(Guid RuleId, int MatchCount);

    private sealed record AccountIngestCounts(
        Guid AccountId,
        int Inserted,
        int Versioned,
        int Removed,
        int SkippedDuplicates,
        IReadOnlyList<Guid> SeenTransactionIds);
}

internal sealed record ImportStatementRequest(
    string? InstitutionName,
    string? AccountName,
    string? AccountKind,
    string? Content);

internal sealed record ImportResponse(
    Guid ConnectionId,
    Guid AccountId,
    int Inserted,
    int SkippedDuplicates,
    int TransfersLinked,
    int UncategorizedCount);

