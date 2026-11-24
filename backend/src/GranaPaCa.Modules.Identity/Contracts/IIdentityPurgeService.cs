using Npgsql;

namespace GranaPaCa.Modules.Identity.Contracts;

/// <summary>
/// Verifies owner credentials and deletes all identity records for a household during full account purge (RF-07).
/// </summary>
public interface IIdentityPurgeService
{
    Task<bool> VerifyOwnerCredentialsAsync(
        Guid ownerId,
        Guid householdId,
        string password,
        string totpCode,
        CancellationToken cancellationToken = default);

    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
