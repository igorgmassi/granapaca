using Npgsql;

namespace GranaPaCa.Modules.Alerts.Contracts;

/// <summary>
/// Reads alert changes inside a caller-owned REPEATABLE READ snapshot for cursor delta sync (ADR-007).
/// </summary>
public interface IAlertsDeltaReader
{
    Task<IReadOnlyList<SyncAlertDto>> GetAlertChangesAsync(
        Guid householdId,
        DateTimeOffset? cursor,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}

public sealed record SyncAlertDto(
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
    DateTimeOffset? ResolvedAt,
    DateTimeOffset UpdatedAt);
