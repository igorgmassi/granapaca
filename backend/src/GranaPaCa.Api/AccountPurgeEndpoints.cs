using System.Security.Claims;
using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using GranaPaCa.Modules.Assistant.Contracts;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Categorization.Contracts;
using GranaPaCa.Modules.Identity.Contracts;
using GranaPaCa.Modules.Keyring.Contracts;
using GranaPaCa.Modules.Planning.Contracts;
using GranaPaCa.Modules.Receipts.Contracts;
using Npgsql;

namespace GranaPaCa.Api;

internal static class AccountPurgeEndpoints
{
    private const string RequiredConfirmationText = "APAGAR TUDO";

    public static IEndpointRouteBuilder MapAccountPurgeEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/account/purge", async (
            AccountPurgeRequest? request,
            HttpContext httpContext,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            IIdentityPurgeService identityPurge,
            IBankingPurgeService bankingPurge,
            ICategorizationPurgeService categorizationPurge,
            IAlertsPurgeService alertsPurge,
            IPlanningPurgeService planningPurge,
            IReceiptsPurgeService receiptsPurge,
            IAssistantPurgeService assistantPurge,
            IEnvelopeEncryptor envelopeEncryptor,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetCaller(user, out var ownerId, out var householdId))
            {
                return Results.Unauthorized();
            }

            if (request is null ||
                !string.Equals(request.ConfirmationText, RequiredConfirmationText, StringComparison.Ordinal))
            {
                return Results.Problem(
                    title: "Confirmação inválida",
                    detail: "Para confirmar a exclusão permanente, informe exatamente 'APAGAR TUDO'.",
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_confirmation" });
            }

            if (string.IsNullOrWhiteSpace(request.Password) ||
                string.IsNullOrWhiteSpace(request.TotpCode))
            {
                return Results.Problem(
                    title: "Credenciais obrigatórias",
                    detail: "Informe sua senha e o código de verificação em duas etapas.",
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "missing_credentials" });
            }

            var clientIp = httpContext.Connection.RemoteIpAddress?.ToString() ?? "local";
            var verification = await identityPurge.VerifyOwnerCredentialsAsync(
                ownerId,
                householdId,
                request.Password,
                request.TotpCode,
                clientIp,
                cancellationToken);

            if (verification == OwnerCredentialVerificationStatus.RateLimited)
            {
                return Results.Problem(
                    title: "Muitas tentativas de acesso",
                    detail: "Muitas tentativas de verificação. Tente novamente em alguns minutos.",
                    statusCode: StatusCodes.Status429TooManyRequests,
                    extensions: new Dictionary<string, object?> { ["code"] = "rate_limited" });
            }

            if (verification != OwnerCredentialVerificationStatus.Valid)
            {
                return Results.Problem(
                    title: "Credenciais inválidas",
                    detail: "Senha ou código de verificação inválidos.",
                    statusCode: StatusCodes.Status401Unauthorized,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_credentials" });
            }

            await using (var connection = await dataSource.OpenConnectionAsync(cancellationToken))
            await using (var transaction = await connection.BeginTransactionAsync(cancellationToken))
            {
                // Authorize deletion of append-only provider versions and adjustments within this transaction (ADR-012).
                await connection.ExecuteAsync(new CommandDefinition(
                    "SELECT set_config('granapaca.purge', 'on', true)",
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                await assistantPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await receiptsPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await planningPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await bankingPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await categorizationPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await alertsPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                // Destroy DEK rows atomically inside the same transaction before deleting identity records (ADR-016).
                await envelopeEncryptor.DestroyHouseholdKeysAsync(householdId, connection, transaction, cancellationToken);
                await identityPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);

                await transaction.CommitAsync(cancellationToken);
            }

            // Evict cached DEKs only after commit so a rolled-back purge never invalidates active keys.
            envelopeEncryptor.EvictHouseholdKeysFromCache(householdId);

            return Results.NoContent();
        })
        .RequireAuthorization()
        .WithName("PurgeAccount")
        .WithTags("Account")
        .Produces(StatusCodes.Status204NoContent)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status401Unauthorized)
        .ProducesProblem(StatusCodes.Status429TooManyRequests);

        return endpoints;
    }

    private static bool TryGetCaller(
        ClaimsPrincipal user,
        out Guid ownerId,
        out Guid householdId)
    {
        householdId = Guid.Empty;
        return Guid.TryParse(user.FindFirstValue(IdentityClaimTypes.OwnerId), out ownerId)
            && ownerId != Guid.Empty
            && Guid.TryParse(user.FindFirstValue(IdentityClaimTypes.HouseholdId), out householdId)
            && householdId != Guid.Empty;
    }
}

internal sealed record AccountPurgeRequest(
    string? Password,
    string? TotpCode,
    string? ConfirmationText);
