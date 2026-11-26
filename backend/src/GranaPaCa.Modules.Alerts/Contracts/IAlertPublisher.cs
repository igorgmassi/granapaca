namespace GranaPaCa.Modules.Alerts.Contracts;

public sealed record AlertRequest(
    Guid HouseholdId,
    string DedupKey,
    string Kind,
    string Severity,
    string Title,
    string Message,
    string? ActionTarget = null);

/// <summary>
/// Publishes deduplicated inbox alerts and auto-resolves them when their cause clears (RF-56, ADR-011).
/// </summary>
public interface IAlertPublisher
{
    Task RaiseAsync(AlertRequest alert, CancellationToken cancellationToken = default);

    Task ResolveAsync(Guid householdId, string dedupKey, CancellationToken cancellationToken = default);
}
