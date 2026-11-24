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
        "ollama"
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
