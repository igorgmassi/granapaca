using System.Net.Http.Headers;
using System.Text;
using Dapper;
using GranaPaCa.Modules.Banking.Contracts;
using GranaPaCa.Modules.Receipts.Contracts;
using Microsoft.AspNetCore.Http;
using Npgsql;

namespace GranaPaCa.Modules.Receipts;

internal sealed class ReceiptsService(
    NpgsqlDataSource dataSource,
    EncryptedReceiptFileStore fileStore,
    IBankingAnalyticsReader bankingReader,
    IBankingSplitWriter splitWriter) : IReceiptsPurgeService
{
    private const int MaxFileSizeBytes = 10 * 1024 * 1024;
    private const int MaxBase64NonWhitespaceChars = ((MaxFileSizeBytes + 2) / 3) * 4;
    private const string ConsentNotice =
        "Os itens das suas notas fiscais ficam guardados somente na sua instância, cifrados em disco. " +
        "Você escolhe separadamente se deseja organizar itens por categoria e se autoriza notas alimentares locais.";

    private static readonly HashSet<string> AllowedReceiptContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/png",
        "image/webp",
        "application/pdf",
        "application/xml",
        "text/xml"
    };

    public async Task<IReadOnlyList<string>> PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        var filePaths = (await connection.QueryAsync<string?>(new CommandDefinition(
            "SELECT storage_rel_path FROM receipts.receipt WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken)))
            .Where(p => !string.IsNullOrWhiteSpace(p))
            .Select(p => p!)
            .ToList();

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM receipts.receipt WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM receipts.consent WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        // Return paths so disk erasure executes only after DB transaction commits.
        return filePaths;
    }

    public void DeletePurgedFiles(Guid householdId, IReadOnlyList<string> storageRelPaths)
    {
        fileStore.DeleteHouseholdFiles(householdId, storageRelPaths);
    }

    public async Task<ReceiptConsentDto> GetConsentAsync(
        Guid householdId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<ConsentRow>(new CommandDefinition(
            """
            SELECT
                item_analysis_accepted AS ItemAnalysisAccepted,
                dietary_notes_accepted AS DietaryNotesAccepted,
                decided_at AS DecidedAt
            FROM receipts.consent
            WHERE household_id = @HouseholdId
            """,
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (row is null)
        {
            return new ReceiptConsentDto(false, false, false, null, ConsentNotice);
        }

        return new ReceiptConsentDto(
            true,
            row.ItemAnalysisAccepted,
            row.DietaryNotesAccepted,
            row.DecidedAt,
            ConsentNotice);
    }

    public async Task<ReceiptConsentDto> SaveConsentAsync(
        Guid householdId,
        UpdateReceiptConsentRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var saved = await connection.QuerySingleAsync<ConsentRow>(new CommandDefinition(
            """
            INSERT INTO receipts.consent (
                household_id,
                item_analysis_accepted,
                dietary_notes_accepted,
                decided_at
            )
            VALUES (
                @HouseholdId,
                @ItemAnalysisAccepted,
                @DietaryNotesAccepted,
                now()
            )
            ON CONFLICT (household_id) DO UPDATE
            SET item_analysis_accepted = EXCLUDED.item_analysis_accepted,
                dietary_notes_accepted = EXCLUDED.dietary_notes_accepted,
                decided_at = now()
            RETURNING
                item_analysis_accepted AS ItemAnalysisAccepted,
                dietary_notes_accepted AS DietaryNotesAccepted,
                decided_at AS DecidedAt
            """,
            new
            {
                HouseholdId = householdId,
                request.ItemAnalysisAccepted,
                request.DietaryNotesAccepted
            },
            cancellationToken: cancellationToken));

        return new ReceiptConsentDto(
            true,
            saved.ItemAnalysisAccepted,
            saved.DietaryNotesAccepted,
            saved.DecidedAt,
            ConsentNotice);
    }

    public async Task<ReceiptsListResponse> ListReceiptsAsync(
        Guid householdId,
        Guid? transactionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var sql = transactionId.HasValue
            ? """
              SELECT
                  id AS Id,
                  transaction_id AS TransactionId,
                  file_name AS FileName,
                  content_type AS ContentType,
                  file_size_bytes AS FileSizeBytes,
                  storage_rel_path AS StorageRelPath,
                  nfce_access_key AS NfceAccessKey,
                  issuer_name AS IssuerName,
                  issued_on AS IssuedOn,
                  total_cents AS TotalCents,
                  created_at AS CreatedAt
              FROM receipts.receipt
              WHERE household_id = @HouseholdId
                AND transaction_id = @TransactionId
              ORDER BY created_at DESC, id DESC
              """
            : """
              SELECT
                  id AS Id,
                  transaction_id AS TransactionId,
                  file_name AS FileName,
                  content_type AS ContentType,
                  file_size_bytes AS FileSizeBytes,
                  storage_rel_path AS StorageRelPath,
                  nfce_access_key AS NfceAccessKey,
                  issuer_name AS IssuerName,
                  issued_on AS IssuedOn,
                  total_cents AS TotalCents,
                  created_at AS CreatedAt
              FROM receipts.receipt
              WHERE household_id = @HouseholdId
              ORDER BY created_at DESC, id DESC
              """;

        var receipts = (await connection.QueryAsync<ReceiptRow>(new CommandDefinition(
            sql,
            new { HouseholdId = householdId, TransactionId = transactionId },
            cancellationToken: cancellationToken))).ToList();

        if (receipts.Count == 0)
        {
            return new ReceiptsListResponse([]);
        }

        var receiptIds = receipts.Select(r => r.Id).ToArray();
        var itemRows = (await connection.QueryAsync<ReceiptItemRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                receipt_id AS ReceiptId,
                item_index AS ItemIndex,
                description AS Description,
                quantity AS Quantity,
                unit_price_cents AS UnitPriceCents,
                total_cents AS TotalCents,
                suggested_category AS SuggestedCategory
            FROM receipts.receipt_item
            WHERE receipt_id = ANY(@ReceiptIds)
            ORDER BY receipt_id, item_index ASC
            """,
            new { ReceiptIds = receiptIds },
            cancellationToken: cancellationToken))).ToList();

        var itemsByReceipt = itemRows
            .GroupBy(i => i.ReceiptId)
            .ToDictionary(
                g => g.Key,
                g => (IReadOnlyList<ReceiptItemDto>)g.Select(MapItem).ToList());

        var dtos = receipts.Select(r => MapReceipt(r, itemsByReceipt.GetValueOrDefault(r.Id) ?? [])).ToList();
        return new ReceiptsListResponse(dtos);
    }

    public async Task<(bool Ok, string? Error, ReceiptDto? Data)> UploadReceiptAsync(
        Guid householdId,
        UploadReceiptRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return (false, "Informe os dados do comprovante.", null);
        }

        var safeFileName = SanitizeFileName(request.FileName);
        if (string.IsNullOrWhiteSpace(safeFileName))
        {
            return (false, "Informe o nome do arquivo do comprovante.", null);
        }

        if (!TryNormalizeAllowedContentType(request.ContentType, out var contentType, out var contentTypeError))
        {
            return (false, contentTypeError, null);
        }

        if (string.IsNullOrWhiteSpace(request.ContentBase64))
        {
            return (false, "Informe o conteúdo do arquivo em Base64.", null);
        }

        var trimmedBase64 = request.ContentBase64.Trim();
        if (ExceedsMaxBase64Size(trimmedBase64))
        {
            return (false, "O comprovante excede o tamanho máximo de 10 MB.", null);
        }

        byte[] rawBytes;
        try
        {
            rawBytes = Convert.FromBase64String(trimmedBase64);
        }
        catch (FormatException)
        {
            return (false, "Conteúdo Base64 inválido.", null);
        }

        if (rawBytes.Length == 0)
        {
            return (false, "O arquivo do comprovante está vazio.", null);
        }

        if (rawBytes.Length > MaxFileSizeBytes)
        {
            return (false, "O comprovante excede o tamanho máximo de 10 MB.", null);
        }

        var receiptId = Guid.CreateVersion7();
        var storageRelPath = await fileStore.SaveEncryptedAsync(
            householdId,
            receiptId,
            rawBytes,
            cancellationToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        try
        {
            var saved = await connection.QuerySingleAsync<ReceiptRow>(new CommandDefinition(
                """
                INSERT INTO receipts.receipt (
                    id,
                    household_id,
                    transaction_id,
                    file_name,
                    content_type,
                    file_size_bytes,
                    storage_rel_path
                )
                VALUES (
                    @Id,
                    @HouseholdId,
                    @TransactionId,
                    @FileName,
                    @ContentType,
                    @FileSizeBytes,
                    @StorageRelPath
                )
                RETURNING
                    id AS Id,
                    transaction_id AS TransactionId,
                    file_name AS FileName,
                    content_type AS ContentType,
                    file_size_bytes AS FileSizeBytes,
                    storage_rel_path AS StorageRelPath,
                    nfce_access_key AS NfceAccessKey,
                    issuer_name AS IssuerName,
                    issued_on AS IssuedOn,
                    total_cents AS TotalCents,
                    created_at AS CreatedAt
                """,
                new
                {
                    Id = receiptId,
                    HouseholdId = householdId,
                    request.TransactionId,
                    FileName = safeFileName,
                    ContentType = contentType,
                    FileSizeBytes = (long)rawBytes.Length,
                    StorageRelPath = storageRelPath
                },
                cancellationToken: cancellationToken));

            return (true, null, MapReceipt(saved, []));
        }
        catch
        {
            fileStore.DeleteFile(storageRelPath);
            throw;
        }
    }

    public async Task<(bool Found, byte[]? Bytes, string? ContentType, string? FileName)> DownloadReceiptAsync(
        Guid householdId,
        Guid receiptId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<DownloadRow>(new CommandDefinition(
            """
            SELECT
                file_name AS FileName,
                content_type AS ContentType,
                storage_rel_path AS StorageRelPath
            FROM receipts.receipt
            WHERE id = @Id AND household_id = @HouseholdId
            """,
            new { Id = receiptId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (row is null || string.IsNullOrWhiteSpace(row.StorageRelPath))
        {
            return (false, null, null, null);
        }

        var plaintext = await fileStore.ReadDecryptedAsync(receiptId, row.StorageRelPath, cancellationToken);
        if (plaintext is null)
        {
            return (false, null, null, null);
        }

        return (true, plaintext, row.ContentType, row.FileName);
    }

    public async Task<bool> DeleteReceiptAsync(
        Guid householdId,
        Guid receiptId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var deleted = await connection.QuerySingleOrDefaultAsync<DeletedReceiptRow>(new CommandDefinition(
            """
            DELETE FROM receipts.receipt
            WHERE id = @Id AND household_id = @HouseholdId
            RETURNING id AS Id, storage_rel_path AS StorageRelPath
            """,
            new { Id = receiptId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (deleted is null)
        {
            return false;
        }

        fileStore.DeleteFile(deleted.StorageRelPath);
        return true;
    }

    public async Task<(int StatusCode, string? ErrorCode, string? Error, ParseNfceResponse? Data)> ParseNfceAsync(
        Guid householdId,
        ParseNfceRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return (StatusCodes.Status400BadRequest, "invalid_request", "Informe o XML ou a URL do QR Code da NFC-e.", null);
        }

        var hasXml = !string.IsNullOrWhiteSpace(request.Xml);
        if (hasXml)
        {
            // Enforce the 10 MB ceiling BEFORE parsing XML, regardless of save=true/false (ADR-025).
            if (request.Xml!.Length > MaxFileSizeBytes || Encoding.UTF8.GetByteCount(request.Xml) > MaxFileSizeBytes)
            {
                return (StatusCodes.Status400BadRequest, "payload_too_large", "O XML da NFC-e excede o tamanho máximo de 10 MB.", null);
            }

            // Require explicit household consent before extracting/categorizing NFC-e items (ADR-025).
            await using var consentConn = await dataSource.OpenConnectionAsync(cancellationToken);
            var itemAnalysisAccepted = await consentConn.ExecuteScalarAsync<bool?>(new CommandDefinition(
                """
                SELECT item_analysis_accepted
                FROM receipts.consent
                WHERE household_id = @HouseholdId
                """,
                new { HouseholdId = householdId },
                cancellationToken: cancellationToken));

            if (itemAnalysisAccepted != true)
            {
                return (
                    StatusCodes.Status403Forbidden,
                    "receipt_item_consent_required",
                    "Para ler e categorizar os itens da NFC-e, aceite primeiro o consentimento de leitura de itens em /api/v1/receipts/consent.",
                    null);
            }
        }

        var (ok, error, parsed) = NfceParser.Parse(request.Xml, request.QrUrl);
        if (!ok || parsed is null)
        {
            return (StatusCodes.Status400BadRequest, "invalid_nfce", error ?? "Não foi possível interpretar a NFC-e.", null);
        }

        var shouldSave = request.Save ?? true;
        Guid? savedId = null;

        if (shouldSave)
        {
            var receiptId = Guid.CreateVersion7();
            string? storageRelPath = null;
            string fileName;
            string contentType;
            long fileSizeBytes;

            if (hasXml)
            {
                var xmlBytes = Encoding.UTF8.GetBytes(request.Xml!.Trim());
                if (xmlBytes.Length > MaxFileSizeBytes)
                {
                    return (StatusCodes.Status400BadRequest, "payload_too_large", "O XML da NFC-e excede o tamanho máximo de 10 MB.", null);
                }

                storageRelPath = await fileStore.SaveEncryptedAsync(
                    householdId,
                    receiptId,
                    xmlBytes,
                    cancellationToken);
                fileName = parsed.AccessKey is not null ? $"nfce-{parsed.AccessKey}.xml" : $"nfce-{receiptId:N}.xml";
                contentType = "application/xml";
                fileSizeBytes = xmlBytes.Length;
            }
            else
            {
                fileName = parsed.AccessKey is not null ? $"nfce-{parsed.AccessKey}.txt" : $"nfce-{receiptId:N}.txt";
                contentType = "text/plain";
                fileSizeBytes = Encoding.UTF8.GetByteCount(request.QrUrl!.Trim());
            }

            await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                await connection.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO receipts.receipt (
                        id,
                        household_id,
                        transaction_id,
                        file_name,
                        content_type,
                        file_size_bytes,
                        storage_rel_path,
                        nfce_access_key,
                        issuer_name,
                        issued_on,
                        total_cents
                    )
                    VALUES (
                        @Id,
                        @HouseholdId,
                        @TransactionId,
                        @FileName,
                        @ContentType,
                        @FileSizeBytes,
                        @StorageRelPath,
                        @NfceAccessKey,
                        @IssuerName,
                        @IssuedOn,
                        @TotalCents
                    )
                    """,
                    new
                    {
                        Id = receiptId,
                        HouseholdId = householdId,
                        request.TransactionId,
                        FileName = fileName,
                        ContentType = contentType,
                        FileSizeBytes = fileSizeBytes,
                        StorageRelPath = storageRelPath,
                        NfceAccessKey = parsed.AccessKey,
                        parsed.IssuerName,
                        parsed.IssuedOn,
                        parsed.TotalCents
                    },
                    transaction: transaction,
                    cancellationToken: cancellationToken));

                foreach (var item in parsed.Items)
                {
                    await connection.ExecuteAsync(new CommandDefinition(
                        """
                        INSERT INTO receipts.receipt_item (
                            id,
                            receipt_id,
                            item_index,
                            description,
                            quantity,
                            unit_price_cents,
                            total_cents,
                            suggested_category
                        )
                        VALUES (
                            @Id,
                            @ReceiptId,
                            @ItemIndex,
                            @Description,
                            @Quantity,
                            @UnitPriceCents,
                            @TotalCents,
                            @SuggestedCategory
                        )
                        """,
                        new
                        {
                            Id = Guid.CreateVersion7(),
                            ReceiptId = receiptId,
                            item.ItemIndex,
                            item.Description,
                            item.Quantity,
                            item.UnitPriceCents,
                            item.TotalCents,
                            item.SuggestedCategory
                        },
                        transaction: transaction,
                        cancellationToken: cancellationToken));
                }

                await transaction.CommitAsync(cancellationToken);
                savedId = receiptId;
            }
            catch
            {
                fileStore.DeleteFile(storageRelPath);
                throw;
            }
        }

        return (StatusCodes.Status200OK, null, null, new ParseNfceResponse(
            savedId,
            shouldSave,
            request.TransactionId,
            parsed.AccessKey,
            parsed.State,
            parsed.IssuerName,
            parsed.IssuerCnpj,
            parsed.IssuedOn,
            parsed.TotalCents,
            parsed.QrPortalHost,
            parsed.Notice,
            parsed.Items));
    }

    internal static bool TryNormalizeAllowedContentType(
        string? rawContentType,
        out string normalized,
        out string? error)
    {
        normalized = string.Empty;
        error = null;

        if (string.IsNullOrWhiteSpace(rawContentType))
        {
            error = "Informe o tipo de conteúdo (MIME) do comprovante (JPEG, PNG, WebP, PDF ou XML).";
            return false;
        }

        if (!MediaTypeHeaderValue.TryParse(rawContentType.Trim(), out var parsed) ||
            string.IsNullOrWhiteSpace(parsed.MediaType))
        {
            error = "Tipo de conteúdo (MIME) inválido.";
            return false;
        }

        var mediaType = parsed.MediaType.Trim().ToLowerInvariant();
        if (!AllowedReceiptContentTypes.Contains(mediaType))
        {
            error = "Tipo de arquivo não permitido. Envie imagem (JPEG, PNG, WebP), PDF ou XML de NFC-e.";
            return false;
        }

        normalized = mediaType;
        return true;
    }

    private static bool ExceedsMaxBase64Size(string trimmedBase64)
    {
        // Fast upper bound before scanning whitespace (allows line breaks every 64 chars).
        if (trimmedBase64.Length > MaxBase64NonWhitespaceChars + (MaxBase64NonWhitespaceChars / 64) + 64)
        {
            return true;
        }

        var nonWhitespaceCount = 0;
        var trailingEquals = 0;
        for (var i = 0; i < trimmedBase64.Length; i++)
        {
            var ch = trimmedBase64[i];
            if (!char.IsWhiteSpace(ch))
            {
                nonWhitespaceCount++;
                trailingEquals = ch == '=' ? trailingEquals + 1 : 0;
            }
        }

        var estimatedBytes = (nonWhitespaceCount / 4L) * 3L - Math.Min(trailingEquals, 2);
        return estimatedBytes > MaxFileSizeBytes;
    }

    public async Task<(int StatusCode, string? Error, ApplyReceiptSplitsResponse? Data)> ApplySplitsAsync(
        Guid householdId,
        Guid receiptId,
        ApplyReceiptSplitsRequest? request,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var receipt = await connection.QuerySingleOrDefaultAsync<ReceiptRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                transaction_id AS TransactionId,
                file_name AS FileName,
                content_type AS ContentType,
                file_size_bytes AS FileSizeBytes,
                storage_rel_path AS StorageRelPath,
                nfce_access_key AS NfceAccessKey,
                issuer_name AS IssuerName,
                issued_on AS IssuedOn,
                total_cents AS TotalCents,
                created_at AS CreatedAt
            FROM receipts.receipt
            WHERE id = @Id AND household_id = @HouseholdId
            """,
            new { Id = receiptId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        if (receipt is null)
        {
            return (404, "Comprovante não encontrado.", null);
        }

        var transactionId = request?.TransactionId ?? receipt.TransactionId;
        if (!transactionId.HasValue || transactionId.Value == Guid.Empty)
        {
            return (400, "Informe o identificador da transação para aplicar a divisão.", null);
        }

        var items = (await connection.QueryAsync<ReceiptItemRow>(new CommandDefinition(
            """
            SELECT
                id AS Id,
                receipt_id AS ReceiptId,
                item_index AS ItemIndex,
                description AS Description,
                quantity AS Quantity,
                unit_price_cents AS UnitPriceCents,
                total_cents AS TotalCents,
                suggested_category AS SuggestedCategory
            FROM receipts.receipt_item
            WHERE receipt_id = @ReceiptId
            ORDER BY item_index ASC
            """,
            new { ReceiptId = receiptId },
            cancellationToken: cancellationToken))).ToList();

        if (items.Count == 0)
        {
            return (400, "Este comprovante não possui itens detalhados para dividir a transação.", null);
        }

        // Look up the target transaction to align exact cents and sign (RN-24 / ADR-013).
        var tx = await FindTransactionAsync(householdId, transactionId.Value, receipt.IssuedOn, cancellationToken);
        if (tx is null)
        {
            return (404, "Transação não encontrada.", null);
        }

        var targetMagnitude = Math.Abs(tx.AmountCents);
        if (targetMagnitude <= 0)
        {
            return (400, "O valor da transação precisa ser diferente de zero para aplicar a divisão.", null);
        }

        var allocatedMagnitudes = AllocateExactCents(items, targetMagnitude);
        var sign = Math.Sign(tx.AmountCents);
        var signedSplits = BuildSplitInputs(items, allocatedMagnitudes, sign);

        var (ok, splitError) = await splitWriter.ReplaceTransactionSplitsAsync(
            householdId,
            transactionId.Value,
            signedSplits,
            cancellationToken);

        if (!ok)
        {
            return (400, splitError ?? "Não foi possível aplicar a divisão na transação.", null);
        }

        var appliedSplits = signedSplits;

        if (receipt.TransactionId != transactionId.Value)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE receipts.receipt
                SET transaction_id = @TransactionId
                WHERE id = @Id AND household_id = @HouseholdId
                """,
                new { Id = receiptId, HouseholdId = householdId, TransactionId = transactionId.Value },
                cancellationToken: cancellationToken));
        }

        var appliedDtos = appliedSplits
            .Select(s => new AppliedReceiptSplitDto(s.Description, s.AmountCents, s.Category, s.Essentiality))
            .ToList();

        return (200, null, new ApplyReceiptSplitsResponse(
            receiptId,
            transactionId.Value,
            appliedDtos.Count,
            appliedDtos.Sum(s => s.AmountCents),
            appliedDtos));
    }

    private async Task<BankingTransactionFact?> FindTransactionAsync(
        Guid householdId,
        Guid transactionId,
        DateOnly? issuedOn,
        CancellationToken cancellationToken)
    {
        if (issuedOn.HasValue)
        {
            var near = await bankingReader.GetTransactionsInRangeAsync(
                householdId,
                issuedOn.Value.AddDays(-45),
                issuedOn.Value.AddDays(46),
                cancellationToken);
            var foundNear = near.FirstOrDefault(t => t.Id == transactionId);
            if (foundNear is not null)
            {
                return foundNear;
            }
        }

        var wide = await bankingReader.GetTransactionsInRangeAsync(
            householdId,
            new DateOnly(2000, 1, 1),
            new DateOnly(2100, 1, 1),
            cancellationToken);
        return wide.FirstOrDefault(t => t.Id == transactionId);
    }

    /// <summary>
    /// Distributes targetMagnitude across receipt items in exact integer cents,
    /// placing any rounding or discount residual cent on the largest part (ADR-013, RN-24).
    /// </summary>
    private static long[] AllocateExactCents(List<ReceiptItemRow> items, long targetMagnitude)
    {
        var count = items.Count;
        var rawTotals = items.Select(i => Math.Max(0L, i.TotalCents)).ToArray();
        var rawSum = rawTotals.Sum();

        if (rawSum == targetMagnitude)
        {
            return rawTotals;
        }

        var allocated = new long[count];
        if (rawSum > 0)
        {
            for (var i = 0; i < count; i++)
            {
                var scaled = (decimal)rawTotals[i] * targetMagnitude / rawSum;
                allocated[i] = decimal.ToInt64(Math.Round(scaled, 0, MidpointRounding.AwayFromZero));
            }
        }
        else
        {
            var equalPart = targetMagnitude / count;
            for (var i = 0; i < count; i++)
            {
                allocated[i] = equalPart;
            }
        }

        var diff = targetMagnitude - allocated.Sum();
        if (diff != 0)
        {
            var largestIdx = 0;
            for (var i = 1; i < count; i++)
            {
                if (allocated[i] > allocated[largestIdx] ||
                    (allocated[i] == allocated[largestIdx] && rawTotals[i] > rawTotals[largestIdx]))
                {
                    largestIdx = i;
                }
            }

            allocated[largestIdx] += diff;
        }

        return allocated;
    }

    private static List<BankingSplitInput> BuildSplitInputs(
        List<ReceiptItemRow> items,
        long[] magnitudes,
        long sign)
    {
        var splits = new List<BankingSplitInput>(items.Count);
        for (var i = 0; i < items.Count; i++)
        {
            if (magnitudes[i] == 0)
            {
                continue;
            }

            var item = items[i];
            var essentiality = SuggestEssentiality(item.SuggestedCategory);
            splits.Add(new BankingSplitInput(
                item.Description,
                sign * magnitudes[i],
                item.SuggestedCategory,
                essentiality));
        }

        return splits;
    }

    private static string? SuggestEssentiality(string? category) => category switch
    {
        "housing" or "health" => "essential",
        "food" or "transport" or "education" or "services" => "important",
        "leisure" or "shopping" or "other" => "flexible",
        _ => null
    };

    private static string SanitizeFileName(string? fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName))
        {
            return string.Empty;
        }

        var leaf = Path.GetFileName(fileName.Trim());
        return leaf.Length > 200 ? leaf[..200] : leaf;
    }

    private static ReceiptDto MapReceipt(ReceiptRow row, IReadOnlyList<ReceiptItemDto> items) =>
        new(
            row.Id,
            row.TransactionId,
            row.FileName,
            row.ContentType,
            row.FileSizeBytes,
            !string.IsNullOrWhiteSpace(row.StorageRelPath),
            row.NfceAccessKey,
            row.IssuerName,
            row.IssuedOn,
            row.TotalCents,
            row.CreatedAt,
            items);

    private static ReceiptItemDto MapItem(ReceiptItemRow row) =>
        new(
            row.Id,
            row.ItemIndex,
            row.Description,
            row.Quantity,
            row.UnitPriceCents,
            row.TotalCents,
            row.SuggestedCategory);

    private sealed record ConsentRow(
        bool ItemAnalysisAccepted,
        bool DietaryNotesAccepted,
        DateTimeOffset DecidedAt);

    private sealed record ReceiptRow(
        Guid Id,
        Guid? TransactionId,
        string FileName,
        string ContentType,
        long FileSizeBytes,
        string? StorageRelPath,
        string? NfceAccessKey,
        string? IssuerName,
        DateOnly? IssuedOn,
        long? TotalCents,
        DateTimeOffset CreatedAt);

    private sealed record ReceiptItemRow(
        Guid Id,
        Guid ReceiptId,
        int ItemIndex,
        string Description,
        decimal Quantity,
        long UnitPriceCents,
        long TotalCents,
        string? SuggestedCategory);

    private sealed record DownloadRow(
        string FileName,
        string ContentType,
        string? StorageRelPath);

    private sealed record DeletedReceiptRow(
        Guid Id,
        string? StorageRelPath);
}
