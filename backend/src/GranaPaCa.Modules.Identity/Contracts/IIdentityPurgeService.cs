using Npgsql;

namespace GranaPaCa.Modules.Identity.Contracts;

public enum OwnerCredentialVerificationStatus
{
    Valid,
    InvalidCredentials,
    RateLimited,
}

/// <summary>
/// Verifies owner credentials and deletes all identity records for a household during full account purge (RF-07).
/// </summary>
public interface IIdentityPurgeService
{
    Task<OwnerCredentialVerificationStatus> VerifyOwnerCredentialsAsync(
        Guid ownerId,
        Guid householdId,
        string password,
        string totpCode,
        string clientIp,
        CancellationToken cancellationToken = default);

    Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}
