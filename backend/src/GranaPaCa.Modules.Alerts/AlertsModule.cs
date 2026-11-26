using System.Security.Claims;
using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace GranaPaCa.Modules.Alerts;

public static class AlertsModule
{
    public static IServiceCollection AddAlertsModule(this IServiceCollection services)
    {
        services.AddSingleton<IAlertPublisher, AlertPublisher>();
        services.AddSingleton<IAlertsDeltaReader, AlertsDeltaReader>();
        services.AddSingleton<IAlertsPurgeService, AlertsPurgeService>();
        return services;
    }

    public static IEndpointRouteBuilder MapAlertsEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/alerts").RequireAuthorization();

        group.MapGet("", async (
            bool? includeResolved,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            var showResolved = includeResolved ?? false;

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var sql = showResolved
                ? """
                  SELECT
                      id AS Id,
                      dedup_key AS DedupKey,
                      kind AS Kind,
                      severity AS Severity,
                      title AS Title,
                      message AS Message,
                      action_target AS ActionTarget,
                      is_read AS IsRead,
                      created_at AS CreatedAt,
                      read_at AS ReadAt,
                      resolved_at AS ResolvedAt
                  FROM alerts.alert
                  WHERE household_id = @HouseholdId
                  ORDER BY created_at DESC, id DESC
                  """
                : """
                  SELECT
                      id AS Id,
                      dedup_key AS DedupKey,
                      kind AS Kind,
                      severity AS Severity,
                      title AS Title,
                      message AS Message,
                      action_target AS ActionTarget,
                      is_read AS IsRead,
                      created_at AS CreatedAt,
                      read_at AS ReadAt,
                      resolved_at AS ResolvedAt
                  FROM alerts.alert
                  WHERE household_id = @HouseholdId
                    AND resolved_at IS NULL
                  ORDER BY created_at DESC, id DESC
                  """;

            var items = (await connection.QueryAsync<AlertItemDto>(new CommandDefinition(
                sql,
                new { HouseholdId = householdId },
                cancellationToken: cancellationToken))).ToList();

            var unreadCount = items.Count(item => !item.IsRead && item.ResolvedAt is null);

            return Results.Ok(new AlertsResponse(unreadCount, items));
        });

        group.MapPost("/{id:guid}/read", async (
            Guid id,
            ClaimsPrincipal user,
            NpgsqlDataSource dataSource,
            CancellationToken cancellationToken) =>
        {
            if (!TryGetHouseholdId(user, out var householdId))
            {
                return Results.Unauthorized();
            }

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            var affected = await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE alerts.alert
                SET is_read = true,
                    read_at = COALESCE(read_at, now())
                WHERE id = @Id
                  AND household_id = @HouseholdId
                """,
                new { Id = id, HouseholdId = householdId },
                cancellationToken: cancellationToken));

            return affected == 0 ? Results.NotFound() : Results.NoContent();
        });

        return endpoints;
    }

    private static bool TryGetHouseholdId(ClaimsPrincipal user, out Guid householdId)
    {
        var raw = user.FindFirst("household_id")?.Value;
        return Guid.TryParse(raw, out householdId);
    }
}

internal sealed record AlertItemDto(
    Guid Id,
    string DedupKey,
    string Kind,
    string Severity,
    string Title,
    string Message,
    string? ActionTarget,
    bool IsRead,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ReadAt,
    DateTimeOffset? ResolvedAt);

internal sealed record AlertsResponse(
    int UnreadCount,
    IReadOnlyList<AlertItemDto> Items);
