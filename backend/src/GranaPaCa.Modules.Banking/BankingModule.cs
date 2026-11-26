using System.Security.Claims;
using Dapper;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Banking.Providers;
using GranaPaCa.Modules.Categorization.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GranaPaCa.Modules.Banking;

public static class BankingModule
{
    public static IServiceCollection AddBankingModule(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        SqlMapper.AddTypeHandler(new DateOnlyTypeHandler());

        var pluggyBaseUrl = configuration["Pluggy:BaseUrl"]
            ?? configuration["PLUGGY_BASE_URL"]
            ?? "https://api.pluggy.ai/";

        services.AddSingleton<SyntheticBankProvider>();
        services.AddSingleton<PluggyAuthTokenCache>();
        services.AddHttpClient<PluggyBankProvider>(client =>
        {
            client.BaseAddress = new Uri(pluggyBaseUrl);
            client.Timeout = TimeSpan.FromSeconds(30);
        });

        services.AddScoped<BankingSyncService>();
        services.AddScoped<IBankingSyncTrigger>(sp => sp.GetRequiredService<BankingSyncService>());
        services.AddScoped<ITransactionReclassifier>(sp => sp.GetRequiredService<BankingSyncService>());
        services.AddScoped<BankingQueries>();
        services.AddScoped<BankingDeltaSyncService>();
        services.AddSingleton<IBankingPurgeService, BankingPurgeService>();

        services.AddHostedService<DailySyncWorker>();
        return services;
    }

    public static IEndpointRouteBuilder MapBankingEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var api = endpoints.MapGroup("/api/v1").RequireAuthorization();

        api.MapGet("/summary", async (
            string? month,
            Guid? bankId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await queries.GetSummaryAsync(householdId, month, bankId, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        api.MapGet("/banks", async (
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetBanksAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        api.MapGet("/banks/{connectionId:guid}", async (
            Guid connectionId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetBankDetailAsync(householdId, connectionId, cancellationToken);
            return data is null ? Results.NotFound() : Results.Ok(data);
        });

        api.MapGet("/cards/{accountId:guid}/bills", async (
            Guid accountId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetCardBillsAsync(householdId, accountId, cancellationToken);
            return data is null ? Results.NotFound() : Results.Ok(data);
        });

        api.MapGet("/cards/bills/{billId:guid}", async (
            Guid billId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetCardBillDetailAsync(householdId, billId, cancellationToken);
            return data is null ? Results.NotFound() : Results.Ok(data);
        });

        api.MapGet("/transactions", async (
            DateOnly? from,
            DateOnly? to,
            Guid? bankId,
            Guid? accountId,
            string? kind,
            string? category,
            string? essentiality,
            string? brand,
            string? search,
            int? page,
            int? pageSize,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetTransactionsAsync(
                householdId,
                from,
                to,
                bankId,
                accountId,
                kind,
                category,
                essentiality,
                brand,
                search,
                page ?? 1,
                pageSize ?? 50,
                cancellationToken);

            return Results.Ok(data);
        });

        api.MapGet("/transactions/review-queue", async (
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetReviewQueueAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        api.MapGet("/transactions/{id:guid}", async (
            Guid id,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetTransactionDetailAsync(householdId, id, cancellationToken);
            return data is null ? Results.NotFound() : Results.Ok(data);
        });

        api.MapPost("/transactions/{id:guid}/adjustments", async (
            Guid id,
            ApplyAdjustmentsRequest request,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (statusCode, error, data) = await queries.ApplyAdjustmentsAsync(
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

        api.MapPost("/transactions/{id:guid}/adjustments/{adjustmentId:guid}/undo", async (
            Guid id,
            Guid adjustmentId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (statusCode, error, data) = await queries.UndoAdjustmentAsync(
                householdId,
                id,
                adjustmentId,
                cancellationToken);

            return statusCode switch
            {
                200 => Results.Ok(data),
                404 => Results.NotFound(),
                409 => Results.Conflict(new { error }),
                _ => Results.BadRequest(new { error })
            };
        });

        api.MapGet("/spending/donut", async (
            DateOnly? from,
            DateOnly? to,
            Guid? bankId,
            Guid? accountId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetSpendingDonutAsync(
                householdId,
                from,
                to,
                bankId,
                accountId,
                cancellationToken);

            return Results.Ok(data);
        });

        api.MapGet("/spending/ranking", async (
            DateOnly? from,
            DateOnly? to,
            Guid? bankId,
            Guid? accountId,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetSpendingRankingAsync(
                householdId,
                from,
                to,
                bankId,
                accountId,
                cancellationToken);

            return Results.Ok(data);
        });

        api.MapGet("/connections", async (
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await queries.GetConnectionsAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        api.MapPost("/connections/pluggy", async (
            RegisterPluggyConnectionRequest request,
            ClaimsPrincipal user,
            BankingQueries queries,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await queries.RegisterPluggyConnectionAsync(
                householdId,
                request,
                cancellationToken);

            return ok ? Results.Created($"/api/v1/banks/{data!.Id}", data) : Results.BadRequest(new { error });
        });

        api.MapPost("/connections/sync", async (
            ClaimsPrincipal user,
            IBankingSyncTrigger syncTrigger,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var summary = await syncTrigger.SyncHouseholdAsync(householdId, cancellationToken);
            var message = summary.ConnectionsProcessed == 0 && summary.FailedConnections == 0
                ? "Nenhuma conexão bancária encontrada para sincronizar."
                : summary.FailedConnections > 0
                    ? "Sincronização concluída com avisos em uma ou mais conexões."
                    : "Sincronização concluída com sucesso.";

            return Results.Ok(new SyncResponse(
                summary.ConnectionsProcessed,
                summary.AccountsSynced,
                summary.TransactionsInserted,
                summary.TransactionsVersioned,
                summary.TransactionsRemoved,
                summary.TransfersLinked,
                summary.FailedConnections,
                message));
        });

        api.MapGet("/sync/changes", async (
            string? cursor,
            ClaimsPrincipal user,
            BankingDeltaSyncService deltaSync,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, errorCode, error, data) = await deltaSync.GetChangesAsync(householdId, cursor, cancellationToken);
            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Cursor de sincronização inválido",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?>
                    {
                        ["code"] = errorCode ?? "invalid_cursor",
                        ["fullResyncRequired"] = true,
                    });
        })
        .WithName("GetSyncChanges")
        .WithTags("Sync")
        .Produces<SyncChangesResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

        api.MapPost("/imports/ofx", async (
            ImportStatementRequest? request,
            ClaimsPrincipal user,
            BankingSyncService syncService,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await syncService.ImportStatementAsync(
                householdId,
                "ofx",
                request,
                cancellationToken);

            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Erro ao importar extrato OFX",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_ofx" });
        })
        .WithName("ImportOfxStatement")
        .WithTags("Imports")
        .Produces<ImportResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

        api.MapPost("/imports/csv", async (
            ImportStatementRequest? request,
            ClaimsPrincipal user,
            BankingSyncService syncService,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await syncService.ImportStatementAsync(
                householdId,
                "csv",
                request,
                cancellationToken);

            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Erro ao importar extrato CSV",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_csv" });
        })
        .WithName("ImportCsvStatement")
        .WithTags("Imports")
        .Produces<ImportResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId);
    }
}
