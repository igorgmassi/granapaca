namespace GranaPaCa.Modules.Banking.Contracts;

public sealed record SyncSummary(
    int ConnectionsProcessed,
    int AccountsSynced,
    int TransactionsInserted,
    int TransactionsVersioned,
    int TransactionsRemoved,
    int TransfersLinked,
    int FailedConnections);

public interface IBankingSyncTrigger
{
    Task<SyncSummary> SyncHouseholdAsync(
        Guid householdId,
        CancellationToken cancellationToken = default);
}
