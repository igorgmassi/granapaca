using Dapper;
using GranaPaCa.Modules.Banking.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class BankingPurgeService : IBankingPurgeService
{
    public async Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        // Enables authorized append-only bypass only inside this transaction (ADR-012).
        await connection.ExecuteAsync(new CommandDefinition(
            "SELECT set_config('granapaca.purge', 'on', true)",
            transaction: transaction,
            cancellationToken: cancellationToken));

        var param = new { HouseholdId = householdId };

        // Clear self-referencing adjustment undo links before deleting adjustments.
        await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE banking.adjustment a
            SET undoes_id = NULL
            FROM banking.transaction t
            WHERE a.transaction_id = t.id
              AND t.household_id = @HouseholdId
              AND a.undoes_id IS NOT NULL
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.adjustment a
            USING banking.transaction t
            WHERE a.transaction_id = t.id
              AND t.household_id = @HouseholdId
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.classification cl
            USING banking.transaction t
            WHERE cl.transaction_id = t.id
              AND t.household_id = @HouseholdId
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM banking.transfer_link WHERE household_id = @HouseholdId",
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.transaction_version v
            USING banking.transaction t
            WHERE v.transaction_id = t.id
              AND t.household_id = @HouseholdId
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.transaction_source s
            USING banking.transaction t
            WHERE s.transaction_id = t.id
              AND t.household_id = @HouseholdId
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM banking.transaction WHERE household_id = @HouseholdId",
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.card_bill cb
            USING banking.account a
            WHERE cb.account_id = a.id
              AND a.household_id = @HouseholdId
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM banking.balance_snapshot bs
            USING banking.account a
            WHERE bs.account_id = a.id
              AND a.household_id = @HouseholdId
            """,
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM banking.account WHERE household_id = @HouseholdId",
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM banking.connection WHERE household_id = @HouseholdId",
            param,
            transaction: transaction,
            cancellationToken: cancellationToken));
    }
}
