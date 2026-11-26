namespace GranaPaCa.Modules.Identity.Contracts;

public sealed record AuthenticatedSession(
    Guid OwnerId,
    Guid HouseholdId,
    Guid SessionId,
    string Email,
    string DisplayName,
    string DeviceName);

public interface IAuthTokenValidator
{
    Task<AuthenticatedSession?> ValidateAccessTokenAsync(
        string accessToken,
        CancellationToken cancellationToken = default);
}

public static class IdentityClaimTypes
{
    public const string OwnerId = "owner_id";
    public const string HouseholdId = "household_id";
    public const string SessionId = "session_id";
    public const string DeviceName = "device_name";
}
