using System.Security.Claims;
using System.Text.Encodings.Web;
using GranaPaCa.Modules.Identity.Contracts;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace GranaPaCa.Api;

internal sealed class OpaqueBearerAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    IAuthTokenValidator tokenValidator)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "OpaqueBearer";

    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue("Authorization", out var headerValues))
        {
            return AuthenticateResult.NoResult();
        }

        var header = headerValues.ToString();
        const string prefix = "Bearer ";
        if (!header.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return AuthenticateResult.NoResult();
        }

        var token = header[prefix.Length..].Trim();
        if (string.IsNullOrEmpty(token))
        {
            return AuthenticateResult.Fail("Missing bearer token.");
        }

        var session = await tokenValidator.ValidateAccessTokenAsync(token, Context.RequestAborted);
        if (session is null)
        {
            return AuthenticateResult.Fail("Invalid or expired access token.");
        }

        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, session.OwnerId.ToString("D")),
            new Claim(IdentityClaimTypes.OwnerId, session.OwnerId.ToString("D")),
            new Claim(IdentityClaimTypes.HouseholdId, session.HouseholdId.ToString("D")),
            new Claim(IdentityClaimTypes.SessionId, session.SessionId.ToString("D")),
            new Claim(IdentityClaimTypes.DeviceName, session.DeviceName),
            new Claim(ClaimTypes.Email, session.Email),
            new Claim(ClaimTypes.Name, session.DisplayName),
        };

        var identity = new ClaimsIdentity(claims, SchemeName);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, SchemeName);

        return AuthenticateResult.Success(ticket);
    }
}
