using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Alerts;

internal sealed class AlertsPurgeService : IAlertsPurgeService
{
    public Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        return connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM alerts.alert WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));
    }
}
