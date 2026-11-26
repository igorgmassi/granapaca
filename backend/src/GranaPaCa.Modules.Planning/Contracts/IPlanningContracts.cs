using Npgsql;

namespace GranaPaCa.Modules.Planning.Contracts;

public sealed record PlanningSnapshot(
    string Month,
    long ProjectedMonthEndSpentCents,
    long NeedsCents,
    long WantsCents,
    long SavingsCents,
    int ActiveBudgetsCount,
    int ActiveGoalsCount,
    int DetectedSubscriptionsCount);

public interface IPlanningReader
{
    Task<PlanningSnapshot> GetSnapshotAsync(
        Guid householdId,
        DateOnly monthStart,
        CancellationToken cancellationToken = default);
}

public interface IPlanningPurgeService
{
    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
