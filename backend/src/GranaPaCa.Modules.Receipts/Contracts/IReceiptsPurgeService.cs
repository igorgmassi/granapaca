using Npgsql;

namespace GranaPaCa.Modules.Receipts.Contracts;

public interface IReceiptsPurgeService
{
    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
