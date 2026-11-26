using Npgsql;

namespace GranaPaCa.Modules.Alerts.Contracts;

/// <summary>
/// Permanently deletes all inbox alerts for a household (RF-07).
/// </summary>
public interface IAlertsPurgeService
{
    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
