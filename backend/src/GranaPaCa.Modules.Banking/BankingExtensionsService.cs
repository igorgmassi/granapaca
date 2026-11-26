using Dapper;
using GranaPaCa.Modules.Categorization.Contracts;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class BankingExtensionsService(
    NpgsqlDataSource dataSource,
    ICategorizationEngine categorizationEngine,
    IConfiguration configuration)
{
    private const int MaxTagNameLength = 60;
    private const int MaxBulkTransactionCount = 500;
    private const string CashExternalItemId = "cash:household";
    private const string CashExternalAccountId = "cash:wallet";
    private const string CashBrandColor = "#2D6A4F";

    private readonly TimeZoneInfo _instanceTimeZone = DateParser.ResolveInstanceTimeZone(configuration);

    public async Task<(int StatusCode, string? Error, TransactionDetailDto? Data)> CreateCashTransactionAsync(
        Guid householdId,
        CreateCashTransactionRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return (400, "Corpo da requisição inválido.", null);
        }

        if (string.IsNullOrWhiteSpace(request.Description))
        {
            return (400, "Informe a descrição do lançamento em dinheiro.", null);
        }

        if (!request.AmountCents.HasValue || request.AmountCents.Value == 0 || request.AmountCents.Value == long.MinValue)
        {
            return (400, "Informe um valor em centavos diferente de zero.", null);
        }

        var description = request.Description.Trim();
        var occurredOn = request.OccurredOn ?? DateParser.TodayInTimeZone(_instanceTimeZone);

        var normalizedKind = string.IsNullOrWhiteSpace(request.Kind)
            ? "expense"
            : request.Kind.Trim().ToLowerInvariant();
        if (!BankingTaxonomy.TransactionKinds.Contains(normalizedKind))
        {
            return (400, "Tipo de movimento inválido.", null);
        }

        var rawAmount = request.AmountCents.Value;
        var signedAmountCents = normalizedKind switch
        {
            "expense" or "withdrawal" or "investment" or "card_payment" => -Math.Abs(rawAmount),
            "income" or "refund" or "redemption" => Math.Abs(rawAmount),
            _ => rawAmount
        };

        string? normalizedCategory = null;
        if (request.Category is not null)
        {
            normalizedCategory = request.Category.Trim().ToLowerInvariant();
            if (normalizedCategory.Length == 0)
            {
                normalizedCategory = null;
            }
            else if (!BankingTaxonomy.EditableCategories.Contains(normalizedCategory))
            {
                return (400, "Categoria inválida.", null);
            }
        }

        string? normalizedEssentiality = null;
        if (request.Essentiality is not null)
        {
            normalizedEssentiality = request.Essentiality.Trim().ToLowerInvariant();
            if (normalizedEssentiality.Length == 0)
            {
                normalizedEssentiality = null;
            }
            else if (!BankingTaxonomy.Essentialities.Contains(normalizedEssentiality))
            {
                return (400, "Essencialidade inválida; use essential, important ou flexible.", null);
            }
        }

        var (tagsOk, tagsError, normalizedTags) = NormalizeTagNames(request.Tags);
        if (!tagsOk)
        {
            return (400, tagsError, null);
        }

        var hasClientMutationId = !string.IsNullOrWhiteSpace(request.ClientMutationId);
        var externalId = hasClientMutationId
            ? request.ClientMutationId!.Trim()
            : $"cash:{Guid.CreateVersion7():D}";

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var accountId = await EnsureCashAccountAsync(connection, householdId, cancellationToken);

        if (hasClientMutationId)
        {
            var existingTxId = await connection.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
                """
                SELECT transaction_id
                FROM banking.transaction_source
                WHERE account_id = @AccountId
                  AND source = 'cash'
                  AND external_id = @ExternalId
                """,
                new { AccountId = accountId, ExternalId = externalId },
                cancellationToken: cancellationToken));

            if (existingTxId.HasValue)
            {
                var existingDetail = await BankingQueries.LoadTransactionDetailAsync(
                    connection,
                    householdId,
                    existingTxId.Value,
                    cancellationToken);
                return (200, null, existingDetail);
            }
        }

        var autoClassified = await categorizationEngine.ClassifyAsync(
            new CategorizationInput(householdId, description, null, signedAmountCents, normalizedKind),
            cancellationToken);

        var hasExplicitClassification = normalizedCategory is not null || normalizedEssentiality is not null;
        var finalCategory = normalizedCategory ?? autoClassified.Category;
        var finalEssentiality = normalizedEssentiality ?? autoClassified.Essentiality;
        var finalBrand = autoClassified.Brand;
        var decidingLayer = hasExplicitClassification ? "manual" : autoClassified.DecidingLayer;
        Guid? decidingRuleId = hasExplicitClassification ? null : autoClassified.DecidingRuleId;
        string? decidingRuleName = hasExplicitClassification ? null : autoClassified.DecidingRuleName;
        var explanation = hasExplicitClassification
            ? "Classificação informada no lançamento em dinheiro."
            : autoClassified.Explanation;

        var txId = Guid.CreateVersion7();
        var versionId = Guid.CreateVersion7();
        var contentHash = ContentHashCalculator.ComputeTransactionHash(
            occurredOn,
            occurredOn,
            description,
            null,
            signedAmountCents,
            "BRL",
            "posted",
            null,
            null,
            null,
            isRemoved: false);

        await using var dbTx = await connection.BeginTransactionAsync(cancellationToken);
        try
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.transaction (id, household_id, account_id)
                VALUES (@Id, @HouseholdId, @AccountId)
                """,
                new { Id = txId, HouseholdId = householdId, AccountId = accountId },
                transaction: dbTx,
                cancellationToken: cancellationToken));

            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.transaction_source (id, transaction_id, account_id, source, external_id)
                VALUES (@Id, @TransactionId, @AccountId, 'cash', @ExternalId)
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    TransactionId = txId,
                    AccountId = accountId,
                    ExternalId = externalId
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));

            await connection.ExecuteAsync(new CommandDefinition(
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
                    raw_payload_enc,
                    payment_method,
                    is_atypical
                )
                VALUES (
                    @Id,
                    @TransactionId,
                    1,
                    @ContentHash,
                    @OccurredOn,
                    @PurchaseOn,
                    @Description,
                    NULL,
                    @AmountCents,
                    'BRL',
                    'posted',
                    NULL,
                    NULL,
                    NULL,
                    false,
                    NULL,
                    'cash',
                    false
                )
                """,
                new
                {
                    Id = versionId,
                    TransactionId = txId,
                    ContentHash = contentHash,
                    OccurredOn = occurredOn,
                    PurchaseOn = occurredOn,
                    Description = description,
                    AmountCents = signedAmountCents
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));

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
                """,
                new
                {
                    TransactionId = txId,
                    TxKind = normalizedKind,
                    Category = finalCategory,
                    Essentiality = finalEssentiality,
                    Brand = finalBrand,
                    DecidingLayer = decidingLayer,
                    DecidingRuleId = decidingRuleId,
                    DecidingRuleName = decidingRuleName,
                    Explanation = explanation
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));

            if (normalizedTags.Count > 0)
            {
                await LinkTagsInTransactionAsync(
                    connection,
                    dbTx,
                    householdId,
                    txId,
                    normalizedTags,
                    replaceExisting: false,
                    cancellationToken);
            }

            await dbTx.CommitAsync(cancellationToken);
        }
        catch (PostgresException ex) when (hasClientMutationId && ex.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            await dbTx.RollbackAsync(cancellationToken);

            var existingTxId = await connection.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
                """
                SELECT transaction_id
                FROM banking.transaction_source
                WHERE account_id = @AccountId
                  AND source = 'cash'
                  AND external_id = @ExternalId
                """,
                new { AccountId = accountId, ExternalId = externalId },
                cancellationToken: cancellationToken));

            if (existingTxId.HasValue)
            {
                var existingDetail = await BankingQueries.LoadTransactionDetailAsync(
                    connection,
                    householdId,
                    existingTxId.Value,
                    cancellationToken);
                return (200, null, existingDetail);
            }

            throw;
        }

        var detail = await BankingQueries.LoadTransactionDetailAsync(connection, householdId, txId, cancellationToken);
        return (201, null, detail);
    }

    public async Task<TagsListResponse> GetTagsAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var items = (await connection.QueryAsync<TagDto>(new CommandDefinition(
            """
            SELECT
                tg.id AS Id,
                tg.name AS Name,
                tg.color AS Color,
                COUNT(te.id)::int AS TransactionCount,
                tg.created_at AS CreatedAt
            FROM banking.tag tg
            LEFT JOIN banking.transaction_tag tt ON tt.tag_id = tg.id
            LEFT JOIN banking.transaction_effective te
                ON te.id = tt.transaction_id
               AND te.household_id = @HouseholdId
            WHERE tg.household_id = @HouseholdId
            GROUP BY tg.id, tg.name, tg.color, tg.created_at
            ORDER BY lower(tg.name) ASC, tg.id ASC
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToList();

        return new TagsListResponse(items);
    }

    public async Task<(int StatusCode, string? Error, TagDto? Data)> CreateTagAsync(
        Guid householdId,
        CreateTagRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.Name))
        {
            return (400, "Informe o nome da tag.", null);
        }

        var name = request.Name.Trim();
        if (name.Length > MaxTagNameLength)
        {
            return (400, $"O nome da tag deve ter no máximo {MaxTagNameLength} caracteres.", null);
        }

        var color = "#A0521A";
        if (!string.IsNullOrWhiteSpace(request.Color))
        {
            if (!BankingTaxonomy.IsValidHexColor(request.Color))
            {
                return (400, "Cor inválida; use o formato hexadecimal #RRGGBB.", null);
            }

            color = request.Color.Trim().ToUpperInvariant();
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        try
        {
            var created = await connection.QuerySingleAsync<TagCreatedRow>(new CommandDefinition(
                """
                INSERT INTO banking.tag (id, household_id, name, color)
                VALUES (@Id, @HouseholdId, @Name, @Color)
                RETURNING
                    id AS Id,
                    name AS Name,
                    color AS Color,
                    created_at AS CreatedAt
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    HouseholdId = householdId,
                    Name = name,
                    Color = color
                },
                cancellationToken: cancellationToken));

            return (201, null, new TagDto(created.Id, created.Name, created.Color, 0, created.CreatedAt));
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return (409, "Já existe uma tag com este nome.", null);
        }
    }

    public async Task<bool> DeleteTagAsync(
        Guid householdId,
        Guid tagId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var deleted = await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.tag
            WHERE id = @TagId
              AND household_id = @HouseholdId
            """,
            new { TagId = tagId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        return deleted > 0;
    }

    public async Task<(int StatusCode, string? Error, TransactionTagsResponse? Data)> ReplaceTransactionTagsAsync(
        Guid householdId,
        Guid transactionId,
        ReplaceTransactionTagsRequest? request,
        CancellationToken cancellationToken)
    {
        if (request?.Tags is null)
        {
            return (400, "Informe a lista de tags da transação.", null);
        }

        var (tagsOk, tagsError, normalizedTags) = NormalizeTagNames(request.Tags);
        if (!tagsOk)
        {
            return (400, tagsError, null);
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var exists = await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
            """
            SELECT EXISTS (
                SELECT 1
                FROM banking.transaction_effective
                WHERE id = @TransactionId
                  AND household_id = @HouseholdId
            )
            """,
            new { TransactionId = transactionId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (!exists)
        {
            return (404, null, null);
        }

        await using var dbTx = await connection.BeginTransactionAsync(cancellationToken);

        await LinkTagsInTransactionAsync(
            connection,
            dbTx,
            householdId,
            transactionId,
            normalizedTags,
            replaceExisting: true,
            cancellationToken);

        var assignedTags = (await connection.QueryAsync<TagCreatedRow>(new CommandDefinition(
            """
            SELECT
                tg.id AS Id,
                tg.name AS Name,
                tg.color AS Color,
                tg.created_at AS CreatedAt
            FROM banking.transaction_tag tt
            JOIN banking.tag tg ON tg.id = tt.tag_id
            WHERE tt.transaction_id = @TransactionId
            ORDER BY lower(tg.name) ASC, tg.id ASC
            """,
            new { TransactionId = transactionId },
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        await dbTx.CommitAsync(cancellationToken);

        var names = assignedTags.Select(t => t.Name).ToList();
        var tagItems = assignedTags
            .Select(t => new TagReferenceDto(t.Id, t.Name, t.Color))
            .ToList();

        return (200, null, new TransactionTagsResponse(transactionId, names, tagItems));
    }

    public async Task<(int StatusCode, string? Error, BulkAdjustmentsResponse? Data)> ApplyBulkAdjustmentsAsync(
        Guid householdId,
        BulkAdjustmentsRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null || request.TransactionIds is null || request.TransactionIds.Count == 0)
        {
            return (400, "Informe ao menos uma transação para ajustar.", null);
        }

        var distinctIds = request.TransactionIds.Distinct().ToArray();
        if (distinctIds.Length > MaxBulkTransactionCount)
        {
            return (400, $"É possível ajustar no máximo {MaxBulkTransactionCount} transações por vez.", null);
        }

        if (request.Category is null &&
            request.Essentiality is null &&
            request.Brand is null &&
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

        string? normalizedBrand = null;
        if (request.Brand is not null)
        {
            normalizedBrand = request.Brand.Trim();
            if (normalizedBrand.Length == 0)
            {
                return (400, "Marca não pode ser vazia.", null);
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
        await using var dbTx = await connection.BeginTransactionAsync(cancellationToken);

        var targets = (await connection.QueryAsync<BulkTargetRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                effective_category AS EffectiveCategory,
                effective_essentiality AS EffectiveEssentiality,
                effective_brand AS EffectiveBrand,
                effective_payment_method AS EffectivePaymentMethod,
                effective_is_atypical AS EffectiveIsAtypical
            FROM banking.transaction_effective
            WHERE household_id = @HouseholdId
              AND id = ANY(@TransactionIds)
            """,
            new { HouseholdId = householdId, TransactionIds = distinctIds },
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        var updatedCount = 0;
        var adjustmentsInserted = 0;

        foreach (var target in targets)
        {
            var changes = new List<(string FieldName, string? OldValue, string NewValue)>();

            if (normalizedCategory is not null &&
                !string.Equals(target.EffectiveCategory, normalizedCategory, StringComparison.Ordinal))
            {
                changes.Add(("category", target.EffectiveCategory, normalizedCategory));
            }

            if (normalizedEssentiality is not null &&
                !string.Equals(target.EffectiveEssentiality, normalizedEssentiality, StringComparison.Ordinal))
            {
                changes.Add(("essentiality", target.EffectiveEssentiality, normalizedEssentiality));
            }

            if (normalizedBrand is not null &&
                !string.Equals(target.EffectiveBrand, normalizedBrand, StringComparison.Ordinal))
            {
                changes.Add(("brand", target.EffectiveBrand, normalizedBrand));
            }

            if (normalizedPaymentMethod is not null &&
                !string.Equals(target.EffectivePaymentMethod, normalizedPaymentMethod, StringComparison.Ordinal))
            {
                changes.Add(("payment_method", target.EffectivePaymentMethod, normalizedPaymentMethod));
            }

            if (request.IsAtypical.HasValue && target.EffectiveIsAtypical != request.IsAtypical.Value)
            {
                changes.Add((
                    "is_atypical",
                    target.EffectiveIsAtypical ? "true" : "false",
                    request.IsAtypical.Value ? "true" : "false"));
            }

            if (changes.Count == 0)
            {
                continue;
            }

            foreach (var (fieldName, oldValue, newValue) in changes)
            {
                await connection.ExecuteAsync(new CommandDefinition(
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
                    """,
                    new
                    {
                        Id = Guid.CreateVersion7(),
                        TransactionId = target.Id,
                        FieldName = fieldName,
                        OldValue = oldValue,
                        NewValue = newValue,
                        Reason = reason
                    },
                    transaction: dbTx,
                    cancellationToken: cancellationToken));

                adjustmentsInserted++;
            }

            updatedCount++;
        }

        await dbTx.CommitAsync(cancellationToken);
        return (200, null, new BulkAdjustmentsResponse(updatedCount, adjustmentsInserted));
    }

    private static async Task<Guid> EnsureCashAccountAsync(
        NpgsqlConnection connection,
        Guid householdId,
        CancellationToken cancellationToken)
    {
        var connectionId = await connection.ExecuteScalarAsync<Guid>(new CommandDefinition(
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
                'cash',
                @ExternalItemId,
                'Dinheiro físico',
                @BrandColor,
                'up_to_date',
                now()
            )
            ON CONFLICT (household_id, provider, external_item_id) DO UPDATE
            SET institution_name = banking.connection.institution_name
            RETURNING id
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                ExternalItemId = CashExternalItemId,
                BrandColor = CashBrandColor
            },
            cancellationToken: cancellationToken));

        return await connection.ExecuteScalarAsync<Guid>(new CommandDefinition(
            """
            INSERT INTO banking.account (
                id,
                household_id,
                connection_id,
                external_account_id,
                name,
                kind,
                currency,
                opening_balance_cents
            )
            VALUES (
                @Id,
                @HouseholdId,
                @ConnectionId,
                @ExternalAccountId,
                'Carteira',
                'cash',
                'BRL',
                0
            )
            ON CONFLICT (connection_id, external_account_id) DO UPDATE
            SET name = banking.account.name
            RETURNING id
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                HouseholdId = householdId,
                ConnectionId = connectionId,
                ExternalAccountId = CashExternalAccountId
            },
            cancellationToken: cancellationToken));
    }

    private static async Task LinkTagsInTransactionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction dbTx,
        Guid householdId,
        Guid transactionId,
        IReadOnlyList<string> tagNames,
        bool replaceExisting,
        CancellationToken cancellationToken)
    {
        if (replaceExisting)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                "DELETE FROM banking.transaction_tag WHERE transaction_id = @TransactionId",
                new { TransactionId = transactionId },
                transaction: dbTx,
                cancellationToken: cancellationToken));
        }

        if (tagNames.Count == 0)
        {
            return;
        }

        foreach (var tagName in tagNames)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.tag (id, household_id, name, color)
                VALUES (@Id, @HouseholdId, @Name, '#A0521A')
                ON CONFLICT (household_id, lower(name)) DO NOTHING
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    HouseholdId = householdId,
                    Name = tagName
                },
                transaction: dbTx,
                cancellationToken: cancellationToken));
        }

        var tagIds = (await connection.QueryAsync<Guid>(new CommandDefinition(
            """
            SELECT id
            FROM banking.tag
            WHERE household_id = @HouseholdId
              AND lower(name) IN (SELECT lower(x) FROM unnest(@TagNames) AS x)
            """,
            new { HouseholdId = householdId, TagNames = tagNames.ToArray() },
            transaction: dbTx,
            cancellationToken: cancellationToken))).ToList();

        foreach (var tagId in tagIds)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO banking.transaction_tag (transaction_id, tag_id)
                VALUES (@TransactionId, @TagId)
                ON CONFLICT (transaction_id, tag_id) DO NOTHING
                """,
                new { TransactionId = transactionId, TagId = tagId },
                transaction: dbTx,
                cancellationToken: cancellationToken));
        }
    }

    private static (bool Ok, string? Error, List<string> Tags) NormalizeTagNames(IReadOnlyList<string>? rawTags)
    {
        var result = new List<string>();
        if (rawTags is null || rawTags.Count == 0)
        {
            return (true, null, result);
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var raw in rawTags)
        {
            if (string.IsNullOrWhiteSpace(raw))
            {
                continue;
            }

            var trimmed = raw.Trim();
            if (trimmed.Length > MaxTagNameLength)
            {
                return (false, $"Cada tag deve ter no máximo {MaxTagNameLength} caracteres.", []);
            }

            if (seen.Add(trimmed))
            {
                result.Add(trimmed);
            }
        }

        return (true, null, result);
    }

    private sealed record TagCreatedRow(Guid Id, string Name, string Color, DateTimeOffset CreatedAt);

    private sealed record BulkTargetRow(
        Guid Id,
        string? EffectiveCategory,
        string? EffectiveEssentiality,
        string? EffectiveBrand,
        string? EffectivePaymentMethod,
        bool EffectiveIsAtypical);
}

internal sealed record CreateCashTransactionRequest(
    DateOnly? OccurredOn = null,
    string? Description = null,
    long? AmountCents = null,
    string? Kind = null,
    string? Category = null,
    string? Essentiality = null,
    IReadOnlyList<string>? Tags = null,
    string? ClientMutationId = null);

internal sealed record TagDto(
    Guid Id,
    string Name,
    string Color,
    int TransactionCount,
    DateTimeOffset CreatedAt);

internal sealed record TagsListResponse(IReadOnlyList<TagDto> Items);

internal sealed record CreateTagRequest(
    string? Name = null,
    string? Color = null);

internal sealed record ReplaceTransactionTagsRequest(
    IReadOnlyList<string>? Tags = null);

internal sealed record TagReferenceDto(
    Guid Id,
    string Name,
    string Color);

internal sealed record TransactionTagsResponse(
    Guid TransactionId,
    IReadOnlyList<string> Tags,
    IReadOnlyList<TagReferenceDto> Items);

internal sealed record BulkAdjustmentsRequest(
    IReadOnlyList<Guid>? TransactionIds = null,
    string? Category = null,
    string? Essentiality = null,
    string? Brand = null,
    string? PaymentMethod = null,
    bool? IsAtypical = null,
    string? Reason = null);

internal sealed record BulkAdjustmentsResponse(
    int UpdatedCount,
    int AdjustmentsInserted);
