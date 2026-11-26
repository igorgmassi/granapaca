using Dapper;
using GranaPaCa.Modules.Alerts.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Alerts;

internal sealed class AlertsDeltaReader : IAlertsDeltaReader
{
    public async Task<IReadOnlyList<SyncAlertDto>> GetAlertChangesAsync(
        Guid householdId,
        DateTimeOffset? cursor,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        var sql = cursor.HasValue
            ? """
              WITH alert_changes AS (
                  SELECT
                      id,
                      dedup_key,
                      kind,
                      severity,
                      title,
                      message,
                      action_target,
                      is_read,
                      created_at,
                      read_at,
                      resolved_at,
                      GREATEST(
                          created_at,
                          COALESCE(read_at, created_at),
                          COALESCE(resolved_at, created_at)
                      ) AS updated_at
                  FROM alerts.alert
                  WHERE household_id = @HouseholdId
              )
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
                  resolved_at AS ResolvedAt,
                  updated_at AS UpdatedAt
              FROM alert_changes
              WHERE updated_at > @Cursor
              ORDER BY updated_at ASC, id ASC
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
                  resolved_at AS ResolvedAt,
                  GREATEST(
                      created_at,
                      COALESCE(read_at, created_at),
                      COALESCE(resolved_at, created_at)
                  ) AS UpdatedAt
              FROM alerts.alert
              WHERE household_id = @HouseholdId
              ORDER BY UpdatedAt ASC, id ASC
              """;

        var parameters = new DynamicParameters();
        parameters.Add("HouseholdId", householdId);
        if (cursor.HasValue)
        {
            parameters.Add("Cursor", cursor.Value);
        }

        return (await connection.QueryAsync<SyncAlertDto>(new CommandDefinition(
            sql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();
    }
}
