using System.Security.Claims;
using GranaPaCa.Modules.Keyring.Contracts;
using GranaPaCa.Modules.Receipts.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GranaPaCa.Modules.Receipts;

public static class ReceiptsModule
{
    public static IServiceCollection AddReceiptsModule(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services.AddSingleton(sp => new EncryptedReceiptFileStore(
            sp.GetRequiredService<IEnvelopeEncryptor>(),
            sp.GetService<IConfiguration>() ?? configuration));

        services.AddScoped<ReceiptsService>();
        services.AddScoped<IReceiptsPurgeService>(sp => sp.GetRequiredService<ReceiptsService>());
        return services;
    }

    public static IEndpointRouteBuilder MapReceiptsEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/receipts").RequireAuthorization();

        group.MapGet("/consent", async (
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.GetConsentAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        group.MapPut("/consent", async (
            UpdateReceiptConsentRequest? request,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            if (request is null)
            {
                return Results.BadRequest(new { error = "Informe as preferências de consentimento." });
            }

            var data = await service.SaveConsentAsync(householdId, request, cancellationToken);
            return Results.Ok(data);
        });

        group.MapGet("", async (
            Guid? transactionId,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.ListReceiptsAsync(householdId, transactionId, cancellationToken);
            return Results.Ok(data);
        });

        group.MapPost("", async (
            UploadReceiptRequest? request,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.UploadReceiptAsync(householdId, request, cancellationToken);
            return ok
                ? Results.Created($"/api/v1/receipts/{data!.Id}", data)
                : Results.BadRequest(new { error });
        });

        group.MapGet("/{id:guid}/download", async (
            Guid id,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (found, bytes, contentType, fileName) = await service.DownloadReceiptAsync(
                householdId,
                id,
                cancellationToken);

            return found && bytes is not null
                ? Results.File(bytes, contentType ?? "application/octet-stream", fileName)
                : Results.NotFound();
        });

        group.MapDelete("/{id:guid}", async (
            Guid id,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var deleted = await service.DeleteReceiptAsync(householdId, id, cancellationToken);
            return deleted ? Results.NoContent() : Results.NotFound();
        });

        group.MapPost("/nfce/parse", async (
            ParseNfceRequest? request,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.ParseNfceAsync(householdId, request, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapPost("/{id:guid}/apply-splits", async (
            Guid id,
            ApplyReceiptSplitsRequest? request,
            ClaimsPrincipal user,
            ReceiptsService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (statusCode, error, data) = await service.ApplySplitsAsync(
                householdId,
                id,
                request,
                cancellationToken);

            return statusCode switch
            {
                200 => Results.Ok(data),
                404 => Results.NotFound(),
                _ => Results.BadRequest(new { error })
            };
        });

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId) && householdId != Guid.Empty;
    }
}
