using Npgsql;

namespace GranaPaCa.Modules.Receipts.Contracts;

public interface IReceiptsPurgeService
{
    Task<IReadOnlyList<string>> PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);

    void DeletePurgedFiles(Guid householdId, IReadOnlyList<string> storageRelPaths);
}
