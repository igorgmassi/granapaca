using Dapper;
using GranaPaCa.Modules.Categorization.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Categorization;

internal sealed class CategorizationDeltaReader : ICategorizationDeltaReader
{
    public async Task<IReadOnlyList<SyncRuleDto>> GetRuleChangesAsync(
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
              SELECT
                  id AS Id,
                  layer AS Layer,
                  priority AS Priority,
                  name AS Name,
                  explanation AS Explanation,
                  match_cnpj AS MatchCnpj,
                  match_merchant_normalized AS MatchMerchantNormalized,
                  match_pattern AS MatchPattern,
                  category AS Category,
                  essentiality AS Essentiality,
                  brand AS Brand,
                  is_active AS IsActive,
                  created_at AS CreatedAt,
                  GREATEST(created_at, updated_at) AS UpdatedAt
              FROM categorization.rule
              WHERE household_id = @HouseholdId
                AND GREATEST(created_at, updated_at) > @Cursor
              ORDER BY UpdatedAt ASC, id ASC
              """
            : """
              SELECT
                  id AS Id,
                  layer AS Layer,
                  priority AS Priority,
                  name AS Name,
                  explanation AS Explanation,
                  match_cnpj AS MatchCnpj,
                  match_merchant_normalized AS MatchMerchantNormalized,
                  match_pattern AS MatchPattern,
                  category AS Category,
                  essentiality AS Essentiality,
                  brand AS Brand,
                  is_active AS IsActive,
                  created_at AS CreatedAt,
                  GREATEST(created_at, updated_at) AS UpdatedAt
              FROM categorization.rule
              WHERE household_id = @HouseholdId
              ORDER BY UpdatedAt ASC, id ASC
              """;

        var parameters = new DynamicParameters();
        parameters.Add("HouseholdId", householdId);
        if (cursor.HasValue)
        {
            parameters.Add("Cursor", cursor.Value);
        }

        return (await connection.QueryAsync<SyncRuleDto>(new CommandDefinition(
            sql,
            parameters,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();
    }
}
