using System.Security.Claims;
using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Categorization.Contracts;
using GranaPaCa.Modules.Identity.Contracts;
using GranaPaCa.Modules.Keyring.Contracts;
using Npgsql;

namespace GranaPaCa.Api;

internal static class AccountPurgeEndpoints
{
    private const string RequiredConfirmationText = "APAGAR TUDO";

    public static IEndpointRouteBuilder MapAccountPurgeEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/v1/account/purge", async (
            AccountPurgeRequest? request,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            IIdentityPurgeService identityPurge,
            IBankingPurgeService bankingPurge,
            ICategorizationPurgeService categorizationPurge,
            IAlertsPurgeService alertsPurge,
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
                return Results.BadRequest(new AccountPurgeErrorResponse(
                    "invalid_confirmation",
                    "Para confirmar a exclusão permanente, informe exatamente 'APAGAR TUDO'."));
            }

            if (string.IsNullOrWhiteSpace(request.Password) ||
                string.IsNullOrWhiteSpace(request.TotpCode))
            {
                return Results.BadRequest(new AccountPurgeErrorResponse(
                    "missing_credentials",
                    "Informe sua senha e o código de verificação em duas etapas."));
            }

            var credentialsValid = await identityPurge.VerifyOwnerCredentialsAsync(
                ownerId,
                householdId,
                request.Password,
                request.TotpCode,
                cancellationToken);

            if (!credentialsValid)
            {
                return Results.Json(
                    new AccountPurgeErrorResponse(
                        "invalid_credentials",
                        "Senha ou código de verificação inválidos."),
                    statusCode: StatusCodes.Status401Unauthorized);
            }

            await using (var connection = await dataSource.OpenConnectionAsync(cancellationToken))
            await using (var transaction = await connection.BeginTransactionAsync(cancellationToken))
            {
                // Authorize deletion of append-only provider versions and adjustments within this transaction (ADR-012).
                await connection.ExecuteAsync(new CommandDefinition(
                    "SELECT set_config('granapaca.purge', 'on', true)",
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                await bankingPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await categorizationPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await alertsPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);
                await identityPurge.PurgeHouseholdAsync(householdId, connection, transaction, cancellationToken);

                await transaction.CommitAsync(cancellationToken);
            }

            // Cryptographic erasure of all household DEKs and in-memory caches (ADR-016).
            await envelopeEncryptor.DestroyHouseholdKeysAsync(householdId, cancellationToken);

            return Results.NoContent();
        }).RequireAuthorization();

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

internal sealed record AccountPurgeErrorResponse(
    string Error,
    string Message);
