using Dapper;
using GranaPaCa.Modules.Categorization.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Categorization;

internal sealed class CategorizationPurgeService : ICategorizationPurgeService
{
    public async Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM categorization.rule WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM categorization.profile_config WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));
    }
}
