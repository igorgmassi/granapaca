using System.Security.Claims;
using System.Text.Json;
using GranaPaCa.Modules.Assistant.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace GranaPaCa.Modules.Assistant;

public static class AssistantModule
{
    public static IServiceCollection AddAssistantModule(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        services.AddHttpClient<ExternalAiProviderClient>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(20);
        });

        services.AddScoped<AssistantService>();
        services.AddScoped<IAssistantPurgeService>(sp => sp.GetRequiredService<AssistantService>());
        return services;
    }

    public static IEndpointRouteBuilder MapAssistantEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/assistant").RequireAuthorization();

        group.MapGet("/provider", async (
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.GetProviderConfigAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        group.MapPut("/provider", async (
            UpdateProviderConfigRequest? request,
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.UpdateProviderConfigAsync(householdId, request, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapGet("/history", async (
            int? limit,
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.GetHistoryAsync(householdId, limit, cancellationToken);
            return Results.Ok(data);
        });

        group.MapPost("/chat", async (
            ChatRequest? request,
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (ok, error, data) = await service.ChatAsync(householdId, request, cancellationToken);
            return ok ? Results.Ok(data) : Results.BadRequest(new { error });
        });

        group.MapPost("/chat/stream", async (
            ChatRequest? request,
            ClaimsPrincipal user,
            HttpContext httpContext,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                httpContext.Response.StatusCode = StatusCodes.Status401Unauthorized;
                return;
            }

            var (ok, error, data) = await service.ChatAsync(householdId, request, cancellationToken);
            if (!ok || data is null)
            {
                httpContext.Response.StatusCode = StatusCodes.Status400BadRequest;
                await httpContext.Response.WriteAsJsonAsync(new { error }, cancellationToken);
                return;
            }

            // Server-Sent Events stream per ADR-018.
            httpContext.Response.StatusCode = StatusCodes.Status200OK;
            httpContext.Response.Headers.ContentType = "text/event-stream; charset=utf-8";
            httpContext.Response.Headers.CacheControl = "no-cache";
            httpContext.Response.Headers["X-Accel-Buffering"] = "no";

            var metaPayload = JsonSerializer.Serialize(new
            {
                data.MessageId,
                data.PeriodUsed,
                data.ProviderUsed,
                data.Pseudonymized,
                data.NumbersCited
            }, AssistantFormatting.WebJson);

            await httpContext.Response.WriteAsync($"event: meta\ndata: {metaPayload}\n\n", cancellationToken);
            await httpContext.Response.Body.FlushAsync(cancellationToken);

            foreach (var chunk in AssistantService.SplitIntoStreamChunks(data.Content))
            {
                var tokenPayload = JsonSerializer.Serialize(new { delta = chunk }, AssistantFormatting.WebJson);
                await httpContext.Response.WriteAsync($"event: token\ndata: {tokenPayload}\n\n", cancellationToken);
                await httpContext.Response.Body.FlushAsync(cancellationToken);
            }

            var donePayload = JsonSerializer.Serialize(new
            {
                data.MessageId,
                data.PeriodUsed,
                data.ProviderUsed,
                data.Pseudonymized,
                data.Content,
                data.NumbersCited,
                data.CreatedAt
            }, AssistantFormatting.WebJson);

            await httpContext.Response.WriteAsync($"event: done\ndata: {donePayload}\n\n", cancellationToken);
            await httpContext.Response.Body.FlushAsync(cancellationToken);
        });

        group.MapPost("/suggestions/generate", async (
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.GenerateSuggestionsAsync(householdId, cancellationToken);
            return Results.Ok(data);
        });

        group.MapGet("/suggestions", async (
            string? status,
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var data = await service.ListSuggestionsAsync(householdId, status, cancellationToken);
            return Results.Ok(data);
        });

        group.MapPost("/suggestions/{id:guid}/decide", async (
            Guid id,
            DecideSuggestionRequest? request,
            ClaimsPrincipal user,
            AssistantService service,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var (statusCode, error, data) = await service.DecideSuggestionAsync(
                householdId,
                id,
                request,
                cancellationToken);

            return statusCode switch
            {
                200 => Results.Ok(data),
                404 => Results.NotFound(),
                409 => Results.Conflict(new { error }),
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
