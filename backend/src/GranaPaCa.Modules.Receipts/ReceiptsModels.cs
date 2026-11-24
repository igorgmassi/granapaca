namespace GranaPaCa.Modules.Receipts;

internal sealed record ReceiptConsentDto(
    bool HasDecided,
    bool ItemAnalysisAccepted,
    bool DietaryNotesAccepted,
    DateTimeOffset? DecidedAt,
    string Notice);

internal sealed record UpdateReceiptConsentRequest(
    bool ItemAnalysisAccepted,
    bool DietaryNotesAccepted);

internal sealed record ReceiptItemDto(
    Guid Id,
    int ItemIndex,
    string Description,
    decimal Quantity,
    long UnitPriceCents,
    long TotalCents,
    string? SuggestedCategory);

internal sealed record ReceiptDto(
    Guid Id,
    Guid? TransactionId,
    string FileName,
    string ContentType,
    long FileSizeBytes,
    bool HasStoredFile,
    string? NfceAccessKey,
    string? IssuerName,
    DateOnly? IssuedOn,
    long? TotalCents,
    DateTimeOffset CreatedAt,
    IReadOnlyList<ReceiptItemDto> Items);

internal sealed record ReceiptsListResponse(
    IReadOnlyList<ReceiptDto> Items);

internal sealed record UploadReceiptRequest(
    Guid? TransactionId,
    string? FileName,
    string? ContentType,
    string? ContentBase64);

internal sealed record ParseNfceRequest(
    string? Xml,
    string? QrUrl,
    Guid? TransactionId,
    bool? Save);

internal sealed record ParsedNfceItemDto(
    int ItemIndex,
    string Description,
    decimal Quantity,
    long UnitPriceCents,
    long TotalCents,
    string? SuggestedCategory);

internal sealed record ParseNfceResponse(
    Guid? Id,
    bool Saved,
    Guid? TransactionId,
    string? AccessKey,
    string? State,
    string? IssuerName,
    string? IssuerCnpj,
    DateOnly? IssuedOn,
    long? TotalCents,
    string? QrPortalHost,
    string? Notice,
    IReadOnlyList<ParsedNfceItemDto> Items);

internal sealed record ApplyReceiptSplitsRequest(Guid? TransactionId);

internal sealed record AppliedReceiptSplitDto(
    string Description,
    long AmountCents,
    string? Category,
    string? Essentiality);

internal sealed record ApplyReceiptSplitsResponse(
    Guid ReceiptId,
    Guid TransactionId,
    int SplitsApplied,
    long TotalCents,
    IReadOnlyList<AppliedReceiptSplitDto> Splits);
