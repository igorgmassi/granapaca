namespace GranaPaCa.Modules.Banking.Contracts;

public sealed record BankingMonthMetrics(
    string Month,
    long BalanceCents,
    long SpentCents,
    long ReceivedCents,
    long LeftoverCents,
    long CardBillCents,
    long EssentialSpentCents,
    long ImportantSpentCents,
    long FlexibleSpentCents,
    long RecurringSpentCents,
    long AtypicalSpentCents,
    IReadOnlyDictionary<string, long> SpentByCategoryCents,
    IReadOnlyDictionary<DateOnly, long> DailySpendingCents);

public sealed record BankingTransactionFact(
    Guid Id,
    Guid AccountId,
    string AccountName,
    string InstitutionName,
    DateOnly OccurredOn,
    string Description,
    long AmountCents,
    string Kind,
    string? Category,
    string? Essentiality,
    string? PaymentMethod,
    bool IsAtypical,
    IReadOnlyList<string> Tags);

public sealed record BankingSplitInput(
    string Description,
    long AmountCents,
    string? Category,
    string? Essentiality);

/// <summary>
/// Read-only financial facts contract consumed by Planning and Assistant without violating ADR-002 boundaries.
/// </summary>
public interface IBankingAnalyticsReader
{
    Task<BankingMonthMetrics> GetMonthMetricsAsync(
        Guid householdId,
        DateOnly monthStart,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<BankingTransactionFact>> GetTransactionsInRangeAsync(
        Guid householdId,
        DateOnly from,
        DateOnly toExclusive,
        CancellationToken cancellationToken = default);
}

/// <summary>
/// Allows Receipts (NFC-e itemization) to replace splits on a household transaction while enforcing exact-cent sum (RN-24).
/// </summary>
public interface IBankingSplitWriter
{
    Task<(bool Ok, string? Error)> ReplaceTransactionSplitsAsync(
        Guid householdId,
        Guid transactionId,
        IReadOnlyList<BankingSplitInput> splits,
        CancellationToken cancellationToken = default);
}
