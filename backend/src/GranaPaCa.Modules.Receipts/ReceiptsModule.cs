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
        var group = endpoints.MapGroup("/api/v1/receipts")
            .RequireAuthorization()
            .WithTags("Receipts");

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
        })
        .WithName("GetReceiptConsent")
        .Produces<ReceiptConsentDto>(StatusCodes.Status200OK)
        .Produces(StatusCodes.Status401Unauthorized);

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
                return Results.Problem(
                    title: "Preferências de consentimento inválidas",
                    detail: "Informe as preferências de consentimento.",
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_consent_request" });
            }

            var data = await service.SaveConsentAsync(householdId, request, cancellationToken);
            return Results.Ok(data);
        })
        .WithName("SaveReceiptConsent")
        .Produces<ReceiptConsentDto>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
        })
        .WithName("ListReceipts")
        .Produces<ReceiptsListResponse>(StatusCodes.Status200OK)
        .Produces(StatusCodes.Status401Unauthorized);

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
                : Results.Problem(
                    title: "Erro ao enviar comprovante",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_receipt_upload" });
        })
        .WithName("UploadReceipt")
        .Produces<ReceiptDto>(StatusCodes.Status201Created)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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

            if (!found || bytes is null)
            {
                return Results.NotFound();
            }

            var safeContentType = ReceiptsService.TryNormalizeAllowedContentType(contentType, out var normalized, out _)
                ? normalized
                : "application/octet-stream";

            return Results.File(bytes, safeContentType, fileName);
        })
        .WithName("DownloadReceipt")
        .Produces(StatusCodes.Status200OK)
        .Produces(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

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
        })
        .WithName("DeleteReceipt")
        .Produces(StatusCodes.Status204NoContent)
        .Produces(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

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

            var (statusCode, errorCode, error, data) = await service.ParseNfceAsync(householdId, request, cancellationToken);
            return statusCode switch
            {
                StatusCodes.Status200OK => Results.Ok(data),
                StatusCodes.Status403Forbidden => Results.Problem(
                    title: "Consentimento necessário",
                    detail: error,
                    statusCode: StatusCodes.Status403Forbidden,
                    extensions: new Dictionary<string, object?> { ["code"] = errorCode ?? "receipt_item_consent_required" }),
                _ => Results.Problem(
                    title: "Erro ao interpretar NFC-e",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = errorCode ?? "invalid_nfce" })
            };
        })
        .WithName("ParseNfce")
        .Produces<ParseNfceResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status403Forbidden)
        .Produces(StatusCodes.Status401Unauthorized);

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
                404 => Results.Problem(
                    title: "Comprovante não encontrado",
                    detail: error ?? "Comprovante não encontrado.",
                    statusCode: StatusCodes.Status404NotFound,
                    extensions: new Dictionary<string, object?> { ["code"] = "receipt_not_found" }),
                _ => Results.Problem(
                    title: "Erro ao aplicar divisão do comprovante",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_receipt_splits" })
            };
        })
        .WithName("ApplyReceiptSplits")
        .Produces<ApplyReceiptSplitsResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId) && householdId != Guid.Empty;
    }
}
