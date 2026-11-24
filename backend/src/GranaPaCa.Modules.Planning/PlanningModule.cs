using System.Security.Claims;
using GranaPaCa.Modules.Planning.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;

namespace GranaPaCa.Modules.Planning;

public static class PlanningModule
{
    public static IServiceCollection AddPlanningModule(this IServiceCollection services)
    {
        services.AddScoped<PlanningService>();
        services.AddScoped<IPlanningReader>(sp => sp.GetRequiredService<PlanningService>());
        services.AddScoped<IPlanningPurgeService>(sp => sp.GetRequiredService<PlanningService>());
        return services;
    }

    public static IEndpointRouteBuilder MapPlanningEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/planning").RequireAuthorization();

        group.MapGet("/overview", async (
            string? month,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.GetOverviewAsync(householdId, month, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapGet("/budgets", async (
            string? month,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.GetBudgetsAsync(householdId, month, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapPut("/budgets", async (
            UpsertBudgetRequest? request,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.UpsertBudgetAsync(householdId, request, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapDelete("/budgets/{id:guid}", async (
            Guid id,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var deleted = await service.DeleteBudgetAsync(householdId, id, cancellationToken);
            return deleted ? Results.NoContent() : Results.NotFound();
        });

        group.MapGet("/goals", async (
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.GetGoalsAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        group.MapPost("/goals", async (
            CreateGoalRequest? request,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.CreateGoalAsync(householdId, request, cancellationToken);
            return ok
                ? Results.Created($"/api/v1/planning/goals/{data!.Id}", data)
                : Results.BadRequest(new { error });
        });

        group.MapPatch("/goals/{id:guid}", async (
            Guid id,
            UpdateGoalRequest? request,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (statusCode, error, data) = await service.UpdateGoalAsync(householdId, id, request, cancellationToken);
            return statusCode switch
            {
                200 => Results.Ok(data),
                404 => Results.NotFound(),
                _ => Results.BadRequest(new { error })
            };
        });

        group.MapDelete("/goals/{id:guid}", async (
            Guid id,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var deleted = await service.DeleteGoalAsync(householdId, id, cancellationToken);
            return deleted ? Results.NoContent() : Results.NotFound();
        });

        group.MapGet("/alert-rules", async (
            string? month,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.GetAlertRulesAsync(householdId, month, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapPost("/alert-rules", async (
            CreateSpendingAlertRuleRequest? request,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.CreateAlertRuleAsync(householdId, request, cancellationToken);
            return ok
                ? Results.Created($"/api/v1/planning/alert-rules/{data!.Id}", data)
                : Results.BadRequest(new { error });
        });

        group.MapDelete("/alert-rules/{id:guid}", async (
            Guid id,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var deleted = await service.DeleteAlertRuleAsync(householdId, id, cancellationToken);
            return deleted ? Results.NoContent() : Results.NotFound();
        });

        group.MapPost("/evaluate-alerts", async (
            string? month,
            EvaluateAlertsRequest? request,
            ClaimsPrincipal user,
            PlanningService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var effectiveMonth = !string.IsNullOrWhiteSpace(month) ? month : request?.Month;
            var (ok, error, data) = await service.EvaluateAlertsAsync(householdId, effectiveMonth, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId) && householdId != Guid.Empty;
    }
}
