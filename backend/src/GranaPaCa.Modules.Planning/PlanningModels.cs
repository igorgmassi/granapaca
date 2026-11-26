using System.Globalization;
using Microsoft.Extensions.Configuration;

namespace GranaPaCa.Modules.Planning;

internal static class PlanningFormatting
{
    private const string DefaultTimeZoneId = "America/Sao_Paulo";
    private static readonly CultureInfo PtBr = CultureInfo.GetCultureInfo("pt-BR");

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

    public static readonly HashSet<string> AllowedCategories = new(StringComparer.Ordinal)
    {
        "housing",
        "food",
        "transport",
        "health",
        "education",
        "leisure",
        "shopping",
        "services",
        "other"
    };

    public static string GetCategoryLabel(string category) =>
        CategoryLabels.TryGetValue(category, out var label) ? label : category;

    public static bool TryNormalizeCategory(string? raw, out string normalized)
    {
        if (!string.IsNullOrWhiteSpace(raw))
        {
            var candidate = raw.Trim().ToLowerInvariant();
            if (AllowedCategories.Contains(candidate))
            {
                normalized = candidate;
                return true;
            }
        }

        normalized = string.Empty;
        return false;
    }

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

    public static bool TryParseMonth(string? month, TimeZoneInfo timeZone, out DateOnly monthStart, out string monthLabel)
    {
        if (string.IsNullOrWhiteSpace(month))
        {
            var today = TodayInTimeZone(timeZone);
            monthStart = new DateOnly(today.Year, today.Month, 1);
            monthLabel = monthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);
            return true;
        }

        if (DateOnly.TryParseExact(
            month.Trim() + "-01",
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out monthStart))
        {
            monthLabel = monthStart.ToString("yyyy-MM", CultureInfo.InvariantCulture);
            return true;
        }

        monthStart = default;
        monthLabel = string.Empty;
        return false;
    }
}

internal sealed record Rule503020Dto(
    long NeedsCents,
    long WantsCents,
    long SavingsCents,
    long BaseCents,
    long UnclassifiedSpentCents,
    decimal NeedsPercent,
    decimal WantsPercent,
    decimal SavingsPercent,
    decimal TargetNeedsPercent,
    decimal TargetWantsPercent,
    decimal TargetSavingsPercent);

internal sealed record MonthProjectionDto(
    string Month,
    long SpentCents,
    long RegularSpentCents,
    long AtypicalSpentCents,
    long DailyAverageCents,
    long ProjectedMonthEndSpentCents,
    long ProjectedLeftoverCents,
    int ElapsedDays,
    int DaysInMonth,
    int RemainingDays,
    bool IsClosedMonth);

internal sealed record CategoryDeltaDto(
    string Category,
    string Label,
    long CurrentSpentCents,
    long PreviousSpentCents,
    long DeltaCents,
    decimal DeltaPercent);

internal sealed record MonthOverMonthDto(
    string CurrentMonth,
    string PreviousMonth,
    long CurrentSpentCents,
    long PreviousSpentCents,
    long SpentDeltaCents,
    decimal SpentDeltaPercent,
    long CurrentReceivedCents,
    long PreviousReceivedCents,
    long ReceivedDeltaCents,
    long CurrentLeftoverCents,
    long PreviousLeftoverCents,
    long LeftoverDeltaCents,
    IReadOnlyList<CategoryDeltaDto> CategoryDeltas);

internal sealed record CalendarHeatmapDayDto(
    DateOnly Date,
    long SpentCents,
    int Intensity);

internal sealed record DetectedSubscriptionDto(
    string MerchantNormalized,
    string DisplayName,
    string Category,
    string CategoryLabel,
    long EstimatedMonthlyCents,
    long EstimatedAnnualCents,
    int Occurrences,
    int MonthsDetected,
    DateOnly LastChargedOn,
    int AverageDayOfMonth,
    bool PossiblyUnused,
    string? UnusedReason);

internal sealed record BudgetDto(
    Guid Id,
    string Category,
    string CategoryLabel,
    long MonthLimitCents,
    int AlertThresholdPercent,
    bool IsActive,
    long SpentCents,
    long RemainingCents,
    decimal UsedPercent,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

internal sealed record BudgetsListResponse(
    string Month,
    IReadOnlyList<BudgetDto> Items);

internal sealed record UpsertBudgetRequest(
    string? Category,
    long MonthLimitCents,
    int? AlertThresholdPercent,
    bool? IsActive);

internal sealed record GoalDto(
    Guid Id,
    string Name,
    long TargetCents,
    long CurrentCents,
    long RemainingCents,
    decimal ProgressPercent,
    DateOnly? TargetDate,
    long? SuggestedMonthlyCents,
    bool IsCompleted,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

internal sealed record GoalsListResponse(IReadOnlyList<GoalDto> Items);

internal sealed record CreateGoalRequest(
    string? Name,
    long TargetCents,
    long? CurrentCents,
    DateOnly? TargetDate);

internal sealed record UpdateGoalRequest(
    string? Name,
    long? TargetCents,
    long? CurrentCents,
    long? AddCents,
    DateOnly? TargetDate,
    bool? ClearTargetDate,
    bool? IsCompleted);

internal sealed record SpendingAlertRuleDto(
    Guid Id,
    string Expression,
    string? Category,
    string? CategoryLabel,
    string? MerchantKeyword,
    long LimitCents,
    bool IsActive,
    long CurrentSpentCents,
    bool IsTriggered,
    DateTimeOffset CreatedAt);

internal sealed record SpendingAlertRulesListResponse(
    string Month,
    IReadOnlyList<SpendingAlertRuleDto> Items);

internal sealed record CreateSpendingAlertRuleRequest(
    string? Expression,
    string? Category,
    string? MerchantKeyword,
    long? LimitCents);

internal sealed record EvaluateAlertsRequest(string? Month);

internal sealed record TriggeredPlanningAlertDto(
    string DedupKey,
    string Kind,
    string Severity,
    string Title,
    string Message,
    long SpentCents,
    long LimitCents);

internal sealed record EvaluateAlertsResponse(
    string Month,
    int BudgetsEvaluated,
    int RulesEvaluated,
    int AlertsRaised,
    int AlertsResolved,
    IReadOnlyList<TriggeredPlanningAlertDto> TriggeredAlerts);

internal sealed record PlanningOverviewResponse(
    string Month,
    Rule503020Dto Rule503020,
    MonthProjectionDto Projection,
    MonthOverMonthDto MonthOverMonth,
    IReadOnlyList<CalendarHeatmapDayDto> CalendarHeatmap,
    IReadOnlyList<BudgetDto> Budgets,
    IReadOnlyList<GoalDto> Goals,
    IReadOnlyList<DetectedSubscriptionDto> Subscriptions,
    long SubscriptionsMonthlyTotalCents,
    long SubscriptionsAnnualTotalCents,
    IReadOnlyList<SpendingAlertRuleDto> AlertRules);
