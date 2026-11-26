using Npgsql;

namespace GranaPaCa.Modules.Categorization.Contracts;

/// <summary>
/// Reads categorization rule changes inside a caller-owned REPEATABLE READ snapshot for cursor delta sync (ADR-007).
/// </summary>
public interface ICategorizationDeltaReader
{
    Task<IReadOnlyList<SyncRuleDto>> GetRuleChangesAsync(
        Guid householdId,
        DateTimeOffset? cursor,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default);
}

public sealed record SyncRuleDto(
    Guid Id,
    string Layer,
    int Priority,
    string Name,
    string Explanation,
    string? MatchCnpj,
    string? MatchMerchantNormalized,
    string? MatchPattern,
    string? Category,
    string? Essentiality,
    string? Brand,
    bool IsActive,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
