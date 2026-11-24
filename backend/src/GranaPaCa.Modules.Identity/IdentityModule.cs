using System.Security.Claims;
using GranaPaCa.Modules.Identity.Contracts;
using GranaPaCa.Modules.Keyring.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace GranaPaCa.Modules.Identity;

public static class IdentityModule
{
    public static IServiceCollection AddIdentityModule(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services.AddSingleton<SessionService>();
        services.AddSingleton<IAuthTokenValidator>(sp => sp.GetRequiredService<SessionService>());
        services.AddSingleton(sp => new IdentityService(
            sp.GetRequiredService<NpgsqlDataSource>(),
            sp.GetRequiredService<IEnvelopeEncryptor>(),
            sp.GetRequiredService<SessionService>(),
            sp.GetService<IConfiguration>() ?? configuration));
        services.AddSingleton<IIdentityPurgeService>(sp => sp.GetRequiredService<IdentityService>());

        return services;
    }

    public static IEndpointRouteBuilder MapIdentityEndpoints(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet("/api/v1/server-info", async (
            IdentityService identityService,
            CancellationToken cancellationToken) =>
            Results.Ok(await identityService.GetServerInfoAsync(cancellationToken)))
            .AllowAnonymous();

        var auth = endpoints.MapGroup("/api/v1/auth");

        auth.MapPost("/setup", (
            SetupRequest? request,
            IdentityService identityService,
            CancellationToken cancellationToken) =>
            identityService.SetupOwnerAsync(request, cancellationToken))
            .AllowAnonymous();

        auth.MapPost("/login", (
            LoginRequest? request,
            HttpContext httpContext,
            IdentityService identityService,
            CancellationToken cancellationToken) =>
            identityService.LoginAsync(request, GetClientIp(httpContext), cancellationToken))
            .AllowAnonymous();

        auth.MapPost("/totp/setup", (
            TotpSetupRequest? request,
            IdentityService identityService,
            CancellationToken cancellationToken) =>
            identityService.BeginTotpSetupAsync(request, cancellationToken))
            .AllowAnonymous();

        auth.MapPost("/totp/confirm", (
            TotpConfirmRequest? request,
            HttpContext httpContext,
            IdentityService identityService,
            CancellationToken cancellationToken) =>
            identityService.ConfirmTotpAsync(request, GetClientIp(httpContext), cancellationToken))
            .AllowAnonymous();

        auth.MapPost("/refresh", (
            RefreshRequest? request,
            IdentityService identityService,
            CancellationToken cancellationToken) =>
            identityService.RefreshAsync(request, cancellationToken))
            .AllowAnonymous();

        auth.MapPost("/logout", async (
            ClaimsPrincipal user,
            SessionService sessionService,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetCallerSession(user, out var ownerId, out var sessionId))
            {
                return Results.Unauthorized();
            }

            await sessionService.RevokeSessionAsync(ownerId, sessionId, cancellationToken);
            return Results.NoContent();
        }).RequireAuthorization();

        auth.MapGet("/sessions", async (
            ClaimsPrincipal user,
            SessionService sessionService,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetCallerSession(user, out var ownerId, out var sessionId))
            {
                return Results.Unauthorized();
            }

            var sessions = await sessionService.ListActiveSessionsAsync(ownerId, sessionId, cancellationToken);
            return Results.Ok(sessions);
        }).RequireAuthorization();

        auth.MapDelete("/sessions/{sessionId:guid}", async (
            Guid sessionId,
            ClaimsPrincipal user,
            SessionService sessionService,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetCallerOwnerId(user, out var ownerId))
            {
                return Results.Unauthorized();
            }

            var revoked = await sessionService.RevokeSessionAsync(ownerId, sessionId, cancellationToken);
            return revoked
                ? Results.NoContent()
                : Results.NotFound(new ErrorResponse("session_not_found", "Sessão não encontrada."));
        }).RequireAuthorization();

        return endpoints;
    }

    private static string GetClientIp(HttpContext httpContext) =>
        httpContext.Connection.RemoteIpAddress?.ToString() ?? "local";

    private static bool TryGetCallerOwnerId(ClaimsPrincipal user, out Guid ownerId) =>
        Guid.TryParse(user.FindFirstValue(IdentityClaimTypes.OwnerId), out ownerId) && ownerId != Guid.Empty;

    private static bool TryGetCallerSession(
        ClaimsPrincipal user,
        out Guid ownerId,
        out Guid sessionId)
    {
        sessionId = Guid.Empty;
        return TryGetCallerOwnerId(user, out ownerId)
            && Guid.TryParse(user.FindFirstValue(IdentityClaimTypes.SessionId), out sessionId)
            && sessionId != Guid.Empty;
    }
}

internal sealed record ServerInfoResponse(
    string App,
    string Version,
    int ApiVersion,
    bool OwnerConfigured,
    string ProviderMode);

internal sealed record SetupRequest(
    string? Email,
    string? DisplayName,
    string? Password,
    string? HouseholdName = null,
    string? Timezone = null);

internal sealed record SetupResponse(
    Guid OwnerId,
    Guid HouseholdId,
    string Email,
    string DisplayName);

internal sealed record LoginRequest(
    string? Email,
    string? Password,
    string? TotpCode = null,
    string? RecoveryCode = null,
    string? DeviceName = null);

internal sealed record PendingTotpLoginResponse(
    string Status,
    string PendingToken);

internal sealed record OwnerSummary(
    Guid Id,
    Guid HouseholdId,
    string Email,
    string DisplayName);

internal sealed record AuthenticatedLoginResponse(
    string Status,
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    Guid SessionId,
    OwnerSummary Owner);

internal sealed record TotpSetupRequest(string? PendingToken);

internal sealed record TotpSetupResponse(
    string ManualKey,
    string OtpauthUri);

internal sealed record TotpConfirmRequest(
    string? PendingToken,
    string? TotpCode);

internal sealed record TotpConfirmResponse(
    string Status,
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    Guid SessionId,
    OwnerSummary Owner,
    IReadOnlyList<string> RecoveryCodes);

internal sealed record RefreshRequest(string? RefreshToken);

internal sealed record SessionListItem(
    Guid Id,
    string DeviceName,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt,
    bool IsCurrent);

internal sealed record ErrorResponse(
    string Error,
    string Message);
