using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace GranaPaCa.Modules.Assistant;

internal static class AssistantFormatting
{
    private const string DefaultTimeZoneId = "America/Sao_Paulo";
    private static readonly CultureInfo PtBr = CultureInfo.GetCultureInfo("pt-BR");

    public static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);

    public static readonly HashSet<string> AllowedProviders = new(StringComparer.Ordinal)
    {
        "none",
        "openai",
        "anthropic",
        "google",
        "ollama",
        "groq",
        "openrouter",
        "openai_compatible"
    };

    public static readonly IReadOnlyDictionary<string, string> CategoryLabels =
        new Dictionary<string, string>(StringComparer.Ordinal)
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

    public static string GetCategoryLabel(string category) =>
        CategoryLabels.TryGetValue(category, out var label) ? label : category;

    public static string FormatBrl(long cents)
    {
        var value = cents / 100m;
        return string.Format(PtBr, "R$ {0:N2}", value);
    }

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
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(DefaultTimeZoneId);
            }
            catch (TimeZoneNotFoundException)
            {
                return TimeZoneInfo.Utc;
            }
        }
    }

    public static DateOnly TodayInTimeZone(TimeZoneInfo timeZone)
    {
        var localNow = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, timeZone);
        return DateOnly.FromDateTime(localNow.Date);
    }
}

internal sealed record ProviderConfigDto(
    string Provider,
    string Model,
    string? BaseUrl,
    bool HasApiKey,
    DateTimeOffset? UpdatedAt);

internal sealed record UpdateProviderConfigRequest(
    string? Provider,
    string? Model,
    string? BaseUrl,
    string? ApiKey,
    bool? ClearApiKey);

internal sealed record CitedNumberDto(
    string Label,
    long AmountCents,
    string Formatted);

internal sealed record ChatMessageDto(
    Guid Id,
    string Role,
    string Content,
    string? PeriodUsed,
    IReadOnlyList<CitedNumberDto> NumbersCited,
    string ProviderUsed,
    DateTimeOffset CreatedAt);

internal sealed record ChatHistoryResponse(
    IReadOnlyList<ChatMessageDto> Items);

internal sealed record ChatRequest(
    string? Message,
    string? Month);

internal sealed record ChatResponse(
    Guid MessageId,
    string Content,
    string PeriodUsed,
    IReadOnlyList<CitedNumberDto> NumbersCited,
    string ProviderUsed,
    bool Pseudonymized,
    DateTimeOffset CreatedAt);

internal sealed record CategorizationSuggestionDto(
    Guid Id,
    Guid TransactionId,
    string MerchantNormalized,
    string? SuggestedCategory,
    string? SuggestedCategoryLabel,
    string? SuggestedEssentiality,
    decimal Confidence,
    bool IsLowConfidence,
    string Explanation,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DecidedAt);

internal sealed record GenerateSuggestionsResponse(
    int GeneratedCount,
    int PendingCount,
    IReadOnlyList<CategorizationSuggestionDto> Items);

internal sealed record SuggestionsListResponse(
    int TotalCount,
    int LowConfidenceCount,
    IReadOnlyList<CategorizationSuggestionDto> Items);

internal sealed record DecideSuggestionRequest(string? Action);

internal sealed record RuleConfirmationPayloadDto(
    string Name,
    string MatchDescriptionContains,
    string? SetCategory,
    string? SetEssentiality,
    int Priority);

internal sealed record DecideSuggestionResponse(
    CategorizationSuggestionDto Suggestion,
    RuleConfirmationPayloadDto? RulePayload);

internal sealed record ProviderPresetDto(
    string Provider,
    string DisplayName,
    string Description,
    string CostTier,
    string CostLabel,
    string SetupEffort,
    string SetupEffortLabel,
    string RecommendedModel,
    IReadOnlyList<string> AlternativeModels,
    string? DefaultBaseUrl,
    bool RequiresApiKey,
    bool IsLocal,
    bool PseudonymizationActive,
    string PrivacyNote,
    string? SetupUrl);

internal sealed record ProviderPresetsResponse(
    IReadOnlyList<ProviderPresetDto> Items);

internal static class AssistantProviderPresets
{
    public const string DefaultGoogleBaseUrl = "https://generativelanguage.googleapis.com/v1beta";
    public const string DefaultGoogleModel = "gemini-2.5-flash-lite";

    public const string DefaultGroqBaseUrl = "https://api.groq.com/openai/v1/";
    public const string DefaultGroqModel = "llama-3.3-70b-versatile";

    public const string DefaultOpenRouterBaseUrl = "https://openrouter.ai/api/v1/";
    public const string DefaultOpenRouterModel = "meta-llama/llama-3.3-70b-instruct:free";

    public const string DefaultOllamaBaseUrl = "http://host.docker.internal:11434/";
    public const string DefaultOllamaModel = "qwen2.5:7b";

    public const string DefaultOpenAiCompatibleBaseUrl = "http://host.docker.internal:1234/v1/";
    public const string DefaultOpenAiCompatibleModel = "local-model";

    public const string DefaultOpenAiBaseUrl = "https://api.openai.com/v1/";
    public const string DefaultOpenAiModel = "gpt-4o-mini";

    public const string DefaultAnthropicBaseUrl = "https://api.anthropic.com/v1/";
    public const string DefaultAnthropicModel = "claude-3-5-haiku-latest";

    public static readonly IReadOnlyList<ProviderPresetDto> All =
    [
        new(
            Provider: "none",
            DisplayName: "Paçoca local (nativo)",
            Description: "Motor determinístico local embutido no GranaPaCá. Responde sobre gastos por mês, categorias, estabelecimentos, maiores despesas, regra 50/30/20, assinaturas, projeções e comparações sem precisar de conta externa.",
            CostTier: "free",
            CostLabel: "Grátis (sem conta)",
            SetupEffort: "none",
            SetupEffortLabel: "Zero configuração",
            RecommendedModel: string.Empty,
            AlternativeModels: [],
            DefaultBaseUrl: null,
            RequiresApiKey: false,
            IsLocal: true,
            PseudonymizationActive: false,
            PrivacyNote: "100% privado e offline: nenhum dado sai da sua instância nem requer internet.",
            SetupUrl: null),
        new(
            Provider: "google",
            DisplayName: "Google Gemini (Google AI Studio)",
            Description: "Camada gratuita sem cartão de crédito pelo Google AI Studio, com ótimo desempenho em português do Brasil.",
            CostTier: "free_tier",
            CostLabel: "Camada gratuita sem cartão",
            SetupEffort: "low",
            SetupEffortLabel: "Fácil (1 chave gratuita)",
            RecommendedModel: DefaultGoogleModel,
            AlternativeModels: ["gemini-2.5-flash"],
            DefaultBaseUrl: DefaultGoogleBaseUrl,
            RequiresApiKey: true,
            IsLocal: false,
            PseudonymizationActive: true,
            PrivacyNote: "Pseudonimização obrigatória ativa: CPF, CNPJ, e-mail, telefone, contas, bancos e estabelecimentos são ocultados antes do envio.",
            SetupUrl: "https://aistudio.google.com/apikey"),
        new(
            Provider: "groq",
            DisplayName: "Groq",
            Description: "Camada gratuita rápida com modelos open-weights (Llama 3.3 70B) via API compatível com OpenAI.",
            CostTier: "free_tier",
            CostLabel: "Camada gratuita rápida",
            SetupEffort: "low",
            SetupEffortLabel: "Fácil (1 chave gratuita)",
            RecommendedModel: DefaultGroqModel,
            AlternativeModels: ["llama-3.1-8b-instant"],
            DefaultBaseUrl: DefaultGroqBaseUrl,
            RequiresApiKey: true,
            IsLocal: false,
            PseudonymizationActive: true,
            PrivacyNote: "Pseudonimização obrigatória ativa: somente resumo financeiro minimizado e tokens genéricos são enviados.",
            SetupUrl: "https://console.groq.com/keys"),
        new(
            Provider: "openrouter",
            DisplayName: "OpenRouter",
            Description: "Acesso unificado a modelos open-weights gratuitos (sufixo :free) e opções de baixo custo via API compatível com OpenAI.",
            CostTier: "free_tier",
            CostLabel: "Modelos :free gratuitos / baixo custo",
            SetupEffort: "low",
            SetupEffortLabel: "Fácil (1 chave gratuita)",
            RecommendedModel: DefaultOpenRouterModel,
            AlternativeModels: ["google/gemma-3-27b-it:free", "qwen/qwen-2.5-72b-instruct:free"],
            DefaultBaseUrl: DefaultOpenRouterBaseUrl,
            RequiresApiKey: true,
            IsLocal: false,
            PseudonymizationActive: true,
            PrivacyNote: "Pseudonimização obrigatória ativa: dados pessoais e nomes reais nunca saem da sua instância.",
            SetupUrl: "https://openrouter.ai/keys"),
        new(
            Provider: "ollama",
            DisplayName: "Ollama local",
            Description: "Grátis e 100% local na própria máquina ou servidor doméstico com modelos open-weights, sem nuvem.",
            CostTier: "free",
            CostLabel: "Grátis (100% local)",
            SetupEffort: "medium",
            SetupEffortLabel: "Moderado (instalar Ollama local)",
            RecommendedModel: DefaultOllamaModel,
            AlternativeModels: ["llama3.2"],
            DefaultBaseUrl: DefaultOllamaBaseUrl,
            RequiresApiKey: false,
            IsLocal: true,
            PseudonymizationActive: true,
            PrivacyNote: "100% local na sua rede, sem envio à nuvem; ainda assim aplicamos minimização e pseudonimização.",
            SetupUrl: "https://ollama.com/"),
        new(
            Provider: "openai_compatible",
            DisplayName: "Outro endpoint compatível com OpenAI",
            Description: "Conecte qualquer servidor compatível com /chat/completions, como LM Studio, llama.cpp, vLLM ou provedor próprio.",
            CostTier: "flexible",
            CostLabel: "Grátis (local) ou conforme o provedor",
            SetupEffort: "medium",
            SetupEffortLabel: "Moderado (informar URL base e modelo)",
            RecommendedModel: DefaultOpenAiCompatibleModel,
            AlternativeModels: [],
            DefaultBaseUrl: DefaultOpenAiCompatibleBaseUrl,
            RequiresApiKey: false,
            IsLocal: false,
            PseudonymizationActive: true,
            PrivacyNote: "Pseudonimização obrigatória ativa antes de enviar qualquer contexto ao endpoint configurado.",
            SetupUrl: null),
        new(
            Provider: "openai",
            DisplayName: "OpenAI (BYOK)",
            Description: "Modelos da OpenAI usando sua própria chave de API com cobrança por uso.",
            CostTier: "paid",
            CostLabel: "Pago por uso (BYOK)",
            SetupEffort: "low",
            SetupEffortLabel: "Fácil (chave com créditos)",
            RecommendedModel: DefaultOpenAiModel,
            AlternativeModels: ["gpt-4.1-mini"],
            DefaultBaseUrl: DefaultOpenAiBaseUrl,
            RequiresApiKey: true,
            IsLocal: false,
            PseudonymizationActive: true,
            PrivacyNote: "Pseudonimização obrigatória ativa: somente resumo financeiro minimizado e tokens genéricos são enviados.",
            SetupUrl: "https://platform.openai.com/api-keys"),
        new(
            Provider: "anthropic",
            DisplayName: "Anthropic (BYOK)",
            Description: "Modelos da Anthropic usando sua própria chave de API com cobrança por uso.",
            CostTier: "paid",
            CostLabel: "Pago por uso (BYOK)",
            SetupEffort: "low",
            SetupEffortLabel: "Fácil (chave com créditos)",
            RecommendedModel: DefaultAnthropicModel,
            AlternativeModels: [],
            DefaultBaseUrl: DefaultAnthropicBaseUrl,
            RequiresApiKey: true,
            IsLocal: false,
            PseudonymizationActive: true,
            PrivacyNote: "Pseudonimização obrigatória ativa: somente resumo financeiro minimizado e tokens genéricos são enviados.",
            SetupUrl: "https://console.anthropic.com/settings/keys")
    ];
}
