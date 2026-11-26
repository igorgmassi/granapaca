using System.Globalization;
using Dapper;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Categorization.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class BankingAnalyticsService(NpgsqlDataSource dataSource)
    : IBankingAnalyticsReader, IBankingSplitWriter
{
    public async Task<BankingMonthMetrics> GetMonthMetricsAsync(
        Guid householdId,
        DateOnly monthStart,
        CancellationToken cancellationToken = default)
    {
        var monthEndExclusive = monthStart.AddMonths(1);
        var lookbackStart = monthStart.AddMonths(-3);
        var monthLabel = monthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var accounts = (await connection.QueryAsync<AccountBalanceRow>(new CommandDefinition(
            """
            SELECT
                a.kind AS Kind,
                COALESCE(
                    (SELECT bs.balance_cents
                     FROM banking.balance_snapshot bs
                     WHERE bs.account_id = a.id
                     ORDER BY bs.captured_at DESC, bs.id DESC
                     LIMIT 1),
                    a.opening_balance_cents
                ) AS BalanceCents,
                (SELECT COALESCE(SUM(cb.total_cents), 0)::bigint
                 FROM banking.card_bill cb
                 WHERE cb.account_id = a.id AND cb.is_open = true) AS OpenBillCents
            FROM banking.account a
            WHERE a.household_id = @HouseholdId
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        long balanceCents = 0;
        long cardBillCents = 0;
        foreach (var acc in accounts)
        {
            if (string.Equals(acc.Kind, "credit_card", StringComparison.Ordinal))
            {
                cardBillCents += acc.OpenBillCents > 0
                    ? acc.OpenBillCents
                    : Math.Max(0, -acc.BalanceCents);
            }
            else
            {
                balanceCents += acc.BalanceCents;
            }
        }

        var windowTxs = (await connection.QueryAsync<AnalyticsTransactionRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                occurred_on AS OccurredOn,
                original_description AS OriginalDescription,
                amount_cents AS AmountCents,
                effective_kind AS EffectiveKind,
                effective_category AS EffectiveCategory,
                effective_essentiality AS EffectiveEssentiality,
                effective_is_atypical AS EffectiveIsAtypical,
                installment_total AS InstallmentTotal
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND occurred_on >= @LookbackStart
              AND occurred_on < @MonthEndExclusive
            ORDER BY occurred_on ASC, id ASC
            """,
            new
            {
                HouseholdId = householdId,
                LookbackStart = lookbackStart,
                MonthEndExclusive = monthEndExclusive
            },
            cancellationToken: cancellationToken))).ToList();

        var monthTxs = new List<AnalyticsTransactionRow>();
        var priorTxs = new List<AnalyticsTransactionRow>();
        foreach (var tx in windowTxs)
        {
            if (tx.OccurredOn >= monthStart)
            {
                monthTxs.Add(tx);
            }
            else
            {
                priorTxs.Add(tx);
            }
        }

        var splitsByTx = new Dictionary<Guid, List<SplitPartRow>>();
        if (monthTxs.Count > 0)
        {
            var monthTxIds = monthTxs.Select(t => t.Id).ToArray();
            var splitRows = await connection.QueryAsync<SplitPartRow>(new CommandDefinition(
                """
                SELECT
                    transaction_id AS TransactionId,
                    amount_cents AS AmountCents,
                    category AS Category,
                    essentiality AS Essentiality
                FROM banking.transaction_split
                WHERE transaction_id = ANY(@TransactionIds)
                ORDER BY transaction_id ASC, part_index ASC
                """,
                new { TransactionIds = monthTxIds },
                cancellationToken: cancellationToken));

            foreach (var split in splitRows)
            {
                if (!splitsByTx.TryGetValue(split.TransactionId, out var list))
                {
                    list = [];
                    splitsByTx[split.TransactionId] = list;
                }

                list.Add(split);
            }
        }

        long spentCents = 0;
        long receivedCents = 0;
        long essentialSpentCents = 0;
        long importantSpentCents = 0;
        long flexibleSpentCents = 0;
        long atypicalSpentCents = 0;

        var spentByCategory = new Dictionary<string, long>(StringComparer.Ordinal);
        var dailySpending = new Dictionary<DateOnly, long>();

        foreach (var tx in monthTxs)
        {
            if (string.Equals(tx.EffectiveKind, "income", StringComparison.Ordinal))
            {
                receivedCents += tx.AmountCents;
                continue;
            }

            if (tx.EffectiveKind is not ("expense" or "refund"))
            {
                continue;
            }

            var txSpent = -tx.AmountCents;
            spentCents += txSpent;

            if (tx.EffectiveIsAtypical)
            {
                atypicalSpentCents += txSpent;
            }

            dailySpending[tx.OccurredOn] = dailySpending.GetValueOrDefault(tx.OccurredOn) + txSpent;

            if (splitsByTx.TryGetValue(tx.Id, out var txSplits) && txSplits.Count > 0)
            {
                foreach (var part in txSplits)
                {
                    var partSpent = -part.AmountCents;
                    var partCategory = part.Category ?? tx.EffectiveCategory ?? "uncategorized";
                    var partEssentiality = part.Essentiality ?? tx.EffectiveEssentiality;

                    spentByCategory[partCategory] = spentByCategory.GetValueOrDefault(partCategory) + partSpent;
                    AccumulateEssentiality(
                        partEssentiality,
                        partSpent,
                        ref essentialSpentCents,
                        ref importantSpentCents,
                        ref flexibleSpentCents);
                }
            }
            else
            {
                var category = tx.EffectiveCategory ?? "uncategorized";
                spentByCategory[category] = spentByCategory.GetValueOrDefault(category) + txSpent;
                AccumulateEssentiality(
                    tx.EffectiveEssentiality,
                    txSpent,
                    ref essentialSpentCents,
                    ref importantSpentCents,
                    ref flexibleSpentCents);
            }
        }

        var recurringSpentCents = ComputeRecurringSpentCents(monthTxs, priorTxs);

        var orderedCategories = spentByCategory
            .Where(kv => kv.Value > 0)
            .OrderByDescending(kv => kv.Value)
            .ThenBy(kv => kv.Key, StringComparer.Ordinal)
            .ToDictionary(kv => kv.Key, kv => kv.Value, StringComparer.Ordinal);

        var orderedDaily = dailySpending
            .Where(kv => kv.Value > 0)
            .OrderBy(kv => kv.Key)
            .ToDictionary(kv => kv.Key, kv => kv.Value);

        return new BankingMonthMetrics(
            monthLabel,
            balanceCents,
            spentCents,
            receivedCents,
            receivedCents - spentCents,
            cardBillCents,
            essentialSpentCents,
            importantSpentCents,
            flexibleSpentCents,
            recurringSpentCents,
            atypicalSpentCents,
            orderedCategories,
            orderedDaily);
    }

    public async Task<IReadOnlyList<BankingTransactionFact>> GetTransactionsInRangeAsync(
        Guid householdId,
        DateOnly from,
        DateOnly toExclusive,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var rows = (await connection.QueryAsync<TransactionFactRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                account_id AS AccountId,
                account_name AS AccountName,
                institution_name AS InstitutionName,
                occurred_on AS OccurredOn,
                effective_description AS Description,
                amount_cents AS AmountCents,
                effective_kind AS Kind,
                effective_category AS Category,
                effective_essentiality AS Essentiality,
                effective_payment_method AS PaymentMethod,
                effective_is_atypical AS IsAtypical
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND occurred_on >= @From
              AND occurred_on < @ToExclusive
            ORDER BY occurred_on DESC, id DESC
            """,
            new
            {
                HouseholdId = householdId,
                From = from,
                ToExclusive = toExclusive
            },
            cancellationToken: cancellationToken))).ToList();

        var tagsByTx = await BankingQueries.LoadTagsByTransactionIdsAsync(
            connection,
            rows.Select(r => r.Id).ToArray(),
            cancellationToken);

        return rows
            .Select(r => new BankingTransactionFact(
                r.Id,
                r.AccountId,
                r.AccountName,
                r.InstitutionName,
                r.OccurredOn,
                r.Description,
                r.AmountCents,
                r.Kind,
                r.Category,
                r.Essentiality,
                r.PaymentMethod,
                r.IsAtypical,
                tagsByTx.TryGetValue(r.Id, out var tags) ? tags : []))
            .ToList();
    }

    public async Task<(bool Ok, string? Error)> ReplaceTransactionSplitsAsync(
        Guid householdId,
        Guid transactionId,
        IReadOnlyList<BankingSplitInput> splits,
        CancellationToken cancellationToken = default)
    {
        var (statusCode, error, _) = await ReplaceSplitsCoreAsync(
            householdId,
            transactionId,
            splits,
            cancellationToken);

        return (statusCode == 200, error);
    }

    public async Task<TransactionSplitsResponse?> GetTransactionSplitsAsync(
        Guid householdId,
        Guid transactionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var txAmount = await connection.QuerySingleOrDefaultAsync<long?>(new CommandDefinition(
            """
            SELECT amount_cents
            FROM banking.transaction_effective
            WHERE id = @TransactionId
              AND household_id = @HouseholdId
            """,
            new { TransactionId = transactionId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (!txAmount.HasValue)
        {
            return null;
        }

        var parts = (await connection.QueryAsync<TransactionSplitDto>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                part_index AS PartIndex,
                description AS Description,
                amount_cents AS AmountCents,
                category AS Category,
                essentiality AS Essentiality,
                created_at AS CreatedAt
            FROM banking.transaction_split
            WHERE transaction_id = @TransactionId
            ORDER BY part_index ASC
            """,
            new { TransactionId = transactionId },
            cancellationToken: cancellationToken))).ToList();

        return new TransactionSplitsResponse(transactionId, txAmount.Value, parts);
    }

    public async Task<(int StatusCode, string? Error, TransactionSplitsResponse? Data)> ReplaceTransactionSplitsEndpointAsync(
        Guid householdId,
        Guid transactionId,
        ReplaceTransactionSplitsRequest? request,
        CancellationToken cancellationToken)
    {
        if (request?.Parts is null)
        {
            return (400, "Informe a lista de partes do rateio.", null);
        }

        var inputs = request.Parts
            .Select(p => new BankingSplitInput(
                p.Description ?? string.Empty,
                p.AmountCents,
                p.Category,
                p.Essentiality))
            .ToList();

        return await ReplaceSplitsCoreAsync(householdId, transactionId, inputs, cancellationToken);
    }

    private async Task<(int StatusCode, string? Error, TransactionSplitsResponse? Data)> ReplaceSplitsCoreAsync(
        Guid householdId,
        Guid transactionId,
        IReadOnlyList<BankingSplitInput>? splits,
        CancellationToken cancellationToken)
    {
        if (splits is null)
        {
            return (400, "Informe a lista de partes do rateio.", null);
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var txAmount = await connection.QuerySingleOrDefaultAsync<long?>(new CommandDefinition(
            """
            SELECT amount_cents
            FROM banking.transaction_effective
            WHERE id = @TransactionId
              AND household_id = @HouseholdId
            """,
            new { TransactionId = transactionId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (!txAmount.HasValue)
        {
            return (404, "Transação não encontrada.", null);
        }

        var expectedTotal = txAmount.Value;
        var expectedSign = Math.Sign(expectedTotal);
        var normalized = new List<(string Description, long AmountCents, string? Category, string? Essentiality)>(splits.Count);

        if (splits.Count > 0)
        {
            long runningTotal = 0;

            foreach (var part in splits)
            {
                if (string.IsNullOrWhiteSpace(part.Description))
                {
                    return (400, "Informe a descrição de cada parte do rateio.", null);
                }

                if (part.AmountCents == 0)
                {
                    return (400, "Cada parte do rateio deve ter valor diferente de zero.", null);
                }

                if (Math.Sign(part.AmountCents) != expectedSign)
                {
                    return (400, "Todas as partes do rateio devem ter o mesmo sinal da transação.", null);
                }

                string? normalizedCategory = null;
                if (!string.IsNullOrWhiteSpace(part.Category))
                {
                    normalizedCategory = part.Category.Trim().ToLowerInvariant();
                    if (!BankingTaxonomy.EditableCategories.Contains(normalizedCategory))
                    {
                        return (400, "Categoria inválida em uma das partes do rateio.", null);
                    }
                }

                string? normalizedEssentiality = null;
                if (!string.IsNullOrWhiteSpace(part.Essentiality))
                {
                    normalizedEssentiality = part.Essentiality.Trim().ToLowerInvariant();
                    if (!BankingTaxonomy.Essentialities.Contains(normalizedEssentiality))
                    {
                        return (400, "Essencialidade inválida em uma das partes do rateio; use essential, important ou flexible.", null);
                    }
                }

                try
                {
                    runningTotal = checked(runningTotal + part.AmountCents);
                }
                catch (OverflowException)
                {
                    return (400, "A soma das partes do rateio excede o limite suportado.", null);
                }

                normalized.Add((part.Description.Trim(), part.AmountCents, normalizedCategory, normalizedEssentiality));
            }

            if (runningTotal != expectedTotal)
            {
                return (400, "A soma das partes do rateio deve ser exatamente igual ao valor da transação.", null);
            }
        }

        var insertedParts = new List<TransactionSplitDto>(normalized.Count);

        await using var dbTx = await connection.BeginTransactionAsync(cancellationToken);

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM banking.transaction_split WHERE transaction_id = @TransactionId",
            new { TransactionId = transactionId },
            transaction: dbTx,
            cancellationToken: cancellationToken));

        for (var i = 0; i < normalized.Count; i++)
        {
            var part = normalized[i];
            var splitId = Guid.CreateVersion7();

            var createdAt = await connection.ExecuteScalarAsync<DateTimeOffset>(new CommandDefinition(
                """
                INSERT INTO banking.transaction_split (
                    id,
                    transaction_id,
                    part_index,
                    description,
                    amount_cents,
                    category,
                    essentiality
                )
                VALUES (
                    @Id,
                    @TransactionId,
                    @PartIndex,
                    @Description,
                    @AmountCents,
                    @Category,
                    @Essentiality
                )
                RETURNING created_at
                """,
                new
                {
                    Id = splitId,
                    TransactionId = transactionId,
                    PartIndex = i,
                    part.Description,
                    part.AmountCents,
                    part.Category,
                    part.Essentiality
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));

            insertedParts.Add(new TransactionSplitDto(
                splitId,
                i,
                part.Description,
                part.AmountCents,
                part.Category,
                part.Essentiality,
                createdAt));
        }

        await dbTx.CommitAsync(cancellationToken);

        return (200, null, new TransactionSplitsResponse(transactionId, expectedTotal, insertedParts));
    }

    private static void AccumulateEssentiality(
        string? essentiality,
        long spentCents,
        ref long essentialSpentCents,
        ref long importantSpentCents,
        ref long flexibleSpentCents)
    {
        switch (essentiality)
        {
            case "essential":
                essentialSpentCents += spentCents;
                break;
            case "important":
                importantSpentCents += spentCents;
                break;
            case "flexible":
                flexibleSpentCents += spentCents;
                break;
        }
    }

    private static long ComputeRecurringSpentCents(
        List<AnalyticsTransactionRow> monthTxs,
        List<AnalyticsTransactionRow> priorTxs)
    {
        var priorSinglePerMonth = new Dictionary<string, List<long>>(StringComparer.Ordinal);

        var priorGroups = priorTxs
            .Where(t => string.Equals(t.EffectiveKind, "expense", StringComparison.Ordinal) && !t.EffectiveIsAtypical)
            .GroupBy(t => (
                Merchant: MerchantNormalizer.NormalizeDescription(t.OriginalDescription),
                t.OccurredOn.Year,
                t.OccurredOn.Month));

        foreach (var group in priorGroups)
        {
            if (string.IsNullOrEmpty(group.Key.Merchant))
            {
                continue;
            }

            var items = group.ToList();
            if (items.Count != 1)
            {
                continue;
            }

            if (!priorSinglePerMonth.TryGetValue(group.Key.Merchant, out var amounts))
            {
                amounts = [];
                priorSinglePerMonth[group.Key.Merchant] = amounts;
            }

            amounts.Add(-items[0].AmountCents);
        }

        var currentMerchantCounts = monthTxs
            .Where(t => string.Equals(t.EffectiveKind, "expense", StringComparison.Ordinal) && !t.EffectiveIsAtypical)
            .GroupBy(t => MerchantNormalizer.NormalizeDescription(t.OriginalDescription), StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.Count(), StringComparer.Ordinal);

        long recurring = 0;
        foreach (var tx in monthTxs)
        {
            if (!string.Equals(tx.EffectiveKind, "expense", StringComparison.Ordinal) || tx.EffectiveIsAtypical)
            {
                continue;
            }

            var spent = -tx.AmountCents;
            if (spent <= 0)
            {
                continue;
            }

            if (tx.InstallmentTotal is > 1)
            {
                recurring += spent;
                continue;
            }

            var merchant = MerchantNormalizer.NormalizeDescription(tx.OriginalDescription);
            if (string.IsNullOrEmpty(merchant))
            {
                continue;
            }

            if (currentMerchantCounts.GetValueOrDefault(merchant) == 1 &&
                priorSinglePerMonth.TryGetValue(merchant, out var priorAmounts) &&
                priorAmounts.Any(prior => Math.Abs(prior - spent) * 4 <= Math.Max(prior, spent)))
            {
                recurring += spent;
            }
        }

        return recurring;
    }

    private sealed record AccountBalanceRow(
        string Kind,
        long BalanceCents,
        long OpenBillCents);

    private sealed record AnalyticsTransactionRow(
        Guid Id,
        DateOnly OccurredOn,
        string OriginalDescription,
        long AmountCents,
        string EffectiveKind,
        string? EffectiveCategory,
        string? EffectiveEssentiality,
        bool EffectiveIsAtypical,
        int? InstallmentTotal);

    private sealed record SplitPartRow(
        Guid TransactionId,
        long AmountCents,
        string? Category,
        string? Essentiality);

    private sealed record TransactionFactRow(
        Guid Id,
        Guid AccountId,
        string AccountName,
        string InstitutionName,
        DateOnly OccurredOn,
        string Description,
        long AmountCents,
        string Kind,
        string? Category,
        string? Essentiality,
        string? PaymentMethod,
        bool IsAtypical);
}

internal sealed record TransactionSplitInputDto(
    string? Description = null,
    long AmountCents = 0,
    string? Category = null,
    string? Essentiality = null);

internal sealed record ReplaceTransactionSplitsRequest(
    IReadOnlyList<TransactionSplitInputDto>? Parts = null);

internal sealed record TransactionSplitsResponse(
    Guid TransactionId,
    long TransactionAmountCents,
    IReadOnlyList<TransactionSplitDto> Parts);
