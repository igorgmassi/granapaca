using Npgsql;

namespace GranaPaCa.Modules.Categorization.Contracts;

/// <summary>
/// Permanently deletes all categorization rules and profile configuration for a household (RF-07).
/// </summary>
public interface ICategorizationPurgeService
{
    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
