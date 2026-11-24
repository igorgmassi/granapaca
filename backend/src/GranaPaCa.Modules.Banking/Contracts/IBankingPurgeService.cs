using Npgsql;

namespace GranaPaCa.Modules.Banking.Contracts;

/// <summary>
/// Permanently deletes all banking data for a household under granapaca.purge = 'on' (RF-07, ADR-012).
/// </summary>
public interface IBankingPurgeService
{
    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
