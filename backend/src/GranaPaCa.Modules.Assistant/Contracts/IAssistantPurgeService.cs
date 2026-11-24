using Npgsql;

namespace GranaPaCa.Modules.Assistant.Contracts;

public interface IAssistantPurgeService
{
    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
