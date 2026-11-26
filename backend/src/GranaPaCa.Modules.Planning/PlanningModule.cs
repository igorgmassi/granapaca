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
        var group = endpoints.MapGroup("/api/v1/planning")
            .RequireAuthorization()
            .WithTags("Planning");

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
            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Parâmetro de planejamento inválido",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_planning_query" });
        })
        .WithName("GetPlanningOverview")
        .Produces<PlanningOverviewResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Consulta de orçamentos inválida",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_budget_query" });
        })
        .WithName("GetBudgets")
        .Produces<BudgetsListResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Orçamento inválido",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_budget" });
        })
        .WithName("UpsertBudget")
        .Produces<BudgetDto>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
        })
        .WithName("DeleteBudget")
        .Produces(StatusCodes.Status204NoContent)
        .Produces(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

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
        })
        .WithName("GetGoals")
        .Produces<GoalsListResponse>(StatusCodes.Status200OK)
        .Produces(StatusCodes.Status401Unauthorized);

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
                : Results.Problem(
                    title: "Meta inválida",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_goal" });
        })
        .WithName("CreateGoal")
        .Produces<GoalDto>(StatusCodes.Status201Created)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
                404 => Results.Problem(
                    title: "Meta não encontrada",
                    detail: error ?? "Meta não encontrada.",
                    statusCode: StatusCodes.Status404NotFound,
                    extensions: new Dictionary<string, object?> { ["code"] = "goal_not_found" }),
                _ => Results.Problem(
                    title: "Atualização de meta inválida",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_goal_update" })
            };
        })
        .WithName("UpdateGoal")
        .Produces<GoalDto>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .ProducesProblem(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

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
        })
        .WithName("DeleteGoal")
        .Produces(StatusCodes.Status204NoContent)
        .Produces(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

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
            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Consulta de regras de alerta inválida",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_alert_rule_query" });
        })
        .WithName("GetSpendingAlertRules")
        .Produces<SpendingAlertRulesListResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
                : Results.Problem(
                    title: "Regra de alerta inválida",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_alert_rule" });
        })
        .WithName("CreateSpendingAlertRule")
        .Produces<SpendingAlertRuleDto>(StatusCodes.Status201Created)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

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
        })
        .WithName("DeleteSpendingAlertRule")
        .Produces(StatusCodes.Status204NoContent)
        .Produces(StatusCodes.Status404NotFound)
        .Produces(StatusCodes.Status401Unauthorized);

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
            return ok
                ? Results.Ok(data)
                : Results.Problem(
                    title: "Avaliação de alertas inválida",
                    detail: error,
                    statusCode: StatusCodes.Status400BadRequest,
                    extensions: new Dictionary<string, object?> { ["code"] = "invalid_alert_evaluation" });
        })
        .WithName("EvaluatePlanningAlerts")
        .Produces<EvaluateAlertsResponse>(StatusCodes.Status200OK)
        .ProducesProblem(StatusCodes.Status400BadRequest)
        .Produces(StatusCodes.Status401Unauthorized);

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId) && householdId != Guid.Empty;
    }
}
