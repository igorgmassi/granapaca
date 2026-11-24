namespace GranaPaCa.Modules.Banking.Providers;

internal interface IBankProvider
{
    string ProviderName { get; }

    bool IsConfigured { get; }

    Task<ProviderConnectionData> FetchConnectionAsync(
        string externalItemId,
        CancellationToken cancellationToken = default);
}

internal sealed record ProviderConnectionData(
    string ExternalItemId,
    string InstitutionName,
    string BrandColor,
    string Status,
    DateTimeOffset? ConsentExpiresAt,
    string? LastErrorCode,
    IReadOnlyList<ProviderAccountData> Accounts);

internal sealed record ProviderAccountData(
    string ExternalAccountId,
    string Name,
    string Kind,
    string? LastFourDigits,
    string Currency,
    long OpeningBalanceCents,
    long CurrentBalanceCents,
    IReadOnlyList<ProviderCardBillData> Bills,
    IReadOnlyList<ProviderTransactionData> Transactions);

internal sealed record ProviderCardBillData(
    string ExternalBillId,
    DateOnly PeriodMonth,
    DateOnly ClosingOn,
    DateOnly DueOn,
    long TotalCents,
    bool IsOpen,
    string RawPayloadJson);

internal sealed record ProviderTransactionData(
    string Source,
    string ExternalId,
    DateOnly OccurredOn,
    DateOnly? PurchaseOn,
    string Description,
    string? MerchantCnpj,
    long AmountCents,
    string Currency,
    string Status,
    string? ExternalBillId,
    int? InstallmentNumber,
    int? InstallmentTotal,
    string RawPayloadJson);
