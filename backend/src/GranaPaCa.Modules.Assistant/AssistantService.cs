using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Dapper;
using GranaPaCa.Modules.Assistant.Contracts;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Categorization.Contracts;
using GranaPaCa.Modules.Keyring.Contracts;
using GranaPaCa.Modules.Planning.Contracts;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace GranaPaCa.Modules.Assistant;

internal sealed partial class AssistantService(
    NpgsqlDataSource dataSource,
    IEnvelopeEncryptor encryptor,
    IBankingAnalyticsReader bankingReader,
    IPlanningReader planningReader,
    ICategorizationEngine categorizationEngine,
    ExternalAiProviderClient externalClient,
    IConfiguration configuration) : IAssistantPurgeService
{
    private const string ApiKeyPurpose = "assistant.api_key";
    private const string ApiKeyTable = "assistant.provider_config";
    private const string ApiKeyColumn = "api_key_enc";
    private const decimal LowConfidenceThreshold = 0.750m;

    private static readonly IReadOnlyDictionary<string, int> PortugueseMonths =
        new Dictionary<string, int>(StringComparer.Ordinal)
        {
            ["janeiro"] = 1,
            ["fevereiro"] = 2,
            ["marco"] = 3,
            ["abril"] = 4,
            ["maio"] = 5,
            ["junho"] = 6,
            ["julho"] = 7,
            ["agosto"] = 8,
            ["setembro"] = 9,
            ["outubro"] = 10,
            ["novembro"] = 11,
            ["dezembro"] = 12
        };

    private static readonly (string Category, string[] Terms)[] QuestionCategoryKeywords =
    [
        ("food", ["alimentacao", "comida", "refeicao", "refeicoes"]),
        ("housing", ["moradia", "habitacao", "casa", "condominio", "iptu"]),
        ("transport", ["transporte", "mobilidade", "combustivel", "gasolina"]),
        ("health", ["saude", "medico", "plano de saude", "consulta", "consultas", "odonto", "hospital"]),
        ("education", ["educacao", "ensino", "curso", "cursos", "faculdade", "escola", "estudos"]),
        ("leisure", ["lazer", "entretenimento", "viagem", "diversao"]),
        ("shopping", ["compras", "varejo", "vestuario", "roupa", "roupas", "eletronico", "eletronicos"]),
        ("services", ["servicos", "servico", "telefonia", "telefone", "celular"])
    ];

    private static readonly (string NormalizedTerm, string DisplayTerm)[] KnownMerchantTerms =
    [
        ("conta de luz", "conta de luz"),
        ("supermercado", "supermercado"),
        ("restaurante", "restaurante"),
        ("lanchonete", "lanchonete"),
        ("hortifruti", "hortifruti"),
        ("papelaria", "papelaria"),
        ("armarinho", "armarinho"),
        ("streaming", "streaming"),
        ("farmacia", "farmácia"),
        ("drogaria", "drogaria"),
        ("livraria", "livraria"),
        ("academia", "academia"),
        ("internet", "internet"),
        ("delivery", "delivery"),
        ("mercado", "mercado"),
        ("padaria", "padaria"),
        ("aluguel", "aluguel"),
        ("energia", "energia"),
        ("corrida", "corrida"),
        ("acougue", "açougue"),
        ("cinema", "cinema"),
        ("posto", "posto"),
        ("feira", "feira"),
        ("ifood", "iFood"),
        ("loja", "loja"),
        ("uber", "Uber"),
        ("luz", "luz")
    ];

    private static readonly HashSet<string> DynamicMerchantStopWords = new(StringComparer.Ordinal)
    {
        "quanto", "gastei", "gasto", "gastos", "despesa", "despesas", "compra", "compras",
        "valor", "valores", "total", "resumo", "mes", "meses", "passado", "anterior", "atual",
        "para", "pelo", "pela", "pelos", "pelas", "sobre", "entre", "com", "sem", "como",
        "qual", "quais", "foram", "foi", "onde", "mais", "menos", "maior", "maiores",
        "meu", "meus", "minha", "minhas", "este", "esse", "esta", "essa", "reais", "dinheiro",
        "conta", "contas", "cartao", "fatura", "saldo", "sobra", "sobrou", "recebi", "receita",
        "categoria", "categorias", "regra", "projecao", "assinatura", "assinaturas", "comparar",
        "comparacao", "janeiro", "fevereiro", "marco", "abril", "maio", "junho", "julho",
        "agosto", "setembro", "outubro", "novembro", "dezembro"
    };

    private static readonly (string Category, string Essentiality, decimal Confidence, string Reason, string[] Keywords)[] SuggestionHeuristics =
    [
        ("food", "important", 0.720m, "Descrição associada a alimentação ou compras de mercado; confirme antes de transformar em regra.",
            ["mercado", "supermercado", "padaria", "acougue", "hortifruti", "restaurante", "lanchonete", "cafe", "pizza", "delivery", "ifood"]),
        ("health", "essential", 0.740m, "Descrição sugere despesa com saúde ou farmácia; confirme a classificação.",
            ["farmacia", "drogaria", "clinica", "medico", "odonto", "laboratorio", "hospital", "consulta"]),
        ("housing", "essential", 0.740m, "Descrição sugere despesa de moradia ou contas da casa; confirme a classificação.",
            ["aluguel", "condominio", "energia", "luz", "agua", "gas", "iptu", "material de construcao"]),
        ("transport", "important", 0.710m, "Descrição sugere transporte ou combustível; confirme a classificação.",
            ["posto", "combustivel", "estacionamento", "pedagio", "oficina", "borracharia", "uber", "99", "corrida"]),
        ("education", "important", 0.700m, "Descrição sugere educação ou papelaria/livraria; confirme a classificação.",
            ["livraria", "papelaria", "curso", "escola", "faculdade", "mensalidade"]),
        ("services", "important", 0.680m, "Descrição sugere serviço ou assinatura; confirme a classificação.",
            ["internet", "fibra", "telefonia", "assinatura", "lavanderia", "conserto", "manutencao", "academia"]),
        ("leisure", "flexible", 0.670m, "Descrição sugere lazer ou entretenimento; confirme a classificação.",
            ["cinema", "teatro", "ingresso", "streaming", "parque", "show", "clube", "bar"]),
        ("shopping", "flexible", 0.620m, "Descrição sugere compra em varejo/armarinho com confiança moderada; requer sua confirmação.",
            ["armarinho", "bazar", "loja", "magazine", "presente", "roupa", "calcado", "eletro", "tecidos", "utilidades"])
    ];

    private readonly TimeZoneInfo _instanceTimeZone = AssistantFormatting.ResolveInstanceTimeZone(configuration);

    public async Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM assistant.categorization_suggestion WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM assistant.chat_message WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM assistant.provider_config WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));
    }

    public async Task<ProviderConfigDto> GetProviderConfigAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var row = await LoadProviderRowAsync(connection, householdId, cancellationToken);
        return row is null
            ? new ProviderConfigDto("none", string.Empty, null, false, null)
            : new ProviderConfigDto(
                row.Provider,
                row.Model,
                row.BaseUrl,
                row.ApiKeyEnc is { Length: > 0 },
                row.UpdatedAt);
    }

    public async Task<(bool Ok, string? Error, ProviderConfigDto? Data)> UpdateProviderConfigAsync(
        Guid householdId,
        UpdateProviderConfigRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.Provider))
        {
            return (false, "Informe o provedor de IA (none, google, groq, openrouter, ollama, openai_compatible, openai ou anthropic).", null);
        }

        var provider = request.Provider.Trim().ToLowerInvariant();
        if (!AssistantFormatting.AllowedProviders.Contains(provider))
        {
            return (false, "Provedor inválido. Use: none, google, groq, openrouter, ollama, openai_compatible, openai ou anthropic.", null);
        }

        var model = request.Model?.Trim() ?? string.Empty;
        if (!TryValidateProviderBaseUrl(provider, request.BaseUrl, out var baseUrl, out var baseUrlError))
        {
            return (false, baseUrlError, null);
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var existing = await LoadProviderRowAsync(connection, householdId, cancellationToken);

        var sameProvider = existing is not null &&
                           string.Equals(existing.Provider, provider, StringComparison.Ordinal);
        var sameBaseUrl = existing is not null &&
                          string.Equals(existing.BaseUrl ?? string.Empty, baseUrl ?? string.Empty, StringComparison.OrdinalIgnoreCase);

        byte[]? encryptedKey;
        if (provider == "none" || request.ClearApiKey == true)
        {
            encryptedKey = null;
        }
        else if (!string.IsNullOrWhiteSpace(request.ApiKey))
        {
            var keyBytes = Encoding.UTF8.GetBytes(request.ApiKey.Trim());
            try
            {
                encryptedKey = await encryptor.EncryptAsync(
                    householdId,
                    ApiKeyPurpose,
                    keyBytes,
                    ApiKeyTable,
                    ApiKeyColumn,
                    householdId,
                    cancellationToken);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(keyBytes);
            }
        }
        else if (sameProvider && sameBaseUrl)
        {
            encryptedKey = existing!.ApiKeyEnc;
        }
        else
        {
            // Never reuse a previous provider/host API key when switching provider or baseUrl (ADR-020/023).
            encryptedKey = null;
        }

        var saved = await connection.QuerySingleAsync<ProviderConfigRow>(new CommandDefinition(
            """
            INSERT INTO assistant.provider_config (
                household_id,
                provider,
                model,
                base_url,
                api_key_enc,
                updated_at
            )
            VALUES (
                @HouseholdId,
                @Provider,
                @Model,
                @BaseUrl,
                @ApiKeyEnc,
                now()
            )
            ON CONFLICT (household_id) DO UPDATE
            SET provider = EXCLUDED.provider,
                model = EXCLUDED.model,
                base_url = EXCLUDED.base_url,
                api_key_enc = EXCLUDED.api_key_enc,
                updated_at = now()
            RETURNING
                provider AS Provider,
                model AS Model,
                base_url AS BaseUrl,
                api_key_enc AS ApiKeyEnc,
                updated_at AS UpdatedAt
            """,
            new
            {
                HouseholdId = householdId,
                Provider = provider,
                Model = model,
                BaseUrl = baseUrl,
                ApiKeyEnc = encryptedKey
            },
            cancellationToken: cancellationToken));

        return (true, null, new ProviderConfigDto(
            saved.Provider,
            saved.Model,
            saved.BaseUrl,
            saved.ApiKeyEnc is { Length: > 0 },
            saved.UpdatedAt));
    }

    public async Task<ChatHistoryResponse> GetHistoryAsync(
        Guid householdId,
        int? limit,
        CancellationToken cancellationToken)
    {
        var take = Math.Clamp(limit ?? 50, 1, 200);
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = (await connection.QueryAsync<ChatMessageRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                role AS Role,
                content AS Content,
                period_used AS PeriodUsed,
                numbers_cited_json AS NumbersCitedJson,
                provider_used AS ProviderUsed,
                created_at AS CreatedAt
            FROM (
                SELECT *
                FROM assistant.chat_message
                WHERE household_id = @HouseholdId
                ORDER BY created_at DESC, id DESC
                LIMIT @Take
            ) recent
            ORDER BY created_at ASC, id ASC
            """,
            new { HouseholdId = householdId, Take = take },
            cancellationToken: cancellationToken))).ToList();

        var items = rows.Select(MapChatMessage).ToList();
        return new ChatHistoryResponse(items);
    }

    public async Task<(bool Ok, string? Error, ChatResponse? Data)> ChatAsync(
        Guid householdId,
        ChatRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.Message))
        {
            return (false, "Escreva uma pergunta sobre suas finanças.", null);
        }

        var userMessage = request.Message.Trim();
        if (userMessage.Length > 2000)
        {
            return (false, "A mensagem excede o limite de 2.000 caracteres.", null);
        }

        var (monthOk, monthError, monthStart) = await ResolveChatMonthAsync(
            householdId,
            request.Month,
            userMessage,
            cancellationToken);
        if (!monthOk)
        {
            return (false, monthError, null);
        }

        var periodUsed = monthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);

        var metrics = await bankingReader.GetMonthMetricsAsync(householdId, monthStart, cancellationToken);
        var prevMetrics = await bankingReader.GetMonthMetricsAsync(householdId, monthStart.AddMonths(-1), cancellationToken);
        var monthTransactions = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            monthStart,
            monthStart.AddMonths(1),
            cancellationToken);
        var prevMonthTransactions = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            monthStart.AddMonths(-1),
            monthStart,
            cancellationToken);
        var planningSnapshot = await planningReader.GetSnapshotAsync(householdId, monthStart, cancellationToken);

        var (localAnswer, numbersCited) = BuildDeterministicAnswer(
            userMessage,
            monthStart,
            periodUsed,
            metrics,
            prevMetrics,
            monthTransactions,
            prevMonthTransactions,
            planningSnapshot);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var providerRow = await LoadProviderRowAsync(connection, householdId, cancellationToken);

        var finalContent = localAnswer;
        var providerUsed = "local";
        var pseudonymized = false;

        if (providerRow is not null && !string.Equals(providerRow.Provider, "none", StringComparison.Ordinal))
        {
            string? decryptedKey = null;
            if (providerRow.ApiKeyEnc is { Length: > 0 })
            {
                var keyBytes = await encryptor.DecryptAsync(
                    providerRow.ApiKeyEnc,
                    ApiKeyTable,
                    ApiKeyColumn,
                    householdId,
                    cancellationToken);
                try
                {
                    decryptedKey = Encoding.UTF8.GetString(keyBytes);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(keyBytes);
                }
            }

            var pseudonymizer = new PrivacyPseudonymizer();
            foreach (var tx in monthTransactions)
            {
                pseudonymizer.RegisterBank(tx.InstitutionName);
                pseudonymizer.RegisterAccount(tx.AccountName);
                pseudonymizer.RegisterMerchant(tx.Description);
            }

            var minimizedContext = BuildPseudonymizedContext(
                periodUsed,
                metrics,
                planningSnapshot,
                numbersCited,
                monthTransactions,
                pseudonymizer);
            var safeQuestion = pseudonymizer.SanitizeAndPseudonymize(userMessage);

            var systemPrompt =
                "Você é o assistente financeiro somente leitura do GranaPaCá. Responda em português do Brasil, " +
                "de forma objetiva, calma e sem julgamentos. Use APENAS os números exatos fornecidos no contexto, " +
                "cite o período analisado e nunca invente valores. Mantenha os tokens entre colchetes exatamente como enviados.";

            var userPrompt = $"Contexto financeiro ({periodUsed}):\n{minimizedContext}\n\nPergunta da pessoa: {safeQuestion}";

            pseudonymized = true;
            var externalReply = await externalClient.TryCompleteAsync(
                new ExternalCompletionRequest(
                    providerRow.Provider,
                    providerRow.Model,
                    providerRow.BaseUrl,
                    decryptedKey,
                    systemPrompt,
                    userPrompt),
                cancellationToken);

            if (!string.IsNullOrWhiteSpace(externalReply))
            {
                finalContent = pseudonymizer.Restore(externalReply);
                providerUsed = providerRow.Provider;
            }
            else
            {
                providerUsed = "local-fallback";
            }
        }

        var userMsgId = Guid.CreateVersion7();
        var assistantMsgId = Guid.CreateVersion7();
        var numbersJson = JsonSerializer.Serialize(numbersCited, AssistantFormatting.WebJson);

        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO assistant.chat_message (
                id,
                household_id,
                role,
                content,
                period_used,
                numbers_cited_json,
                provider_used
            )
            VALUES (
                @Id,
                @HouseholdId,
                'user',
                @Content,
                @PeriodUsed,
                NULL,
                @ProviderUsed
            )
            """,
            new
            {
                Id = userMsgId,
                HouseholdId = householdId,
                Content = userMessage,
                PeriodUsed = periodUsed,
                ProviderUsed = providerUsed
            },
            cancellationToken: cancellationToken));

        var savedAssistant = await connection.QuerySingleAsync<DateTimeOffset>(new CommandDefinition(
            """
            INSERT INTO assistant.chat_message (
                id,
                household_id,
                role,
                content,
                period_used,
                numbers_cited_json,
                provider_used
            )
            VALUES (
                @Id,
                @HouseholdId,
                'assistant',
                @Content,
                @PeriodUsed,
                @NumbersCitedJson,
                @ProviderUsed
            )
            RETURNING created_at
            """,
            new
            {
                Id = assistantMsgId,
                HouseholdId = householdId,
                Content = finalContent,
                PeriodUsed = periodUsed,
                NumbersCitedJson = numbersJson,
                ProviderUsed = providerUsed
            },
            cancellationToken: cancellationToken));

        return (true, null, new ChatResponse(
            assistantMsgId,
            finalContent,
            periodUsed,
            numbersCited,
            providerUsed,
            pseudonymized,
            savedAssistant));
    }

    public async Task<GenerateSuggestionsResponse> GenerateSuggestionsAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        var today = AssistantFormatting.TodayInTimeZone(_instanceTimeZone);
        var from = new DateOnly(2020, 1, 1);
        var toExclusive = new DateOnly(today.Year, today.Month, 1).AddMonths(2);

        var transactions = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            from,
            toExclusive,
            cancellationToken);

        var uncategorized = transactions
            .Where(t => string.IsNullOrWhiteSpace(t.Category) && t.Kind is "expense" or "refund")
            .OrderByDescending(t => t.OccurredOn)
            .ToList();

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var existingDecidedTxIds = (await connection.QueryAsync<Guid>(new CommandDefinition(
            """
            SELECT transaction_id
            FROM assistant.categorization_suggestion
            WHERE household_id = @HouseholdId
              AND status IN ('pending', 'confirmed')
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken))).ToHashSet();

        var generatedCount = 0;

        foreach (var tx in uncategorized)
        {
            if (existingDecidedTxIds.Contains(tx.Id))
            {
                continue;
            }

            var normalizedMerchant = MerchantNormalizer.NormalizeDescription(tx.Description);
            if (string.IsNullOrWhiteSpace(normalizedMerchant))
            {
                normalizedMerchant = tx.Description.Trim().ToLowerInvariant();
            }

            var engineResult = await categorizationEngine.ClassifyAsync(
                new CategorizationInput(householdId, tx.Description, null, tx.AmountCents, tx.Kind),
                cancellationToken);

            string? suggestedCategory;
            string? suggestedEssentiality;
            decimal confidence;
            string explanation;

            if (!string.IsNullOrWhiteSpace(engineResult.Category))
            {
                suggestedCategory = engineResult.Category;
                suggestedEssentiality = engineResult.Essentiality ?? "flexible";
                confidence = 0.850m;
                explanation = $"Sugestão baseada em regra existente ({engineResult.Explanation}); aguarda sua confirmação.";
            }
            else
            {
                (suggestedCategory, suggestedEssentiality, confidence, explanation) =
                    InferHeuristicSuggestion(normalizedMerchant);
            }

            var inserted = await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO assistant.categorization_suggestion (
                    id,
                    household_id,
                    transaction_id,
                    merchant_normalized,
                    suggested_category,
                    suggested_essentiality,
                    confidence,
                    explanation,
                    status
                )
                VALUES (
                    @Id,
                    @HouseholdId,
                    @TransactionId,
                    @MerchantNormalized,
                    @SuggestedCategory,
                    @SuggestedEssentiality,
                    @Confidence,
                    @Explanation,
                    'pending'
                )
                ON CONFLICT (household_id, transaction_id) WHERE status = 'pending' DO NOTHING
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    HouseholdId = householdId,
                    TransactionId = tx.Id,
                    MerchantNormalized = normalizedMerchant,
                    SuggestedCategory = suggestedCategory,
                    SuggestedEssentiality = suggestedEssentiality,
                    Confidence = confidence,
                    Explanation = explanation
                },
                cancellationToken: cancellationToken));

            if (inserted > 0)
            {
                generatedCount++;
                existingDecidedTxIds.Add(tx.Id);
            }
        }

        var pending = await ListSuggestionsAsync(householdId, "pending", cancellationToken);
        return new GenerateSuggestionsResponse(generatedCount, pending.TotalCount, pending.Items);
    }

    public async Task<SuggestionsListResponse> ListSuggestionsAsync(
        Guid householdId,
        string? status,
        CancellationToken cancellationToken)
    {
        var filter = string.IsNullOrWhiteSpace(status)
            ? "pending"
            : status.Trim().ToLowerInvariant();

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var sql = filter == "all"
            ? """
              SELECT
                  id AS Id,
                  transaction_id AS TransactionId,
                  merchant_normalized AS MerchantNormalized,
                  suggested_category AS SuggestedCategory,
                  suggested_essentiality AS SuggestedEssentiality,
                  confidence AS Confidence,
                  explanation AS Explanation,
                  status AS Status,
                  created_at AS CreatedAt,
                  decided_at AS DecidedAt
              FROM assistant.categorization_suggestion
              WHERE household_id = @HouseholdId
              ORDER BY created_at DESC, id DESC
              """
            : """
              SELECT
                  id AS Id,
                  transaction_id AS TransactionId,
                  merchant_normalized AS MerchantNormalized,
                  suggested_category AS SuggestedCategory,
                  suggested_essentiality AS SuggestedEssentiality,
                  confidence AS Confidence,
                  explanation AS Explanation,
                  status AS Status,
                  created_at AS CreatedAt,
                  decided_at AS DecidedAt
              FROM assistant.categorization_suggestion
              WHERE household_id = @HouseholdId
                AND status = @Status
              ORDER BY confidence ASC, created_at DESC, id DESC
              """;

        var rows = (await connection.QueryAsync<SuggestionRow>(new CommandDefinition(
            sql,
            new { HouseholdId = householdId, Status = filter },
            cancellationToken: cancellationToken))).ToList();

        var items = rows.Select(MapSuggestion).ToList();
        var lowConfidenceCount = items.Count(s => s.IsLowConfidence);
        return new SuggestionsListResponse(items.Count, lowConfidenceCount, items);
    }

    public async Task<(int StatusCode, string? Error, DecideSuggestionResponse? Data)> DecideSuggestionAsync(
        Guid householdId,
        Guid suggestionId,
        DecideSuggestionRequest? request,
        CancellationToken cancellationToken)
    {
        var action = request?.Action?.Trim().ToLowerInvariant();
        if (action is not ("confirm" or "reject"))
        {
            return (400, "Ação inválida; informe 'confirm' ou 'reject'.", null);
        }

        var nextStatus = action == "confirm" ? "confirmed" : "rejected";

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var existing = await connection.QuerySingleOrDefaultAsync<SuggestionRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                transaction_id AS TransactionId,
                merchant_normalized AS MerchantNormalized,
                suggested_category AS SuggestedCategory,
                suggested_essentiality AS SuggestedEssentiality,
                confidence AS Confidence,
                explanation AS Explanation,
                status AS Status,
                created_at AS CreatedAt,
                decided_at AS DecidedAt
            FROM assistant.categorization_suggestion
            WHERE id = @Id AND household_id = @HouseholdId
            """,
            new { Id = suggestionId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (existing is null)
        {
            return (404, "Sugestão não encontrada.", null);
        }

        if (!string.Equals(existing.Status, "pending", StringComparison.Ordinal))
        {
            return (409, "Esta sugestão já foi decidida anteriormente.", null);
        }

        var updated = await connection.QuerySingleAsync<SuggestionRow>(new CommandDefinition(
            """
            UPDATE assistant.categorization_suggestion
            SET status = @Status,
                decided_at = now()
            WHERE id = @Id AND household_id = @HouseholdId
            RETURNING
                id AS Id,
                transaction_id AS TransactionId,
                merchant_normalized AS MerchantNormalized,
                suggested_category AS SuggestedCategory,
                suggested_essentiality AS SuggestedEssentiality,
                confidence AS Confidence,
                explanation AS Explanation,
                status AS Status,
                created_at AS CreatedAt,
                decided_at AS DecidedAt
            """,
            new { Id = suggestionId, HouseholdId = householdId, Status = nextStatus },
            cancellationToken: cancellationToken));

        var dto = MapSuggestion(updated);
        RuleConfirmationPayloadDto? rulePayload = null;
        if (action == "confirm")
        {
            var categoryLabel = updated.SuggestedCategory is null
                ? "Outros"
                : AssistantFormatting.GetCategoryLabel(updated.SuggestedCategory);
            rulePayload = new RuleConfirmationPayloadDto(
                $"Regra para {updated.MerchantNormalized} ({categoryLabel})",
                updated.MerchantNormalized,
                updated.SuggestedCategory,
                updated.SuggestedEssentiality,
                100);
        }

        return (200, null, new DecideSuggestionResponse(dto, rulePayload));
    }

    public static IEnumerable<string> SplitIntoStreamChunks(string content)
    {
        if (string.IsNullOrEmpty(content))
        {
            yield break;
        }

        var words = content.Split(' ');
        var buffer = new StringBuilder();
        var wordsInChunk = 0;

        for (var i = 0; i < words.Length; i++)
        {
            if (buffer.Length > 0)
            {
                buffer.Append(' ');
            }

            buffer.Append(words[i]);
            wordsInChunk++;

            var isLast = i == words.Length - 1;
            if (wordsInChunk >= 4 || isLast)
            {
                if (!isLast)
                {
                    buffer.Append(' ');
                }

                yield return buffer.ToString();
                buffer.Clear();
                wordsInChunk = 0;
            }
        }
    }

    private async Task<DateOnly> ResolveBestAvailableMonthAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        var today = AssistantFormatting.TodayInTimeZone(_instanceTimeZone);
        var currentMonth = new DateOnly(today.Year, today.Month, 1);

        var currentMetrics = await bankingReader.GetMonthMetricsAsync(householdId, currentMonth, cancellationToken);
        if (currentMetrics.SpentCents > 0 || currentMetrics.ReceivedCents > 0)
        {
            return currentMonth;
        }

        var recent = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            currentMonth.AddMonths(-24),
            currentMonth.AddMonths(2),
            cancellationToken);

        if (recent.Count > 0)
        {
            var latestDate = recent.Max(t => t.OccurredOn);
            return new DateOnly(latestDate.Year, latestDate.Month, 1);
        }

        return currentMonth;
    }

    private async Task<(bool Ok, string? Error, DateOnly MonthStart)> ResolveChatMonthAsync(
        Guid householdId,
        string? explicitMonth,
        string userMessage,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitMonth))
        {
            if (DateOnly.TryParseExact(
                explicitMonth.Trim() + "-01",
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var parsedExplicit))
            {
                return (true, null, parsedExplicit);
            }

            return (false, "Mês inválido; use o formato YYYY-MM.", default);
        }

        var isoMatch = IsoMonthRegex().Match(userMessage);
        if (isoMatch.Success &&
            DateOnly.TryParseExact(
                isoMatch.Value + "-01",
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var parsedFromText))
        {
            return (true, null, parsedFromText);
        }

        var brMatch = BrMonthYearRegex().Match(userMessage);
        if (brMatch.Success &&
            int.TryParse(brMatch.Groups[1].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var brMonth) &&
            int.TryParse(brMatch.Groups[2].Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var brYear))
        {
            return (true, null, new DateOnly(brYear, brMonth, 1));
        }

        var folded = FoldLower(userMessage);
        int? matchedMonthNumber = null;
        var earliestMatchIndex = int.MaxValue;

        foreach (var (monthName, monthNumber) in PortugueseMonths)
        {
            var match = Regex.Match(folded, $@"\b{monthName}\b", RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));
            if (match.Success && match.Index < earliestMatchIndex)
            {
                earliestMatchIndex = match.Index;
                matchedMonthNumber = monthNumber;
            }
        }

        if (matchedMonthNumber.HasValue)
        {
            var yearMatch = YearRegex().Match(folded);
            if (yearMatch.Success &&
                int.TryParse(yearMatch.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedYear))
            {
                return (true, null, new DateOnly(parsedYear, matchedMonthNumber.Value, 1));
            }

            var today = AssistantFormatting.TodayInTimeZone(_instanceTimeZone);
            var candidate = new DateOnly(today.Year, matchedMonthNumber.Value, 1);
            var candidateMetrics = await bankingReader.GetMonthMetricsAsync(householdId, candidate, cancellationToken);
            if (candidateMetrics.SpentCents > 0 || candidateMetrics.ReceivedCents > 0)
            {
                return (true, null, candidate);
            }

            var historical = await bankingReader.GetTransactionsInRangeAsync(
                householdId,
                new DateOnly(today.Year - 3, 1, 1),
                new DateOnly(today.Year + 1, 1, 1),
                cancellationToken);
            var latestForMonth = historical
                .Where(t => t.OccurredOn.Month == matchedMonthNumber.Value)
                .OrderByDescending(t => t.OccurredOn)
                .FirstOrDefault();

            return latestForMonth is not null
                ? (true, null, new DateOnly(latestForMonth.OccurredOn.Year, matchedMonthNumber.Value, 1))
                : (true, null, candidate);
        }

        var bestMonth = await ResolveBestAvailableMonthAsync(householdId, cancellationToken);
        if (!IsComparisonQuery(folded) &&
            (folded.Contains("mes passado", StringComparison.Ordinal) ||
             folded.Contains("mes anterior", StringComparison.Ordinal)))
        {
            return (true, null, bestMonth.AddMonths(-1));
        }

        return (true, null, bestMonth);
    }

    private static (string Answer, IReadOnlyList<CitedNumberDto> NumbersCited) BuildDeterministicAnswer(
        string userMessage,
        DateOnly monthStart,
        string periodUsed,
        BankingMonthMetrics metrics,
        BankingMonthMetrics prevMetrics,
        IReadOnlyList<BankingTransactionFact> monthTransactions,
        IReadOnlyList<BankingTransactionFact> prevMonthTransactions,
        PlanningSnapshot planning)
    {
        var folded = FoldLower(userMessage);
        var prevPeriod = monthStart.AddMonths(-1).ToString("yyyy-MM", CultureInfo.InvariantCulture);
        var cited = new List<CitedNumberDto>();

        void Cite(string label, long cents) =>
            cited.Add(new CitedNumberDto(label, cents, AssistantFormatting.FormatBrl(cents)));

        // 1. Top 5 largest expenses of the month with exact dates & values
        if (IsTopExpensesQuery(folded))
        {
            var topExpenses = monthTransactions
                .Where(t => t.Kind == "expense" && t.AmountCents < 0)
                .OrderBy(t => t.AmountCents)
                .ThenByDescending(t => t.OccurredOn)
                .ThenBy(t => t.Description, StringComparer.Ordinal)
                .Take(5)
                .ToList();

            if (topExpenses.Count == 0)
            {
                Cite($"Gasto total ({periodUsed})", metrics.SpentCents);
                return ($"Em {periodUsed}, não há despesas registradas até o momento (total: {AssistantFormatting.FormatBrl(metrics.SpentCents)}).", cited);
            }

            var sb = new StringBuilder();
            var heading = topExpenses.Count == 1
                ? $"O maior gasto em {periodUsed} foi:"
                : $"Os {topExpenses.Count} maiores gastos em {periodUsed} foram:";
            sb.AppendLine(heading);

            for (var i = 0; i < topExpenses.Count; i++)
            {
                var tx = topExpenses[i];
                var absCents = Math.Abs(tx.AmountCents);
                var categoryLabel = AssistantFormatting.GetCategoryLabel(tx.Category ?? "uncategorized");
                var dateText = tx.OccurredOn.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
                Cite($"{tx.Description} ({dateText})", absCents);
                sb.AppendLine($"{i + 1}. {dateText} — {tx.Description}: {AssistantFormatting.FormatBrl(absCents)} ({categoryLabel})");
            }

            Cite($"Gasto total ({periodUsed})", metrics.SpentCents);
            sb.Append($"Total gasto no período: {AssistantFormatting.FormatBrl(metrics.SpentCents)}.");
            return (sb.ToString(), cited);
        }

        // 2. 50/30/20 rule query
        if (folded.Contains("50/30/20", StringComparison.Ordinal) ||
            folded.Contains("50 30 20", StringComparison.Ordinal) ||
            folded.Contains("essenciais", StringComparison.Ordinal) ||
            folded.Contains("essencial", StringComparison.Ordinal) ||
            folded.Contains("necessidades", StringComparison.Ordinal))
        {
            var baseCents = metrics.ReceivedCents > 0
                ? metrics.ReceivedCents
                : planning.NeedsCents + planning.WantsCents + planning.SavingsCents;
            var needsPct = baseCents > 0 ? Math.Round(planning.NeedsCents * 100m / baseCents, 1, MidpointRounding.AwayFromZero) : 0m;
            var wantsPct = baseCents > 0 ? Math.Round(planning.WantsCents * 100m / baseCents, 1, MidpointRounding.AwayFromZero) : 0m;
            var savingsPct = baseCents > 0 ? Math.Round(planning.SavingsCents * 100m / baseCents, 1, MidpointRounding.AwayFromZero) : 0m;

            Cite("Necessidades (essenciais)", planning.NeedsCents);
            Cite("Desejos (importantes + flexíveis)", planning.WantsCents);
            Cite("Poupança / sobra", planning.SavingsCents);

            var reply =
                $"Na regra 50/30/20 de {periodUsed}: Necessidades (essenciais) somaram {AssistantFormatting.FormatBrl(planning.NeedsCents)} ({needsPct:0.0}%), " +
                $"Desejos (importantes e flexíveis) somaram {AssistantFormatting.FormatBrl(planning.WantsCents)} ({wantsPct:0.0}%) " +
                $"e Poupança/sobra ficou em {AssistantFormatting.FormatBrl(planning.SavingsCents)} ({savingsPct:0.0}%).";

            return (reply, cited);
        }

        // 3. Projection / end-of-month query
        if (folded.Contains("projecao", StringComparison.Ordinal) ||
            folded.Contains("projetar", StringComparison.Ordinal) ||
            folded.Contains("fim do mes", StringComparison.Ordinal) ||
            folded.Contains("fechar o mes", StringComparison.Ordinal) ||
            folded.Contains("fechamento", StringComparison.Ordinal) ||
            folded.Contains("atipic", StringComparison.Ordinal))
        {
            Cite("Projeção de gastos do mês (sem atípicos)", planning.ProjectedMonthEndSpentCents);
            Cite("Gasto realizado no mês", metrics.SpentCents);
            if (metrics.AtypicalSpentCents > 0)
            {
                Cite("Gastos atípicos excluídos da projeção", metrics.AtypicalSpentCents);
            }

            var reply =
                $"Para {periodUsed}, a projeção de fechamento é de {AssistantFormatting.FormatBrl(planning.ProjectedMonthEndSpentCents)} " +
                $"(excluindo {AssistantFormatting.FormatBrl(metrics.AtypicalSpentCents)} em gastos atípicos). " +
                $"Até agora, o total gasto registrado no período é {AssistantFormatting.FormatBrl(metrics.SpentCents)}.";

            return (reply, cited);
        }

        // 4. Subscriptions / recurring query
        if (folded.Contains("assinatura", StringComparison.Ordinal) ||
            folded.Contains("recorrente", StringComparison.Ordinal))
        {
            Cite("Gastos recorrentes no mês", metrics.RecurringSpentCents);
            Cite("Total gasto no mês", metrics.SpentCents);

            var sb = new StringBuilder();
            var subLabel = planning.DetectedSubscriptionsCount == 1
                ? "1 assinatura/cobrança recorrente"
                : $"{planning.DetectedSubscriptionsCount} assinaturas/cobranças recorrentes";
            sb.Append(
                $"Em {periodUsed}, foram detectadas {subLabel}, " +
                $"com {AssistantFormatting.FormatBrl(metrics.RecurringSpentCents)} em gastos recorrentes registrados no período.");

            if (metrics.SpentByCategoryCents.TryGetValue("services", out var servicesCents) && servicesCents > 0)
            {
                Cite($"Serviços e assinaturas ({periodUsed})", servicesCents);
                sb.Append($" Na categoria Serviços e assinaturas, o total foi {AssistantFormatting.FormatBrl(servicesCents)}.");
            }

            return (sb.ToString(), cited);
        }

        // 5. Top category / heaviest spending category query
        if (folded.Contains("qual categoria", StringComparison.Ordinal) ||
            folded.Contains("pesou mais", StringComparison.Ordinal) ||
            folded.Contains("onde gastei mais", StringComparison.Ordinal) ||
            folded.Contains("ranking", StringComparison.Ordinal))
        {
            var topCategories = metrics.SpentByCategoryCents
                .Where(kv => kv.Value > 0)
                .OrderByDescending(kv => kv.Value)
                .Take(3)
                .ToList();

            if (topCategories.Count == 0)
            {
                Cite($"Gasto total ({periodUsed})", metrics.SpentCents);
                return ($"Em {periodUsed}, não há gastos categorizados registrados até o momento (total: {AssistantFormatting.FormatBrl(metrics.SpentCents)}).", cited);
            }

            var sb = new StringBuilder();
            var leader = topCategories[0];
            var leaderLabel = AssistantFormatting.GetCategoryLabel(leader.Key);
            var leaderShare = metrics.SpentCents > 0
                ? Math.Round(leader.Value * 100m / metrics.SpentCents, 1, MidpointRounding.AwayFromZero)
                : 0m;

            Cite($"{leaderLabel} ({periodUsed})", leader.Value);
            sb.Append($"Em {periodUsed}, a categoria que mais pesou foi {leaderLabel}, com {AssistantFormatting.FormatBrl(leader.Value)} ({leaderShare:0.0}% do total).");

            if (topCategories.Count > 1)
            {
                sb.Append(" Na sequência: ");
                var rest = new List<string>();
                foreach (var entry in topCategories.Skip(1))
                {
                    var label = AssistantFormatting.GetCategoryLabel(entry.Key);
                    Cite($"{label} ({periodUsed})", entry.Value);
                    rest.Add($"{label} ({AssistantFormatting.FormatBrl(entry.Value)})");
                }

                sb.Append(string.Join(" e ", rest)).Append('.');
            }

            Cite($"Gasto total ({periodUsed})", metrics.SpentCents);
            return (sb.ToString(), cited);
        }

        var matchedCategory = FindRequestedCategory(folded);

        // 6. Merchant-specific query (matching normalized descriptions like supermercado, padaria, farmácia, posto, restaurante)
        var merchantMatch = FindRequestedMerchant(
            userMessage,
            folded,
            matchedCategory,
            monthTransactions);
        if (merchantMatch is not null)
        {
            var matchedCurrent = FilterTransactionsByMerchant(monthTransactions, merchantMatch.NormalizedTerm);
            var matchedPrev = FilterTransactionsByMerchant(prevMonthTransactions, merchantMatch.NormalizedTerm);

            var currentExpenses = matchedCurrent.Where(t => t.Kind == "expense" && t.AmountCents < 0)
                .OrderBy(t => t.OccurredOn)
                .ThenBy(t => t.AmountCents)
                .ToList();
            var currentRefunds = matchedCurrent.Where(t => t.Kind == "refund" && t.AmountCents > 0).ToList();
            var currentTotalCents = Math.Max(0L, currentExpenses.Sum(t => -t.AmountCents) - currentRefunds.Sum(t => t.AmountCents));

            var prevTotalCents = Math.Max(
                0L,
                matchedPrev.Where(t => t.Kind == "expense" && t.AmountCents < 0).Sum(t => -t.AmountCents)
                - matchedPrev.Where(t => t.Kind == "refund" && t.AmountCents > 0).Sum(t => t.AmountCents));

            Cite($"Gastos em {merchantMatch.DisplayTerm} ({periodUsed})", currentTotalCents);
            Cite($"Gasto total ({periodUsed})", metrics.SpentCents);

            if (currentExpenses.Count == 0 && currentTotalCents == 0)
            {
                var emptySb = new StringBuilder();
                emptySb.Append($"Em {periodUsed}, não houve gastos registrados correspondentes a \"{merchantMatch.DisplayTerm}\" (0 lançamentos, R$ 0,00).");
                if (prevTotalCents > 0)
                {
                    Cite($"Gastos em {merchantMatch.DisplayTerm} ({prevPeriod})", prevTotalCents);
                    emptySb.Append($" Em {prevPeriod}, o total havia sido {AssistantFormatting.FormatBrl(prevTotalCents)}.");
                }

                return (emptySb.ToString(), cited);
            }

            var countLabel = currentExpenses.Count == 1
                ? "1 lançamento"
                : $"{currentExpenses.Count} lançamentos";
            var distinctMerchants = currentExpenses
                .Select(t => t.Description.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Take(3)
                .ToList();
            var share = metrics.SpentCents > 0
                ? Math.Round(currentTotalCents * 100m / metrics.SpentCents, 1, MidpointRounding.AwayFromZero)
                : 0m;

            var sb = new StringBuilder();
            sb.Append($"Em {periodUsed}, você registrou {countLabel} em \"{merchantMatch.DisplayTerm}\"");
            if (distinctMerchants.Count > 0)
            {
                sb.Append($" ({string.Join(", ", distinctMerchants)})");
            }

            sb.Append($", totalizando {AssistantFormatting.FormatBrl(currentTotalCents)}");
            if (metrics.SpentCents > 0)
            {
                sb.Append($" ({share:0.0}% do total de {AssistantFormatting.FormatBrl(metrics.SpentCents)})");
            }

            sb.Append('.');

            if (currentExpenses.Count <= 5)
            {
                var details = currentExpenses.Select(tx =>
                    $"{tx.OccurredOn:dd/MM/yyyy} ({AssistantFormatting.FormatBrl(Math.Abs(tx.AmountCents))})");
                sb.Append($" Detalhes: {string.Join(", ", details)}.");
            }

            if (prevTotalCents > 0)
            {
                var diff = currentTotalCents - prevTotalCents;
                Cite($"Gastos em {merchantMatch.DisplayTerm} ({prevPeriod})", prevTotalCents);
                var direction = diff >= 0 ? "a mais" : "a menos";
                sb.Append($" Em relação a {prevPeriod} ({AssistantFormatting.FormatBrl(prevTotalCents)}), foram {AssistantFormatting.FormatBrl(Math.Abs(diff))} {direction}.");
            }

            return (sb.ToString(), cited);
        }

        // 7. Specific category query (e.g., alimentação, moradia, transporte, saúde, lazer, compras, educação)
        if (matchedCategory is not null)
        {
            var categoryLabel = AssistantFormatting.GetCategoryLabel(matchedCategory);
            var catSpent = metrics.SpentByCategoryCents.GetValueOrDefault(matchedCategory, 0L);
            var prevCatSpent = prevMetrics.SpentByCategoryCents.GetValueOrDefault(matchedCategory, 0L);
            var share = metrics.SpentCents > 0
                ? Math.Round(catSpent * 100m / metrics.SpentCents, 1, MidpointRounding.AwayFromZero)
                : 0m;

            Cite($"Gasto em {categoryLabel} ({periodUsed})", catSpent);
            Cite($"Gasto total ({periodUsed})", metrics.SpentCents);

            var sb = new StringBuilder();
            sb.Append($"Em {periodUsed}, você gastou {AssistantFormatting.FormatBrl(catSpent)} em {categoryLabel}");
            if (metrics.SpentCents > 0)
            {
                sb.Append($" ({share:0.0}% do total de {AssistantFormatting.FormatBrl(metrics.SpentCents)})");
            }

            sb.Append('.');

            if (prevCatSpent > 0)
            {
                var diff = catSpent - prevCatSpent;
                Cite($"Gasto em {categoryLabel} ({prevPeriod})", prevCatSpent);
                var direction = diff >= 0 ? "a mais" : "a menos";
                sb.Append($" Em relação a {prevPeriod} ({AssistantFormatting.FormatBrl(prevCatSpent)}), foram {AssistantFormatting.FormatBrl(Math.Abs(diff))} {direction}.");
            }

            return (sb.ToString(), cited);
        }

        // 8. Month-over-month comparison query ("comparar com mês passado")
        if (IsComparisonQuery(folded))
        {
            var spentDiff = metrics.SpentCents - prevMetrics.SpentCents;
            Cite($"Gastos ({periodUsed})", metrics.SpentCents);
            Cite($"Gastos ({prevPeriod})", prevMetrics.SpentCents);
            Cite("Diferença de gastos", spentDiff);
            Cite($"Sobra ({periodUsed})", metrics.LeftoverCents);
            Cite($"Sobra ({prevPeriod})", prevMetrics.LeftoverCents);

            var diffDescription = spentDiff == 0
                ? "exatamente no mesmo patamar"
                : $"{AssistantFormatting.FormatBrl(Math.Abs(spentDiff))} {(spentDiff > 0 ? "a mais" : "a menos")}";
            if (prevMetrics.SpentCents > 0 && spentDiff != 0)
            {
                var pct = Math.Round(Math.Abs(spentDiff) * 100m / prevMetrics.SpentCents, 1, MidpointRounding.AwayFromZero);
                diffDescription = $"{diffDescription} ({pct:0.0}%)";
            }

            var sb = new StringBuilder();
            sb.Append(
                $"Comparando {periodUsed} com {prevPeriod}: seus gastos foram de {AssistantFormatting.FormatBrl(metrics.SpentCents)} " +
                $"contra {AssistantFormatting.FormatBrl(prevMetrics.SpentCents)} no mês anterior ({diffDescription}). " +
                $"A sobra foi de {AssistantFormatting.FormatBrl(metrics.LeftoverCents)} frente a {AssistantFormatting.FormatBrl(prevMetrics.LeftoverCents)} em {prevPeriod}.");

            var allCategories = metrics.SpentByCategoryCents.Keys
                .Union(prevMetrics.SpentByCategoryCents.Keys, StringComparer.Ordinal)
                .Select(cat => (
                    Category: cat,
                    Delta: metrics.SpentByCategoryCents.GetValueOrDefault(cat, 0L) - prevMetrics.SpentByCategoryCents.GetValueOrDefault(cat, 0L)))
                .Where(x => x.Delta != 0)
                .OrderByDescending(x => Math.Abs(x.Delta))
                .FirstOrDefault();

            if (!string.IsNullOrEmpty(allCategories.Category))
            {
                var catLabel = AssistantFormatting.GetCategoryLabel(allCategories.Category);
                var catDir = allCategories.Delta > 0 ? "subiu" : "caiu";
                sb.Append($" A maior variação por categoria foi em {catLabel}, que {catDir} {AssistantFormatting.FormatBrl(Math.Abs(allCategories.Delta))}.");
            }

            return (sb.ToString(), cited);
        }

        // 9. Leftover / balance / income / card bill query
        if (folded.Contains("sobrou", StringComparison.Ordinal) ||
            folded.Contains("sobra", StringComparison.Ordinal) ||
            folded.Contains("saldo", StringComparison.Ordinal) ||
            folded.Contains("recebi", StringComparison.Ordinal) ||
            folded.Contains("receita", StringComparison.Ordinal) ||
            folded.Contains("fatura", StringComparison.Ordinal))
        {
            Cite($"Receitas ({periodUsed})", metrics.ReceivedCents);
            Cite($"Gastos ({periodUsed})", metrics.SpentCents);
            Cite($"Sobra ({periodUsed})", metrics.LeftoverCents);
            Cite("Saldo atual em contas", metrics.BalanceCents);
            if (metrics.CardBillCents > 0)
            {
                Cite("Fatura aberta de cartão", metrics.CardBillCents);
            }

            var reply =
                $"Em {periodUsed}, entraram {AssistantFormatting.FormatBrl(metrics.ReceivedCents)} e saíram {AssistantFormatting.FormatBrl(metrics.SpentCents)}, " +
                $"resultando em uma sobra de {AssistantFormatting.FormatBrl(metrics.LeftoverCents)}. " +
                $"O saldo atual somado das contas é {AssistantFormatting.FormatBrl(metrics.BalanceCents)}" +
                (metrics.CardBillCents > 0
                    ? $" e a fatura aberta de cartão está em {AssistantFormatting.FormatBrl(metrics.CardBillCents)}."
                    : ".");

            return (reply, cited);
        }

        // 10. General overview ("quanto gastei?", default)
        Cite($"Gastos ({periodUsed})", metrics.SpentCents);
        Cite($"Receitas ({periodUsed})", metrics.ReceivedCents);
        Cite($"Sobra ({periodUsed})", metrics.LeftoverCents);

        var top = metrics.SpentByCategoryCents
            .Where(kv => kv.Value > 0)
            .OrderByDescending(kv => kv.Value)
            .FirstOrDefault();

        var summary = new StringBuilder();
        summary.Append(
            $"Em {periodUsed}, você gastou {AssistantFormatting.FormatBrl(metrics.SpentCents)} " +
            $"e recebeu {AssistantFormatting.FormatBrl(metrics.ReceivedCents)}, " +
            $"com sobra de {AssistantFormatting.FormatBrl(metrics.LeftoverCents)}.");

        if (!string.IsNullOrEmpty(top.Key))
        {
            var topLabel = AssistantFormatting.GetCategoryLabel(top.Key);
            Cite($"Maior categoria: {topLabel}", top.Value);
            summary.Append($" A categoria com maior peso foi {topLabel} ({AssistantFormatting.FormatBrl(top.Value)}).");
        }

        if (monthTransactions.Count > 0)
        {
            Cite("Projeção do mês (sem atípicos)", planning.ProjectedMonthEndSpentCents);
            summary.Append($" A projeção de fechamento do mês sem gastos atípicos é {AssistantFormatting.FormatBrl(planning.ProjectedMonthEndSpentCents)}.");
        }

        return (summary.ToString(), cited);
    }

    private static string BuildPseudonymizedContext(
        string periodUsed,
        BankingMonthMetrics metrics,
        PlanningSnapshot planning,
        IReadOnlyList<CitedNumberDto> numbersCited,
        IReadOnlyList<BankingTransactionFact> monthTransactions,
        PrivacyPseudonymizer pseudonymizer)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"Período: {periodUsed}");
        sb.AppendLine($"Gastos totais: {AssistantFormatting.FormatBrl(metrics.SpentCents)}");
        sb.AppendLine($"Receitas totais: {AssistantFormatting.FormatBrl(metrics.ReceivedCents)}");
        sb.AppendLine($"Sobra: {AssistantFormatting.FormatBrl(metrics.LeftoverCents)}");
        sb.AppendLine($"Saldo em contas: {AssistantFormatting.FormatBrl(metrics.BalanceCents)}");
        sb.AppendLine($"Fatura aberta: {AssistantFormatting.FormatBrl(metrics.CardBillCents)}");
        sb.AppendLine($"Projeção sem atípicos: {AssistantFormatting.FormatBrl(planning.ProjectedMonthEndSpentCents)}");
        sb.AppendLine($"50/30/20: Necessidades={AssistantFormatting.FormatBrl(planning.NeedsCents)}, Desejos={AssistantFormatting.FormatBrl(planning.WantsCents)}, Poupança={AssistantFormatting.FormatBrl(planning.SavingsCents)}");
        sb.AppendLine($"Assinaturas detectadas: {planning.DetectedSubscriptionsCount}");

        if (metrics.SpentByCategoryCents.Count > 0)
        {
            sb.AppendLine("Gastos por categoria:");
            foreach (var kv in metrics.SpentByCategoryCents.OrderByDescending(x => x.Value))
            {
                sb.AppendLine($"- {AssistantFormatting.GetCategoryLabel(kv.Key)}: {AssistantFormatting.FormatBrl(kv.Value)}");
            }
        }

        var topExpenses = monthTransactions
            .Where(t => t.Kind == "expense" && t.AmountCents < 0)
            .OrderBy(t => t.AmountCents)
            .Take(8)
            .ToList();

        if (topExpenses.Count > 0)
        {
            sb.AppendLine("Principais despesas (pseudonimizadas):");
            foreach (var tx in topExpenses)
            {
                var bankToken = pseudonymizer.RegisterBank(tx.InstitutionName);
                var merchantToken = pseudonymizer.RegisterMerchant(tx.Description);
                var categoryLabel = AssistantFormatting.GetCategoryLabel(tx.Category ?? "uncategorized");
                sb.AppendLine($"- {tx.OccurredOn:yyyy-MM-dd} | {bankToken} | {merchantToken} | {categoryLabel} | {AssistantFormatting.FormatBrl(Math.Abs(tx.AmountCents))}");
            }
        }

        if (numbersCited.Count > 0)
        {
            sb.AppendLine("Números exatos de referência:");
            foreach (var item in numbersCited)
            {
                sb.AppendLine($"- {item.Label}: {item.Formatted}");
            }
        }

        return pseudonymizer.SanitizeAndPseudonymize(sb.ToString());
    }

    private static bool IsTopExpensesQuery(string foldedQuestion)
    {
        if (foldedQuestion.Contains("qual categoria", StringComparison.Ordinal) ||
            foldedQuestion.Contains("pesou mais", StringComparison.Ordinal))
        {
            return false;
        }

        return foldedQuestion.Contains("maiores gastos", StringComparison.Ordinal) ||
               foldedQuestion.Contains("maiores despesas", StringComparison.Ordinal) ||
               foldedQuestion.Contains("maiores compras", StringComparison.Ordinal) ||
               foldedQuestion.Contains("top gastos", StringComparison.Ordinal) ||
               foldedQuestion.Contains("top despesas", StringComparison.Ordinal) ||
               foldedQuestion.Contains("top 5", StringComparison.Ordinal) ||
               foldedQuestion.Contains("gastos mais altos", StringComparison.Ordinal) ||
               foldedQuestion.Contains("despesas mais altas", StringComparison.Ordinal) ||
               foldedQuestion.Contains("gastos mais caros", StringComparison.Ordinal) ||
               foldedQuestion.Contains("despesas mais caras", StringComparison.Ordinal) ||
               foldedQuestion.Contains("maior gasto", StringComparison.Ordinal) ||
               foldedQuestion.Contains("maior despesa", StringComparison.Ordinal) ||
               foldedQuestion.Contains("maior compra", StringComparison.Ordinal);
    }

    private static bool IsComparisonQuery(string foldedQuestion) =>
        foldedQuestion.Contains("compar", StringComparison.Ordinal) ||
        foldedQuestion.Contains("relacao ao mes", StringComparison.Ordinal) ||
        foldedQuestion.Contains("frente ao mes", StringComparison.Ordinal) ||
        foldedQuestion.Contains("versus mes", StringComparison.Ordinal) ||
        foldedQuestion.Contains("vs mes", StringComparison.Ordinal) ||
        foldedQuestion.Contains("gastei mais ou menos", StringComparison.Ordinal) ||
        foldedQuestion.Contains("evolucao mensal", StringComparison.Ordinal);

    private static string? FindRequestedCategory(string foldedQuestion)
    {
        foreach (var (category, terms) in QuestionCategoryKeywords)
        {
            if (terms.Any(term => ContainsWord(foldedQuestion, term)))
            {
                return category;
            }
        }

        return null;
    }

    private static MerchantQueryMatch? FindRequestedMerchant(
        string userMessage,
        string foldedQuestion,
        string? matchedCategory,
        IReadOnlyList<BankingTransactionFact> monthTransactions)
    {
        foreach (var (normalizedTerm, displayTerm) in KnownMerchantTerms)
        {
            if (ContainsWord(foldedQuestion, normalizedTerm))
            {
                return new MerchantQueryMatch(normalizedTerm, displayTerm);
            }
        }

        if (matchedCategory is not null ||
            IsComparisonQuery(foldedQuestion) ||
            foldedQuestion.Contains("sobrou", StringComparison.Ordinal) ||
            foldedQuestion.Contains("sobra", StringComparison.Ordinal) ||
            foldedQuestion.Contains("saldo", StringComparison.Ordinal) ||
            foldedQuestion.Contains("fatura", StringComparison.Ordinal))
        {
            return null;
        }

        var normalizedQuestion = MerchantNormalizer.NormalizeDescription(userMessage);
        if (string.IsNullOrWhiteSpace(normalizedQuestion))
        {
            return null;
        }

        var expenseDescriptions = monthTransactions
            .Where(t => t.Kind is "expense" or "refund")
            .Select(t => (Original: t.Description.Trim(), Normalized: MerchantNormalizer.NormalizeDescription(t.Description)))
            .Where(x => x.Normalized.Length >= 4)
            .DistinctBy(x => x.Normalized, StringComparer.Ordinal)
            .ToList();

        foreach (var entry in expenseDescriptions.OrderByDescending(x => x.Normalized.Length))
        {
            if (ContainsWord(normalizedQuestion, entry.Normalized))
            {
                return new MerchantQueryMatch(entry.Normalized, entry.Original);
            }
        }

        var questionTokens = normalizedQuestion
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(token => token.Length >= 4 &&
                            !DynamicMerchantStopWords.Contains(token) &&
                            !token.All(char.IsDigit))
            .Distinct(StringComparer.Ordinal)
            .ToList();

        foreach (var token in questionTokens)
        {
            var matchedEntry = expenseDescriptions.FirstOrDefault(entry =>
                entry.Normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                    .Any(txToken => string.Equals(txToken, token, StringComparison.Ordinal)));

            if (!string.IsNullOrEmpty(matchedEntry.Normalized))
            {
                return new MerchantQueryMatch(token, token);
            }
        }

        return null;
    }

    private static List<BankingTransactionFact> FilterTransactionsByMerchant(
        IReadOnlyList<BankingTransactionFact> transactions,
        string normalizedTerm)
    {
        return transactions
            .Where(tx => tx.Kind is "expense" or "refund")
            .Where(tx => MerchantNormalizer.NormalizeDescription(tx.Description)
                .Contains(normalizedTerm, StringComparison.Ordinal))
            .ToList();
    }

    private static bool ContainsWord(string foldedText, string normalizedPhrase) =>
        Regex.IsMatch(
            foldedText,
            $@"(?<![a-z0-9]){Regex.Escape(normalizedPhrase)}s?(?![a-z0-9])",
            RegexOptions.CultureInvariant,
            TimeSpan.FromSeconds(1));

    private sealed record MerchantQueryMatch(string NormalizedTerm, string DisplayTerm);

    private static (string Category, string Essentiality, decimal Confidence, string Explanation) InferHeuristicSuggestion(
        string normalizedMerchant)
    {
        foreach (var (category, essentiality, confidence, reason, keywords) in SuggestionHeuristics)
        {
            if (keywords.Any(kw => normalizedMerchant.Contains(kw, StringComparison.Ordinal)))
            {
                return (category, essentiality, confidence, reason);
            }
        }

        return (
            "other",
            "flexible",
            0.420m,
            "Estabelecimento sem histórico ou palavra-chave forte; baixa confiança, requer confirmação manual.");
    }

    private static async Task<ProviderConfigRow?> LoadProviderRowAsync(
        NpgsqlConnection connection,
        Guid householdId,
        CancellationToken cancellationToken)
    {
        return await connection.QuerySingleOrDefaultAsync<ProviderConfigRow>(new CommandDefinition(
            """
            SELECT
                provider AS Provider,
                model AS Model,
                base_url AS BaseUrl,
                api_key_enc AS ApiKeyEnc,
                updated_at AS UpdatedAt
            FROM assistant.provider_config
            WHERE household_id = @HouseholdId
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken));
    }

    private static ChatMessageDto MapChatMessage(ChatMessageRow row)
    {
        IReadOnlyList<CitedNumberDto> cited = [];
        if (!string.IsNullOrWhiteSpace(row.NumbersCitedJson))
        {
            try
            {
                cited = JsonSerializer.Deserialize<List<CitedNumberDto>>(
                    row.NumbersCitedJson,
                    AssistantFormatting.WebJson) ?? [];
            }
            catch (JsonException)
            {
                cited = [];
            }
        }

        return new ChatMessageDto(
            row.Id,
            row.Role,
            row.Content,
            row.PeriodUsed,
            cited,
            row.ProviderUsed,
            row.CreatedAt);
    }

    private static CategorizationSuggestionDto MapSuggestion(SuggestionRow row) =>
        new(
            row.Id,
            row.TransactionId,
            row.MerchantNormalized,
            row.SuggestedCategory,
            row.SuggestedCategory is null ? null : AssistantFormatting.GetCategoryLabel(row.SuggestedCategory),
            row.SuggestedEssentiality,
            row.Confidence,
            row.Confidence < LowConfidenceThreshold,
            row.Explanation,
            row.Status,
            row.CreatedAt,
            row.DecidedAt);

    private static string FoldLower(string text)
    {
        var formD = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(formD.Length);
        foreach (var ch in formD)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
            {
                sb.Append(char.ToLowerInvariant(ch));
            }
        }

        return sb.ToString();
    }

    internal static bool TryValidateProviderBaseUrl(
        string provider,
        string? rawBaseUrl,
        out string? validatedUrl,
        out string? error)
    {
        validatedUrl = null;
        error = null;

        if (string.IsNullOrWhiteSpace(rawBaseUrl))
        {
            return true;
        }

        var trimmedUrl = rawBaseUrl.Trim();
        if (!Uri.TryCreate(trimmedUrl, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            error = "A URL base do provedor deve começar com https:// (ou http:// apenas para Ollama/endpoint OpenAI-compatível local ou privado).";
            return false;
        }

        if (!string.IsNullOrEmpty(uri.UserInfo))
        {
            error = "A URL base do provedor não pode conter credenciais embutidas.";
            return false;
        }

        var host = uri.DnsSafeHost.Trim().TrimEnd('.').ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(host))
        {
            error = "Informe um host válido para a URL base do provedor.";
            return false;
        }

        // Always block cloud metadata hostnames even for local providers.
        if (host is "metadata.google.internal" or "metadata" or "instance-data")
        {
            error = "Endereço interno de metadados não é permitido como URL base do provedor.";
            return false;
        }

        bool isLocalOrPrivateTarget;
        if (IPAddress.TryParse(host, out var ipAddress))
        {
            if (ipAddress.IsIPv4MappedToIPv6)
            {
                ipAddress = ipAddress.MapToIPv4();
            }

            if (IsLinkLocalOrUnspecified(ipAddress))
            {
                error = "Endereços link-local ou de metadados (como 169.254.169.254) não são permitidos.";
                return false;
            }

            isLocalOrPrivateTarget = IsLoopbackOrPrivate(ipAddress);
        }
        else
        {
            isLocalOrPrivateTarget = IsLocalHostname(host);
        }

        var allowsLocalTarget = provider is "ollama" or "openai_compatible";
        if (!allowsLocalTarget && isLocalOrPrivateTarget)
        {
            error = "Provedores em nuvem não podem apontar para endereços locais ou redes privadas.";
            return false;
        }

        if (string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) &&
            !(allowsLocalTarget && isLocalOrPrivateTarget))
        {
            error = "Endereços remotos exigem https:// (http:// é permitido apenas para Ollama ou endpoint OpenAI-compatível local/privado).";
            return false;
        }

        validatedUrl = trimmedUrl;
        return true;
    }

    private static bool IsLocalHostname(string host) =>
        host is "localhost" or "ip6-localhost" or "ip6-loopback"
        || host.EndsWith(".localhost", StringComparison.Ordinal)
        || host.EndsWith(".local", StringComparison.Ordinal)
        || host.EndsWith(".internal", StringComparison.Ordinal)
        || !host.Contains('.');

    private static bool IsLinkLocalOrUnspecified(IPAddress ip)
    {
        if (ip.Equals(IPAddress.Any) || ip.Equals(IPAddress.IPv6Any))
        {
            return true;
        }

        if (ip.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = ip.GetAddressBytes();
            // 169.254.0.0/16 (link-local / cloud metadata) or 0.0.0.0/8
            return b[0] == 0 || (b[0] == 169 && b[1] == 254);
        }

        if (ip.AddressFamily == AddressFamily.InterNetworkV6)
        {
            var b = ip.GetAddressBytes();
            // fe80::/10 link-local
            return b[0] == 0xFE && (b[1] & 0xC0) == 0x80;
        }

        return false;
    }

    private static bool IsLoopbackOrPrivate(IPAddress ip)
    {
        if (IPAddress.IsLoopback(ip))
        {
            return true;
        }

        if (ip.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = ip.GetAddressBytes();
            return b[0] == 127
                || b[0] == 10
                || (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
                || (b[0] == 192 && b[1] == 168)
                || (b[0] == 100 && b[1] >= 64 && b[1] <= 127);
        }

        if (ip.AddressFamily == AddressFamily.InterNetworkV6)
        {
            var b = ip.GetAddressBytes();
            // fc00::/7 (Unique Local Addresses)
            return (b[0] & 0xFE) == 0xFC;
        }

        return false;
    }

    [GeneratedRegex(@"\b(?:19|20)\d{2}-(?:0[1-9]|1[0-2])\b", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex IsoMonthRegex();

    [GeneratedRegex(@"(?<![\d/])(0?[1-9]|1[0-2])/((?:19|20)\d{2})\b", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex BrMonthYearRegex();

    [GeneratedRegex(@"\b(?:19|20)\d{2}\b", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
    private static partial Regex YearRegex();

    private sealed record ProviderConfigRow(
        string Provider,
        string Model,
        string? BaseUrl,
        byte[]? ApiKeyEnc,
        DateTimeOffset UpdatedAt);

    private sealed record ChatMessageRow(
        Guid Id,
        string Role,
        string Content,
        string? PeriodUsed,
        string? NumbersCitedJson,
        string ProviderUsed,
        DateTimeOffset CreatedAt);

    private sealed record SuggestionRow(
        Guid Id,
        Guid TransactionId,
        string MerchantNormalized,
        string? SuggestedCategory,
        string? SuggestedEssentiality,
        decimal Confidence,
        string Explanation,
        string Status,
        DateTimeOffset CreatedAt,
        DateTimeOffset? DecidedAt);
}
