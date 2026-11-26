namespace GranaPaCa.Modules.Identity.Contracts;

/// <summary>
/// Lists configured household identifiers for host-level maintenance tasks.
/// </summary>
public interface IHouseholdDirectory
{
    Task<IReadOnlyList<Guid>> ListHouseholdIdsAsync(CancellationToken cancellationToken = default);
}
