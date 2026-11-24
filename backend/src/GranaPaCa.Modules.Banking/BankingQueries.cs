using System.Globalization;
using System.Text;
using Dapper;
using GranaPaCa.Modules.Categorization.Contracts;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class BankingQueries(NpgsqlDataSource dataSource, IConfiguration configuration)
{
    private readonly TimeZoneInfo _instanceTimeZone = DateParser.ResolveInstanceTimeZone(configuration);

    public async Task<(bool Ok, string? Error, SummaryResponse? Data)> GetSummaryAsync(
        Guid householdId,
        string? month,
        Guid? bankId,
        CancellationToken cancellationToken)
    {
        DateOnly monthStart;
        string monthLabel;

        if (string.IsNullOrWhiteSpace(month))
        {
            var today = DateParser.TodayInTimeZone(_instanceTimeZone);
            monthStart = new DateOnly(today.Year, today.Month, 1);
            monthLabel = monthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);
        }
        else if (DateOnly.TryParseExact(
            month.Trim() + "-01",
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out monthStart))
        {
            monthLabel = monthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);
        }
        else
        {
            return (false, "Mês inválido; use o formato YYYY-MM.", null);
        }

        var monthEndExclusive = monthStart.AddMonths(1);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var allConnections = (await connection.QueryAsync<ConnectionSummaryRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
                status AS Status,
                last_synced_at AS LastSyncedAt,
                consent_expires_at AS ConsentExpiresAt
            FROM banking.connection
            WHERE household_id = @HouseholdId
            ORDER BY created_at ASC, id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var hasConnections = allConnections.Count > 0;
        var filteredConnections = bankId.HasValue
            ? allConnections.Where(c => c.Id == bankId.Value).ToList()
            : allConnections;

        var accounts = (await connection.QueryAsync<AccountBalanceRow>(new CommandDefinition(
            """
            SELECT
                a.id AS Id,
                a.connection_id AS ConnectionId,
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

        var monthlyFlows = (await connection.QueryAsync<BankMonthlyFlowRow>(new CommandDefinition(
            """
            SELECT
                connection_id AS ConnectionId,
                COALESCE(SUM(CASE WHEN effective_kind IN ('expense', 'refund') THEN -amount_cents ELSE 0 END), 0)::bigint AS SpentCents,
                COALESCE(SUM(CASE WHEN effective_kind = 'income' THEN amount_cents ELSE 0 END), 0)::bigint AS ReceivedCents
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND occurred_on >= @From
              AND occurred_on < @ToExclusive
            GROUP BY connection_id
            """,
            new
            {
                HouseholdId = householdId,
                From = monthStart,
                ToExclusive = monthEndExclusive
            },
            cancellationToken: cancellationToken)))
            .ToDictionary(r => r.ConnectionId);

        var accountsByBank = accounts
            .GroupBy(a => a.ConnectionId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var bankSummaries = new List<BankSummaryDto>(filteredConnections.Count);
        long totalBalance = 0;
        long totalCardBill = 0;
        long totalSpent = 0;
        long totalReceived = 0;

        foreach (var conn in filteredConnections)
        {
            var bankAccounts = accountsByBank.GetValueOrDefault(conn.Id) ?? [];
            long bankBalance = 0;
            long bankCardBill = 0;

            foreach (var acc in bankAccounts)
            {
                if (acc.Kind == "credit_card")
                {
                    bankCardBill += acc.OpenBillCents > 0
                        ? acc.OpenBillCents
                        : Math.Max(0, -acc.BalanceCents);
                }
                else
                {
                    bankBalance += acc.BalanceCents;
                }
            }

            var flow = monthlyFlows.GetValueOrDefault(conn.Id);
            var bankSpent = flow?.SpentCents ?? 0;
            var bankReceived = flow?.ReceivedCents ?? 0;

            totalBalance += bankBalance;
            totalCardBill += bankCardBill;
            totalSpent += bankSpent;
            totalReceived += bankReceived;

            bankSummaries.Add(new BankSummaryDto(
                conn.Id,
                conn.InstitutionName,
                conn.BrandColor,
                conn.Status,
                conn.LastSyncedAt,
                conn.ConsentExpiresAt,
                bankBalance,
                bankCardBill,
                bankSpent,
                bankReceived,
                bankAccounts.Count));
        }

        var response = new SummaryResponse(
            monthLabel,
            totalBalance,
            totalSpent,
            totalReceived,
            totalReceived - totalSpent,
            totalCardBill,
            hasConnections,
            bankSummaries);

        return (true, null, response);
    }

    public async Task<BanksListResponse> GetBanksAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        var banks = await LoadBankDetailsInternalAsync(householdId, connectionId: null, cancellationToken);
        return new BanksListResponse(banks);
    }

    public async Task<BankDetailDto?> GetBankDetailAsync(
        Guid householdId,
        Guid connectionId,
        CancellationToken cancellationToken)
    {
        var banks = await LoadBankDetailsInternalAsync(householdId, connectionId, cancellationToken);
        return banks.FirstOrDefault();
    }

    public async Task<CardBillsListResponse?> GetCardBillsAsync(
        Guid householdId,
        Guid accountId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var card = await connection.QuerySingleOrDefaultAsync<CardAccountHeaderRow>(new CommandDefinition(
            """
            SELECT
                a.id AS AccountId,
                a.name AS AccountName,
                a.last_four_digits AS LastFourDigits,
                c.institution_name AS InstitutionName
            FROM banking.account a
            JOIN banking.connection c ON c.id = a.connection_id
            WHERE a.id = @AccountId
              AND a.household_id = @HouseholdId
              AND a.kind = 'credit_card'
            """,
            new { AccountId = accountId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (card is null)
        {
            return null;
        }

        var bills = (await connection.QueryAsync<CardBillSummaryDto>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                period_month AS PeriodMonth,
                closing_on AS ClosingOn,
                due_on AS DueOn,
                total_cents AS TotalCents,
                is_open AS IsOpen
            FROM banking.card_bill
            WHERE account_id = @AccountId
            ORDER BY period_month DESC, due_on DESC
            """,
            new { AccountId = accountId },
            cancellationToken: cancellationToken))).ToList();

        return new CardBillsListResponse(
            card.AccountId,
            card.AccountName,
            card.LastFourDigits,
            card.InstitutionName,
            bills);
    }

    public async Task<CardBillDetailResponse?> GetCardBillDetailAsync(
        Guid householdId,
        Guid billId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var bill = await connection.QuerySingleOrDefaultAsync<CardBillHeaderRow>(new CommandDefinition(
            """
            SELECT
                cb.id AS Id,
                cb.account_id AS AccountId,
                a.name AS AccountName,
                a.last_four_digits AS LastFourDigits,
                c.institution_name AS InstitutionName,
                cb.period_month AS PeriodMonth,
                cb.closing_on AS ClosingOn,
                cb.due_on AS DueOn,
                cb.total_cents AS TotalCents,
                cb.is_open AS IsOpen
            FROM banking.card_bill cb
            JOIN banking.account a ON a.id = cb.account_id
            JOIN banking.connection c ON c.id = a.connection_id
            WHERE cb.id = @BillId
              AND a.household_id = @HouseholdId
            """,
            new { BillId = billId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (bill is null)
        {
            return null;
        }

        var purchases = (await connection.QueryAsync<CardBillPurchaseDto>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                occurred_on AS OccurredOn,
                purchase_on AS PurchaseOn,
                effective_description AS Description,
                original_description AS OriginalDescription,
                amount_cents AS AmountCents,
                effective_kind AS Kind,
                effective_category AS Category,
                effective_essentiality AS Essentiality,
                effective_brand AS Brand,
                installment_number AS InstallmentNumber,
                installment_total AS InstallmentTotal,
                status AS Status,
                has_manual_adjustments AS HasManualAdjustments
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND bill_id = @BillId
            ORDER BY occurred_on DESC, id DESC
            """,
            new { HouseholdId = householdId, BillId = billId },
            cancellationToken: cancellationToken))).ToList();

        return new CardBillDetailResponse(
            bill.Id,
            bill.AccountId,
            bill.AccountName,
            bill.LastFourDigits,
            bill.InstitutionName,
            bill.PeriodMonth,
            bill.ClosingOn,
            bill.DueOn,
            bill.TotalCents,
            bill.IsOpen,
            purchases);
    }

    public async Task<TransactionsPageResponse> GetTransactionsAsync(
        Guid householdId,
        DateOnly? from,
        DateOnly? to,
        Guid? bankId,
        Guid? accountId,
        string? kind,
        string? category,
        string? essentiality,
        string? brand,
        string? search,
        string? paymentMethod,
        string? tag,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var offset = (page - 1) * pageSize;

        var where = new StringBuilder("WHERE te.household_id = @HouseholdId");
        var parameters = new DynamicParameters();
        parameters.Add("HouseholdId", householdId);
        parameters.Add("PageSize", pageSize);
        parameters.Add("Offset", offset);

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

        if (bankId.HasValue)
        {
            where.Append(" AND te.connection_id = @BankId");
            parameters.Add("BankId", bankId.Value);
        }

        if (accountId.HasValue)
        {
            where.Append(" AND te.account_id = @AccountId");
            parameters.Add("AccountId", accountId.Value);
        }

        if (!string.IsNullOrWhiteSpace(kind))
        {
            where.Append(" AND te.effective_kind = @Kind");
            parameters.Add("Kind", kind.Trim().ToLowerInvariant());
        }

        if (!string.IsNullOrWhiteSpace(category))
        {
            var normalizedCategory = category.Trim().ToLowerInvariant();
            if (normalizedCategory == "uncategorized")
            {
                where.Append(" AND te.effective_category IS NULL");
            }
            else
            {
                where.Append(" AND te.effective_category = @Category");
                parameters.Add("Category", normalizedCategory);
            }
        }

        if (!string.IsNullOrWhiteSpace(essentiality))
        {
            where.Append(" AND te.effective_essentiality = @Essentiality");
            parameters.Add("Essentiality", essentiality.Trim().ToLowerInvariant());
        }

        if (!string.IsNullOrWhiteSpace(brand))
        {
            where.Append(" AND te.effective_brand IS NOT NULL AND banking.fold_text(te.effective_brand) = banking.fold_text(@Brand)");
            parameters.Add("Brand", brand.Trim());
        }

        if (!string.IsNullOrWhiteSpace(search))
        {
            where.Append(
                " AND (strpos(banking.fold_text(te.effective_description), banking.fold_text(@Search)) > 0" +
                " OR strpos(banking.fold_text(te.original_description), banking.fold_text(@Search)) > 0)");
            parameters.Add("Search", search.Trim());
        }

        if (!string.IsNullOrWhiteSpace(paymentMethod))
        {
            where.Append(" AND te.effective_payment_method = @PaymentMethod");
            parameters.Add("PaymentMethod", paymentMethod.Trim().ToLowerInvariant());
        }

        if (!string.IsNullOrWhiteSpace(tag))
        {
            where.Append(
                " AND EXISTS (" +
                "SELECT 1 FROM banking.transaction_tag tt " +
                "JOIN banking.tag tg ON tg.id = tt.tag_id " +
                "WHERE tt.transaction_id = te.id " +
                "AND tg.household_id = @HouseholdId " +
                "AND lower(tg.name) = lower(@Tag))");
            parameters.Add("Tag", tag.Trim());
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var totals = await connection.QuerySingleAsync<TransactionTotalsRow>(new CommandDefinition(
            $"""
            SELECT
                COUNT(*)::int AS TotalCount,
                COALESCE(SUM(te.amount_cents), 0)::bigint AS TotalCents
            FROM banking.transaction_effective te
            {where}
            """,
            parameters,
            cancellationToken: cancellationToken));

        var rows = (await connection.QueryAsync<TransactionListRow>(new CommandDefinition(
            $"""
            SELECT
                te.id AS Id,
                te.account_id AS AccountId,
                te.account_name AS AccountName,
                te.account_kind AS AccountKind,
                te.connection_id AS BankId,
                te.institution_name AS InstitutionName,
                te.brand_color AS BrandColor,
                te.occurred_on AS OccurredOn,
                te.purchase_on AS PurchaseOn,
                te.effective_description AS Description,
                te.original_description AS OriginalDescription,
                te.merchant_cnpj AS MerchantCnpj,
                te.amount_cents AS AmountCents,
                te.currency AS Currency,
                te.status AS Status,
                te.effective_kind AS Kind,
                te.effective_category AS Category,
                te.effective_essentiality AS Essentiality,
                te.effective_brand AS Brand,
                te.effective_payment_method AS PaymentMethod,
                te.effective_is_atypical AS IsAtypical,
                te.bill_id AS BillId,
                te.installment_number AS InstallmentNumber,
                te.installment_total AS InstallmentTotal,
                te.has_manual_adjustments AS HasManualAdjustments,
                te.deciding_layer AS DecidingLayer,
                te.deciding_rule_name AS DecidingRuleName,
                te.explanation AS Explanation
            FROM banking.transaction_effective te
            {where}
            ORDER BY te.occurred_on DESC, te.id DESC
            LIMIT @PageSize OFFSET @Offset
            """,
            parameters,
            cancellationToken: cancellationToken))).ToList();

        var tagsByTx = await LoadTagsByTransactionIdsAsync(
            connection,
            rows.Select(r => r.Id).ToArray(),
            cancellationToken);

        var items = rows
            .Select(r => new TransactionListItemDto(
                r.Id,
                r.AccountId,
                r.AccountName,
                r.AccountKind,
                r.BankId,
                r.InstitutionName,
                r.BrandColor,
                r.OccurredOn,
                r.PurchaseOn,
                r.Description,
                r.OriginalDescription,
                r.MerchantCnpj,
                r.AmountCents,
                r.Currency,
                r.Status,
                r.Kind,
                r.Category,
                r.Essentiality,
                r.Brand,
                r.PaymentMethod,
                r.IsAtypical,
                tagsByTx.TryGetValue(r.Id, out var txTags) ? txTags : [],
                r.BillId,
                r.InstallmentNumber,
                r.InstallmentTotal,
                r.HasManualAdjustments,
                r.DecidingLayer,
                r.DecidingRuleName,
                r.Explanation))
            .ToList();

        var hasMore = (long)page * pageSize < totals.TotalCount;

        return new TransactionsPageResponse(
            items,
            totals.TotalCents,
            totals.TotalCount,
            page,
            pageSize,
            hasMore);
    }

    public async Task<TransactionDetailDto?> GetTransactionDetailAsync(
        Guid householdId,
        Guid transactionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        return await LoadTransactionDetailAsync(connection, householdId, transactionId, cancellationToken);
    }

    public async Task<(int StatusCode, string? Error, ApplyAdjustmentsResponse? Data)> ApplyAdjustmentsAsync(
        Guid householdId,
        Guid transactionId,
        ApplyAdjustmentsRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Category is null &&
            request.Essentiality is null &&
            request.Brand is null &&
            request.Kind is null &&
            request.Description is null &&
            request.PaymentMethod is null &&
            request.IsAtypical is null)
        {
            return (400, "Informe ao menos um campo para ajustar.", null);
        }

        string? normalizedCategory = null;
        if (request.Category is not null)
        {
            normalizedCategory = request.Category.Trim().ToLowerInvariant();
            if (!BankingTaxonomy.EditableCategories.Contains(normalizedCategory))
            {
                return (400, "Categoria inválida.", null);
            }
        }

        string? normalizedEssentiality = null;
        if (request.Essentiality is not null)
        {
            normalizedEssentiality = request.Essentiality.Trim().ToLowerInvariant();
            if (!BankingTaxonomy.Essentialities.Contains(normalizedEssentiality))
            {
                return (400, "Essencialidade inválida; use essential, important ou flexible.", null);
            }
        }

        string? normalizedKind = null;
        if (request.Kind is not null)
        {
            normalizedKind = request.Kind.Trim().ToLowerInvariant();
            if (!BankingTaxonomy.TransactionKinds.Contains(normalizedKind))
            {
                return (400, "Tipo de movimento inválido.", null);
            }
        }

        string? normalizedBrand = null;
        if (request.Brand is not null)
        {
            normalizedBrand = request.Brand.Trim();
            if (normalizedBrand.Length == 0)
            {
                return (400, "Marca não pode ser vazia.", null);
            }
        }

        string? normalizedDescription = null;
        if (request.Description is not null)
        {
            normalizedDescription = request.Description.Trim();
            if (normalizedDescription.Length == 0)
            {
                return (400, "Descrição não pode ser vazia.", null);
            }
        }

        string? normalizedPaymentMethod = null;
        if (request.PaymentMethod is not null)
        {
            normalizedPaymentMethod = request.PaymentMethod.Trim().ToLowerInvariant();
            if (!BankingTaxonomy.PaymentMethods.Contains(normalizedPaymentMethod))
            {
                return (400, "Forma de pagamento inválida; use pix, debit, credit, cash, boleto, transfer ou other.", null);
            }
        }

        var reason = string.IsNullOrWhiteSpace(request.Reason) ? null : request.Reason.Trim();

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var current = await LoadTransactionDetailAsync(connection, householdId, transactionId, cancellationToken);
        if (current is null)
        {
            return (404, null, null);
        }

        // Independent fields (RF-24): changing category never alters essentiality and vice versa.
        var toInsert = new List<(string FieldName, string? OldValue, string NewValue)>();

        if (normalizedCategory is not null && !string.Equals(current.Category, normalizedCategory, StringComparison.Ordinal))
        {
            toInsert.Add(("category", current.Category, normalizedCategory));
        }

        if (normalizedEssentiality is not null && !string.Equals(current.Essentiality, normalizedEssentiality, StringComparison.Ordinal))
        {
            toInsert.Add(("essentiality", current.Essentiality, normalizedEssentiality));
        }

        if (normalizedBrand is not null && !string.Equals(current.Brand, normalizedBrand, StringComparison.Ordinal))
        {
            toInsert.Add(("brand", current.Brand, normalizedBrand));
        }

        if (normalizedKind is not null && !string.Equals(current.Kind, normalizedKind, StringComparison.Ordinal))
        {
            toInsert.Add(("kind", current.Kind, normalizedKind));
        }

        if (normalizedDescription is not null && !string.Equals(current.Description, normalizedDescription, StringComparison.Ordinal))
        {
            toInsert.Add(("description", current.Description, normalizedDescription));
        }

        if (normalizedPaymentMethod is not null && !string.Equals(current.PaymentMethod, normalizedPaymentMethod, StringComparison.Ordinal))
        {
            toInsert.Add(("payment_method", current.PaymentMethod, normalizedPaymentMethod));
        }

        if (request.IsAtypical.HasValue && current.IsAtypical != request.IsAtypical.Value)
        {
            toInsert.Add((
                "is_atypical",
                current.IsAtypical ? "true" : "false",
                request.IsAtypical.Value ? "true" : "false"));
        }

        var applied = new List<AdjustmentDto>(toInsert.Count);

        if (toInsert.Count > 0)
        {
            await using var dbTx = await connection.BeginTransactionAsync(cancellationToken);

            foreach (var (fieldName, oldValue, newValue) in toInsert)
            {
                var adjId = Guid.CreateVersion7();
                var createdAt = await connection.ExecuteScalarAsync<DateTimeOffset>(new CommandDefinition(
                    """
                    INSERT INTO banking.adjustment (
                        id,
                        transaction_id,
                        field_name,
                        old_value,
                        new_value,
                        reason,
                        undoes_id
                    )
                    VALUES (
                        @Id,
                        @TransactionId,
                        @FieldName,
                        @OldValue,
                        @NewValue,
                        @Reason,
                        NULL
                    )
                    RETURNING created_at
                    """,
                    new
                    {
                        Id = adjId,
                        TransactionId = transactionId,
                        FieldName = fieldName,
                        OldValue = oldValue,
                        NewValue = newValue,
                        Reason = reason
                    },
                    transaction: dbTx,
                    cancellationToken: cancellationToken));

                applied.Add(new AdjustmentDto(
                    adjId,
                    fieldName,
                    oldValue,
                    newValue,
                    reason,
                    null,
                    createdAt));
            }

            await dbTx.CommitAsync(cancellationToken);
        }

        var updated = (await LoadTransactionDetailAsync(connection, householdId, transactionId, cancellationToken))!;

        var suggestedCnpj = MerchantNormalizer.NormalizeCnpj(updated.Original.MerchantCnpj);
        var suggestedMerchant = MerchantNormalizer.NormalizeDescription(updated.Original.Description);

        var otherCandidates = await connection.QueryAsync<SimilarCandidateRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                original_description AS OriginalDescription,
                merchant_cnpj AS MerchantCnpj
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND id <> @TransactionId
            """,
            new { HouseholdId = householdId, TransactionId = transactionId },
            cancellationToken: cancellationToken));

        var similarCount = 0;
        foreach (var candidate in otherCandidates)
        {
            var cnpjMatches = suggestedCnpj is not null &&
                              string.Equals(
                                  MerchantNormalizer.NormalizeCnpj(candidate.MerchantCnpj),
                                  suggestedCnpj,
                                  StringComparison.Ordinal);

            var merchantMatches = !string.IsNullOrEmpty(suggestedMerchant) &&
                                  string.Equals(
                                      MerchantNormalizer.NormalizeDescription(candidate.OriginalDescription),
                                      suggestedMerchant,
                                      StringComparison.Ordinal);

            if (cnpjMatches || merchantMatches)
            {
                similarCount++;
            }
        }

        return (
            200,
            null,
            new ApplyAdjustmentsResponse(
                updated,
                applied,
                similarCount,
                suggestedCnpj,
                string.IsNullOrEmpty(suggestedMerchant) ? null : suggestedMerchant));
    }

    public async Task<(int StatusCode, string? Error, UndoAdjustmentResponse? Data)> UndoAdjustmentAsync(
        Guid householdId,
        Guid transactionId,
        Guid adjustmentId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var current = await LoadTransactionDetailAsync(connection, householdId, transactionId, cancellationToken);
        if (current is null)
        {
            return (404, null, null);
        }

        var target = current.Adjustments.FirstOrDefault(a => a.Id == adjustmentId);
        if (target is null)
        {
            return (404, null, null);
        }

        if (current.Adjustments.Any(a => a.UndoesId == adjustmentId))
        {
            return (409, "Este ajuste já foi desfeito.", null);
        }

        var currentFieldValue = target.FieldName switch
        {
            "category" => current.Category,
            "essentiality" => current.Essentiality,
            "brand" => current.Brand,
            "kind" => current.Kind,
            "description" => current.Description,
            "payment_method" => current.PaymentMethod,
            "is_atypical" => current.IsAtypical ? "true" : "false",
            _ => null
        };

        var undoId = Guid.CreateVersion7();
        const string undoReason = "Ajuste desfeito";

        var createdAt = await connection.ExecuteScalarAsync<DateTimeOffset>(new CommandDefinition(
            """
            INSERT INTO banking.adjustment (
                id,
                transaction_id,
                field_name,
                old_value,
                new_value,
                reason,
                undoes_id
            )
            VALUES (
                @Id,
                @TransactionId,
                @FieldName,
                @OldValue,
                @NewValue,
                @Reason,
                @UndoesId
            )
            RETURNING created_at
            """,
            new
            {
                Id = undoId,
                TransactionId = transactionId,
                target.FieldName,
                OldValue = currentFieldValue,
                NewValue = target.OldValue,
                Reason = undoReason,
                UndoesId = adjustmentId
            },
            cancellationToken: cancellationToken));

        var undoAdjustment = new AdjustmentDto(
            undoId,
            target.FieldName,
            currentFieldValue,
            target.OldValue,
            undoReason,
            adjustmentId,
            createdAt);

        var updated = (await LoadTransactionDetailAsync(connection, householdId, transactionId, cancellationToken))!;
        return (200, null, new UndoAdjustmentResponse(updated, undoAdjustment));
    }

    public async Task<ReviewQueueResponse> GetReviewQueueAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var rows = (await connection.QueryAsync<ReviewQueueRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                occurred_on AS OccurredOn,
                effective_description AS EffectiveDescription,
                original_description AS OriginalDescription,
                merchant_cnpj AS MerchantCnpj,
                amount_cents AS AmountCents
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND effective_kind IN ('expense', 'refund')
              AND effective_category IS NULL
            ORDER BY occurred_on DESC, id DESC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var groups = rows
            .GroupBy(r => MerchantNormalizer.NormalizeDescription(r.OriginalDescription))
            .Select(g =>
            {
                var ordered = g.OrderByDescending(x => x.OccurredOn).ThenByDescending(x => x.Id).ToList();
                var latest = ordered[0];
                return new ReviewQueueGroupDto(
                    g.Key,
                    latest.EffectiveDescription,
                    ordered.Select(x => x.MerchantCnpj).FirstOrDefault(c => !string.IsNullOrWhiteSpace(c)),
                    ordered.Count,
                    ordered.Sum(x => x.AmountCents),
                    latest.OccurredOn,
                    ordered.Take(10).Select(x => x.Id).ToList());
            })
            .OrderByDescending(g => g.Count)
            .ThenByDescending(g => g.LatestOccurredOn)
            .ThenBy(g => g.MerchantNormalized, StringComparer.Ordinal)
            .ToList();

        return new ReviewQueueResponse(rows.Count, groups);
    }

    public async Task<SpendingRankingResponse> GetSpendingRankingAsync(
        Guid householdId,
        DateOnly? from,
        DateOnly? to,
        Guid? bankId,
        Guid? accountId,
        CancellationToken cancellationToken)
    {
        var (effectiveFrom, effectiveTo, totalCents, items) =
            await QuerySpendingBreakdownAsync(householdId, from, to, bankId, accountId, cancellationToken);

        return new SpendingRankingResponse(effectiveFrom, effectiveTo, totalCents, items);
    }

    public async Task<SpendingDonutResponse> GetSpendingDonutAsync(
        Guid householdId,
        DateOnly? from,
        DateOnly? to,
        Guid? bankId,
        Guid? accountId,
        CancellationToken cancellationToken)
    {
        var (effectiveFrom, effectiveTo, totalCents, items) =
            await QuerySpendingBreakdownAsync(householdId, from, to, bankId, accountId, cancellationToken);

        const int donutLimit = 5;
        var slices = items.Take(donutLimit).ToList();
        var rest = items.Skip(donutLimit).ToList();
        var restCents = rest.Sum(x => x.Cents);
        var restShare = totalCents > 0 ? Math.Round((decimal)restCents / totalCents, 6) : 0m;

        return new SpendingDonutResponse(
            effectiveFrom,
            effectiveTo,
            totalCents,
            slices,
            restCents,
            restShare);
    }

    public async Task<ConnectionsListResponse> GetConnectionsAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = (await connection.QueryAsync<ConnectionListRow>(new CommandDefinition(
            """
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
                consecutive_failures AS ConsecutiveFailures
            FROM banking.connection
            WHERE household_id = @HouseholdId
            ORDER BY created_at ASC, id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var now = DateTimeOffset.UtcNow;
        var items = rows
            .Select(r => new ConnectionDto(
                r.Id,
                r.Provider,
                r.ExternalItemId,
                r.InstitutionName,
                r.BrandColor,
                r.Status,
                r.LastSyncedAt,
                r.ConsentExpiresAt,
                r.ConsentExpiresAt.HasValue && r.ConsentExpiresAt.Value > now && r.ConsentExpiresAt.Value <= now.AddDays(30),
                r.LastErrorCode,
                r.ConsecutiveFailures))
            .ToList();

        return new ConnectionsListResponse(items);
    }

    public async Task<(bool Ok, string? Error, ConnectionDto? Data)> RegisterPluggyConnectionAsync(
        Guid householdId,
        RegisterPluggyConnectionRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.ExternalItemId))
        {
            return (false, "Informe o identificador do item Pluggy (externalItemId).", null);
        }

        var externalItemId = request.ExternalItemId.Trim();
        var institutionName = string.IsNullOrWhiteSpace(request.InstitutionName)
            ? "Instituição conectada"
            : request.InstitutionName.Trim();
        var brandColor = string.IsNullOrWhiteSpace(request.BrandColor)
            ? "#A0521A"
            : request.BrandColor.Trim();

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var row = await connection.QuerySingleAsync<ConnectionListRow>(new CommandDefinition(
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
                'pluggy',
                @ExternalItemId,
                @InstitutionName,
                @BrandColor,
                'up_to_date'
            )
            ON CONFLICT (household_id, provider, external_item_id) DO UPDATE
            SET institution_name = CASE
                    WHEN @HasExplicitName THEN EXCLUDED.institution_name
                    ELSE banking.connection.institution_name
                END,
                updated_at = now()
            RETURNING
                id AS Id,
                provider AS Provider,
                external_item_id AS ExternalItemId,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
                status AS Status,
                last_synced_at AS LastSyncedAt,
                consent_expires_at AS ConsentExpiresAt,
                last_error_code AS LastErrorCode,
                consecutive_failures AS ConsecutiveFailures
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                ExternalItemId = externalItemId,
                InstitutionName = institutionName,
                BrandColor = brandColor,
                HasExplicitName = !string.IsNullOrWhiteSpace(request.InstitutionName)
            },
            cancellationToken: cancellationToken));

        var now = DateTimeOffset.UtcNow;
        var dto = new ConnectionDto(
            row.Id,
            row.Provider,
            row.ExternalItemId,
            row.InstitutionName,
            row.BrandColor,
            row.Status,
            row.LastSyncedAt,
            row.ConsentExpiresAt,
            row.ConsentExpiresAt.HasValue && row.ConsentExpiresAt.Value > now && row.ConsentExpiresAt.Value <= now.AddDays(30),
            row.LastErrorCode,
            row.ConsecutiveFailures);

        return (true, null, dto);
    }

    private async Task<List<BankDetailDto>> LoadBankDetailsInternalAsync(
        Guid householdId,
        Guid? connectionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var connSql = connectionId.HasValue
            ? """
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
                  consecutive_failures AS ConsecutiveFailures
              FROM banking.connection
              WHERE household_id = @HouseholdId
                AND id = @ConnectionId
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
                  consecutive_failures AS ConsecutiveFailures
              FROM banking.connection
              WHERE household_id = @HouseholdId
              ORDER BY created_at ASC, id ASC
              """;

        var connRows = (await connection.QueryAsync<ConnectionListRow>(new CommandDefinition(
            connSql,
            new { HouseholdId = householdId, ConnectionId = connectionId },
            cancellationToken: cancellationToken))).ToList();

        if (connRows.Count == 0)
        {
            return [];
        }

        var accounts = (await connection.QueryAsync<AccountDetailRow>(new CommandDefinition(
            """
            SELECT
                a.id AS Id,
                a.connection_id AS ConnectionId,
                a.name AS Name,
                a.kind AS Kind,
                a.last_four_digits AS LastFourDigits,
                a.currency AS Currency,
                COALESCE(
                    (SELECT bs.balance_cents
                     FROM banking.balance_snapshot bs
                     WHERE bs.account_id = a.id
                     ORDER BY bs.captured_at DESC, bs.id DESC
                     LIMIT 1),
                    a.opening_balance_cents
                ) AS BalanceCents
            FROM banking.account a
            WHERE a.household_id = @HouseholdId
            ORDER BY a.created_at ASC, a.id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var bills = (await connection.QueryAsync<BillWithAccountRow>(new CommandDefinition(
            """
            SELECT
                cb.id AS Id,
                cb.account_id AS AccountId,
                cb.period_month AS PeriodMonth,
                cb.closing_on AS ClosingOn,
                cb.due_on AS DueOn,
                cb.total_cents AS TotalCents,
                cb.is_open AS IsOpen
            FROM banking.card_bill cb
            JOIN banking.account a ON a.id = cb.account_id
            WHERE a.household_id = @HouseholdId
            ORDER BY cb.period_month DESC, cb.due_on DESC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        var billsByAccount = bills
            .GroupBy(b => b.AccountId)
            .ToDictionary(
                g => g.Key,
                g => (IReadOnlyList<CardBillSummaryDto>)g
                    .Select(b => new CardBillSummaryDto(
                        b.Id,
                        b.PeriodMonth,
                        b.ClosingOn,
                        b.DueOn,
                        b.TotalCents,
                        b.IsOpen))
                    .ToList());

        var accountsByConnection = accounts
            .GroupBy(a => a.ConnectionId)
            .ToDictionary(g => g.Key, g => g.ToList());

        var now = DateTimeOffset.UtcNow;
        var result = new List<BankDetailDto>(connRows.Count);

        foreach (var conn in connRows)
        {
            var connAccounts = accountsByConnection.GetValueOrDefault(conn.Id) ?? [];
            long bankBalance = 0;
            long bankCardBill = 0;

            var accountDtos = new List<BankAccountDto>(connAccounts.Count);
            foreach (var acc in connAccounts)
            {
                var accBills = billsByAccount.GetValueOrDefault(acc.Id) ?? [];
                if (acc.Kind == "credit_card")
                {
                    var openBillsTotal = accBills.Where(b => b.IsOpen).Sum(b => b.TotalCents);
                    bankCardBill += openBillsTotal > 0 ? openBillsTotal : Math.Max(0, -acc.BalanceCents);
                }
                else
                {
                    bankBalance += acc.BalanceCents;
                }

                accountDtos.Add(new BankAccountDto(
                    acc.Id,
                    acc.Name,
                    acc.Kind,
                    acc.LastFourDigits,
                    acc.Currency,
                    acc.BalanceCents,
                    accBills));
            }

            var expiringSoon = conn.ConsentExpiresAt.HasValue &&
                               conn.ConsentExpiresAt.Value > now &&
                               conn.ConsentExpiresAt.Value <= now.AddDays(30);

            result.Add(new BankDetailDto(
                conn.Id,
                conn.Provider,
                conn.InstitutionName,
                conn.BrandColor,
                conn.Status,
                conn.LastSyncedAt,
                conn.ConsentExpiresAt,
                expiringSoon,
                bankBalance,
                bankCardBill,
                accountDtos));
        }

        return result;
    }

    private async Task<(DateOnly? From, DateOnly? To, long TotalCents, List<SpendingCategoryDto> Items)> QuerySpendingBreakdownAsync(
        Guid householdId,
        DateOnly? from,
        DateOnly? to,
        Guid? bankId,
        Guid? accountId,
        CancellationToken cancellationToken)
    {
        if (!from.HasValue && !to.HasValue)
        {
            var today = DateParser.TodayInTimeZone(_instanceTimeZone);
            from = new DateOnly(today.Year, today.Month, 1);
            to = new DateOnly(today.Year, today.Month, DateTime.DaysInMonth(today.Year, today.Month));
        }

        var where = new StringBuilder(
            "WHERE household_id = @HouseholdId AND effective_kind IN ('expense', 'refund')");
        var parameters = new DynamicParameters();
        parameters.Add("HouseholdId", householdId);

        if (from.HasValue)
        {
            where.Append(" AND occurred_on >= @From");
            parameters.Add("From", from.Value);
        }

        if (to.HasValue)
        {
            where.Append(" AND occurred_on <= @To");
            parameters.Add("To", to.Value);
        }

        if (bankId.HasValue)
        {
            where.Append(" AND connection_id = @BankId");
            parameters.Add("BankId", bankId.Value);
        }

        if (accountId.HasValue)
        {
            where.Append(" AND account_id = @AccountId");
            parameters.Add("AccountId", accountId.Value);
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = (await connection.QueryAsync<SpendingCategoryRow>(new CommandDefinition(
            $"""
            WITH filtered AS (
                SELECT
                    id,
                    amount_cents,
                    effective_category
                FROM banking.transaction_effective
                {where}
            ),
            expanded AS (
                SELECT
                    COALESCE(s.category, f.effective_category, 'uncategorized') AS category,
                    s.amount_cents
                FROM filtered f
                JOIN banking.transaction_split s ON s.transaction_id = f.id
                UNION ALL
                SELECT
                    COALESCE(f.effective_category, 'uncategorized') AS category,
                    f.amount_cents
                FROM filtered f
                WHERE NOT EXISTS (
                    SELECT 1 FROM banking.transaction_split s WHERE s.transaction_id = f.id
                )
            )
            SELECT
                category AS Category,
                COALESCE(-SUM(amount_cents), 0)::bigint AS Cents
            FROM expanded
            GROUP BY category
            HAVING COALESCE(-SUM(amount_cents), 0) > 0
            ORDER BY Cents DESC, Category ASC
            """,
            parameters,
            cancellationToken: cancellationToken))).ToList();

        var totalCents = rows.Sum(r => r.Cents);
        var items = rows
            .Select(r => new SpendingCategoryDto(
                r.Category,
                BankingTaxonomy.GetCategoryLabel(r.Category),
                r.Cents,
                totalCents > 0 ? Math.Round((decimal)r.Cents / totalCents, 6) : 0m))
            .ToList();

        return (from, to, totalCents, items);
    }

    internal static async Task<Dictionary<Guid, IReadOnlyList<string>>> LoadTagsByTransactionIdsAsync(
        NpgsqlConnection connection,
        Guid[] transactionIds,
        CancellationToken cancellationToken,
        NpgsqlTransaction? transaction = null)
    {
        if (transactionIds.Length == 0)
        {
            return [];
        }

        var rows = await connection.QueryAsync<TransactionTagNameRow>(new CommandDefinition(
            """
            SELECT
                tt.transaction_id AS TransactionId,
                tg.name AS Name
            FROM banking.transaction_tag tt
            JOIN banking.tag tg ON tg.id = tt.tag_id
            WHERE tt.transaction_id = ANY(@TransactionIds)
            ORDER BY lower(tg.name) ASC, tg.id ASC
            """,
            new { TransactionIds = transactionIds },
            transaction: transaction,
            cancellationToken: cancellationToken));

        return rows
            .GroupBy(r => r.TransactionId)
            .ToDictionary(
                g => g.Key,
                g => (IReadOnlyList<string>)g.Select(x => x.Name).ToList());
    }

    internal static async Task<TransactionDetailDto?> LoadTransactionDetailAsync(
        NpgsqlConnection connection,
        Guid householdId,
        Guid transactionId,
        CancellationToken cancellationToken)
    {
        var row = await connection.QuerySingleOrDefaultAsync<TransactionDetailRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                account_id AS AccountId,
                account_name AS AccountName,
                account_kind AS AccountKind,
                connection_id AS BankId,
                institution_name AS InstitutionName,
                brand_color AS BrandColor,
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
            WHERE id = @TransactionId
              AND household_id = @HouseholdId
            """,
            new { TransactionId = transactionId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (row is null)
        {
            return null;
        }

        var adjustments = (await connection.QueryAsync<AdjustmentDto>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                field_name AS FieldName,
                old_value AS OldValue,
                new_value AS NewValue,
                reason AS Reason,
                undoes_id AS UndoesId,
                created_at AS CreatedAt
            FROM banking.adjustment
            WHERE transaction_id = @TransactionId
            ORDER BY created_at ASC, id ASC
            """,
            new { TransactionId = transactionId },
            cancellationToken: cancellationToken))).ToList();

        var tags = (await connection.QueryAsync<string>(new CommandDefinition(
            """
            SELECT tg.name
            FROM banking.transaction_tag tt
            JOIN banking.tag tg ON tg.id = tt.tag_id
            WHERE tt.transaction_id = @TransactionId
            ORDER BY lower(tg.name) ASC, tg.id ASC
            """,
            new { TransactionId = transactionId },
            cancellationToken: cancellationToken))).ToList();

        var splits = (await connection.QueryAsync<TransactionSplitDto>(new CommandDefinition(
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

        return new TransactionDetailDto(
            row.Id,
            row.AccountId,
            row.AccountName,
            row.AccountKind,
            row.BankId,
            row.InstitutionName,
            row.BrandColor,
            row.OccurredOn,
            row.PurchaseOn,
            row.AmountCents,
            row.Currency,
            row.Status,
            row.BillId,
            row.InstallmentNumber,
            row.InstallmentTotal,
            row.EffectiveDescription,
            row.EffectiveKind,
            row.EffectiveCategory,
            row.EffectiveEssentiality,
            row.EffectiveBrand,
            row.EffectivePaymentMethod,
            row.EffectiveIsAtypical,
            tags,
            splits,
            new TransactionEffectiveFieldsDto(
                row.EffectiveDescription,
                row.EffectiveKind,
                row.EffectiveCategory,
                row.EffectiveEssentiality,
                row.EffectiveBrand,
                row.EffectivePaymentMethod,
                row.EffectiveIsAtypical),
            new TransactionOriginalFieldsDto(
                row.OriginalDescription,
                row.MerchantCnpj,
                row.OccurredOn,
                row.PurchaseOn,
                row.AmountCents,
                row.VersionNumber,
                row.OriginalPaymentMethod),
            new TransactionClassificationDto(
                row.ClassifiedKind,
                row.ClassifiedCategory,
                row.ClassifiedEssentiality,
                row.ClassifiedBrand,
                row.DecidingLayer,
                row.DecidingRuleId,
                row.DecidingRuleName,
                row.Explanation),
            row.HasManualAdjustments,
            adjustments);
    }

    private sealed record ConnectionSummaryRow(
        Guid Id,
        string InstitutionName,
        string BrandColor,
        string Status,
        DateTimeOffset? LastSyncedAt,
        DateTimeOffset? ConsentExpiresAt);

    private sealed record AccountBalanceRow(
        Guid Id,
        Guid ConnectionId,
        string Kind,
        long BalanceCents,
        long OpenBillCents);

    private sealed record BankMonthlyFlowRow(
        Guid ConnectionId,
        long SpentCents,
        long ReceivedCents);

    private sealed record ConnectionListRow(
        Guid Id,
        string Provider,
        string ExternalItemId,
        string InstitutionName,
        string BrandColor,
        string Status,
        DateTimeOffset? LastSyncedAt,
        DateTimeOffset? ConsentExpiresAt,
        string? LastErrorCode,
        int ConsecutiveFailures);

    private sealed record AccountDetailRow(
        Guid Id,
        Guid ConnectionId,
        string Name,
        string Kind,
        string? LastFourDigits,
        string Currency,
        long BalanceCents);

    private sealed record BillWithAccountRow(
        Guid Id,
        Guid AccountId,
        DateOnly PeriodMonth,
        DateOnly ClosingOn,
        DateOnly DueOn,
        long TotalCents,
        bool IsOpen);

    private sealed record CardAccountHeaderRow(
        Guid AccountId,
        string AccountName,
        string? LastFourDigits,
        string InstitutionName);

    private sealed record CardBillHeaderRow(
        Guid Id,
        Guid AccountId,
        string AccountName,
        string? LastFourDigits,
        string InstitutionName,
        DateOnly PeriodMonth,
        DateOnly ClosingOn,
        DateOnly DueOn,
        long TotalCents,
        bool IsOpen);

    private sealed record TransactionTotalsRow(int TotalCount, long TotalCents);

    private sealed record TransactionTagNameRow(Guid TransactionId, string Name);

    private sealed record TransactionListRow(
        Guid Id,
        Guid AccountId,
        string AccountName,
        string AccountKind,
        Guid BankId,
        string InstitutionName,
        string BrandColor,
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
        string Explanation);

    private sealed record TransactionDetailRow(
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
        string OriginalDescription,
        string? MerchantCnpj,
        long AmountCents,
        string Currency,
        string Status,
        Guid? BillId,
        int? InstallmentNumber,
        int? InstallmentTotal,
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

    private sealed record SimilarCandidateRow(
        Guid Id,
        string OriginalDescription,
        string? MerchantCnpj);

    private sealed record ReviewQueueRow(
        Guid Id,
        DateOnly OccurredOn,
        string EffectiveDescription,
        string OriginalDescription,
        string? MerchantCnpj,
        long AmountCents);

    private sealed record SpendingCategoryRow(string Category, long Cents);
}

internal sealed record BankSummaryDto(
    Guid Id,
    string InstitutionName,
    string BrandColor,
    string Status,
    DateTimeOffset? LastSyncedAt,
    DateTimeOffset? ConsentExpiresAt,
    long BalanceCents,
    long CardBillCents,
    long SpentCents,
    long ReceivedCents,
    int AccountCount);

internal sealed record SummaryResponse(
    string Month,
    long BalanceCents,
    long SpentCents,
    long ReceivedCents,
    long LeftoverCents,
    long CardBillCents,
    bool HasConnections,
    IReadOnlyList<BankSummaryDto> Banks);

internal sealed record CardBillSummaryDto(
    Guid Id,
    DateOnly PeriodMonth,
    DateOnly ClosingOn,
    DateOnly DueOn,
    long TotalCents,
    bool IsOpen);

internal sealed record BankAccountDto(
    Guid Id,
    string Name,
    string Kind,
    string? LastFourDigits,
    string Currency,
    long BalanceCents,
    IReadOnlyList<CardBillSummaryDto> Bills);

internal sealed record BankDetailDto(
    Guid Id,
    string Provider,
    string InstitutionName,
    string BrandColor,
    string Status,
    DateTimeOffset? LastSyncedAt,
    DateTimeOffset? ConsentExpiresAt,
    bool ExpiringSoon,
    long BalanceCents,
    long CardBillCents,
    IReadOnlyList<BankAccountDto> Accounts);

internal sealed record BanksListResponse(IReadOnlyList<BankDetailDto> Items);

internal sealed record CardBillsListResponse(
    Guid AccountId,
    string AccountName,
    string? LastFourDigits,
    string InstitutionName,
    IReadOnlyList<CardBillSummaryDto> Items);

internal sealed record CardBillPurchaseDto(
    Guid Id,
    DateOnly OccurredOn,
    DateOnly? PurchaseOn,
    string Description,
    string OriginalDescription,
    long AmountCents,
    string Kind,
    string? Category,
    string? Essentiality,
    string? Brand,
    int? InstallmentNumber,
    int? InstallmentTotal,
    string Status,
    bool HasManualAdjustments);

internal sealed record CardBillDetailResponse(
    Guid Id,
    Guid AccountId,
    string AccountName,
    string? LastFourDigits,
    string InstitutionName,
    DateOnly PeriodMonth,
    DateOnly ClosingOn,
    DateOnly DueOn,
    long TotalCents,
    bool IsOpen,
    IReadOnlyList<CardBillPurchaseDto> Purchases);

internal sealed record TransactionListItemDto(
    Guid Id,
    Guid AccountId,
    string AccountName,
    string AccountKind,
    Guid BankId,
    string InstitutionName,
    string BrandColor,
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
    IReadOnlyList<string> Tags,
    Guid? BillId,
    int? InstallmentNumber,
    int? InstallmentTotal,
    bool HasManualAdjustments,
    string DecidingLayer,
    string? DecidingRuleName,
    string Explanation);

internal sealed record TransactionsPageResponse(
    IReadOnlyList<TransactionListItemDto> Items,
    long TotalCents,
    int TotalCount,
    int Page,
    int PageSize,
    bool HasMore);

internal sealed record TransactionEffectiveFieldsDto(
    string Description,
    string Kind,
    string? Category,
    string? Essentiality,
    string? Brand,
    string? PaymentMethod,
    bool IsAtypical);

internal sealed record TransactionOriginalFieldsDto(
    string Description,
    string? MerchantCnpj,
    DateOnly OccurredOn,
    DateOnly? PurchaseOn,
    long AmountCents,
    int VersionNumber,
    string? PaymentMethod);

internal sealed record TransactionClassificationDto(
    string? Kind,
    string? Category,
    string? Essentiality,
    string? Brand,
    string DecidingLayer,
    Guid? DecidingRuleId,
    string? DecidingRuleName,
    string Explanation);

internal sealed record AdjustmentDto(
    Guid Id,
    string FieldName,
    string? OldValue,
    string? NewValue,
    string? Reason,
    Guid? UndoesId,
    DateTimeOffset CreatedAt);

internal sealed record TransactionSplitDto(
    Guid Id,
    int PartIndex,
    string Description,
    long AmountCents,
    string? Category,
    string? Essentiality,
    DateTimeOffset CreatedAt);

internal sealed record TransactionDetailDto(
    Guid Id,
    Guid AccountId,
    string AccountName,
    string AccountKind,
    Guid BankId,
    string InstitutionName,
    string BrandColor,
    DateOnly OccurredOn,
    DateOnly? PurchaseOn,
    long AmountCents,
    string Currency,
    string Status,
    Guid? BillId,
    int? InstallmentNumber,
    int? InstallmentTotal,
    string Description,
    string Kind,
    string? Category,
    string? Essentiality,
    string? Brand,
    string? PaymentMethod,
    bool IsAtypical,
    IReadOnlyList<string> Tags,
    IReadOnlyList<TransactionSplitDto> Splits,
    TransactionEffectiveFieldsDto Effective,
    TransactionOriginalFieldsDto Original,
    TransactionClassificationDto Classification,
    bool HasManualAdjustments,
    IReadOnlyList<AdjustmentDto> Adjustments);

internal sealed record ApplyAdjustmentsRequest(
    string? Category = null,
    string? Essentiality = null,
    string? Brand = null,
    string? Kind = null,
    string? Description = null,
    string? Reason = null,
    string? PaymentMethod = null,
    bool? IsAtypical = null);

internal sealed record ApplyAdjustmentsResponse(
    TransactionDetailDto Transaction,
    IReadOnlyList<AdjustmentDto> AppliedAdjustments,
    int SimilarCount,
    string? SuggestedMatchCnpj,
    string? SuggestedMerchantNormalized);

internal sealed record UndoAdjustmentResponse(
    TransactionDetailDto Transaction,
    AdjustmentDto Adjustment);

internal sealed record ReviewQueueGroupDto(
    string MerchantNormalized,
    string DisplayName,
    string? MerchantCnpj,
    int Count,
    long TotalCents,
    DateOnly LatestOccurredOn,
    IReadOnlyList<Guid> SampleTransactionIds);

internal sealed record ReviewQueueResponse(
    int TotalTransactions,
    IReadOnlyList<ReviewQueueGroupDto> Groups);

internal sealed record SpendingCategoryDto(
    string Category,
    string Label,
    long Cents,
    decimal Share);

internal sealed record SpendingRankingResponse(
    DateOnly? From,
    DateOnly? To,
    long TotalCents,
    IReadOnlyList<SpendingCategoryDto> Items);

internal sealed record SpendingDonutResponse(
    DateOnly? From,
    DateOnly? To,
    long TotalCents,
    IReadOnlyList<SpendingCategoryDto> Slices,
    long RestCents,
    decimal RestShare);

internal sealed record ConnectionDto(
    Guid Id,
    string Provider,
    string ExternalItemId,
    string InstitutionName,
    string BrandColor,
    string Status,
    DateTimeOffset? LastSyncedAt,
    DateTimeOffset? ConsentExpiresAt,
    bool ExpiringSoon,
    string? LastErrorCode,
    int ConsecutiveFailures);

internal sealed record ConnectionsListResponse(IReadOnlyList<ConnectionDto> Items);

internal sealed record RegisterPluggyConnectionRequest(
    string? ExternalItemId,
    string? InstitutionName,
    string? BrandColor);

internal sealed record SyncResponse(
    int ConnectionsProcessed,
    int AccountsSynced,
    int TransactionsInserted,
    int TransactionsVersioned,
    int TransactionsRemoved,
    int TransfersLinked,
    int FailedConnections,
    string Message);
