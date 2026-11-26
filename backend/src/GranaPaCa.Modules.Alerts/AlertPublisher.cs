using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Alerts;

internal sealed class AlertPublisher(NpgsqlDataSource dataSource) : IAlertPublisher
{
    private static readonly HashSet<string> AllowedSeverities =
        new(StringComparer.Ordinal) { "info", "warning", "error" };

    public async Task RaiseAsync(AlertRequest alert, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(alert);

        var severity = alert.Severity.Trim().ToLowerInvariant();
        if (!AllowedSeverities.Contains(severity))
        {
            throw new ArgumentException($"Invalid alert severity '{alert.Severity}'.", nameof(alert));
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO alerts.alert (
                id,
                household_id,
                dedup_key,
                kind,
                severity,
                title,
                message,
                action_target
            )
            VALUES (
                @Id,
                @HouseholdId,
                @DedupKey,
                @Kind,
                @Severity,
                @Title,
                @Message,
                @ActionTarget
            )
            ON CONFLICT (household_id, dedup_key) WHERE resolved_at IS NULL DO NOTHING
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                alert.HouseholdId,
                alert.DedupKey,
                alert.Kind,
                Severity = severity,
                alert.Title,
                alert.Message,
                alert.ActionTarget
            },
            cancellationToken: cancellationToken));
    }

    public async Task ResolveAsync(
        Guid householdId,
        string dedupKey,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE alerts.alert
            SET resolved_at = now()
            WHERE household_id = @HouseholdId
              AND dedup_key = @DedupKey
              AND resolved_at IS NULL
            """,
            new { HouseholdId = householdId, DedupKey = dedupKey },
            cancellationToken: cancellationToken));
    }
}
