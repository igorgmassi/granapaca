using System.Net.Http.Json;
using System.Text.Json;
using GranaPaCa.Modules.Categorization.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GranaPaCa.Modules.Banking.Providers;

internal sealed class PluggyAuthTokenCache
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private string? _apiKey;
    private DateTimeOffset _expiresAt = DateTimeOffset.MinValue;

    public async Task<string> GetOrFetchAsync(
        Func<CancellationToken, Task<string>> fetchToken,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrEmpty(_apiKey) && DateTimeOffset.UtcNow < _expiresAt)
        {
            return _apiKey;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!string.IsNullOrEmpty(_apiKey) && DateTimeOffset.UtcNow < _expiresAt)
            {
                return _apiKey;
            }

            _apiKey = await fetchToken(cancellationToken);
            _expiresAt = DateTimeOffset.UtcNow.AddMinutes(100);
            return _apiKey;
        }
        finally
        {
            _gate.Release();
        }
    }

    public void Invalidate()
    {
        _apiKey = null;
        _expiresAt = DateTimeOffset.MinValue;
    }
}

/// <summary>
/// Direct Pluggy Open Finance REST client without third-party SDKs (ADR-004).
/// </summary>
internal sealed class PluggyBankProvider(
    HttpClient httpClient,
    IConfiguration configuration,
    PluggyAuthTokenCache tokenCache,
    ILogger<PluggyBankProvider> logger) : IBankProvider
{
    private readonly string? _clientId = configuration["Pluggy:ClientId"] ?? configuration["PLUGGY_CLIENT_ID"];
    private readonly string? _clientSecret = configuration["Pluggy:ClientSecret"] ?? configuration["PLUGGY_CLIENT_SECRET"];
    private readonly TimeZoneInfo _instanceTimeZone = DateParser.ResolveInstanceTimeZone(configuration);

    public string ProviderName => "pluggy";

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(_clientId) && !string.IsNullOrWhiteSpace(_clientSecret);

    public async Task<ProviderConnectionData> FetchConnectionAsync(
        string externalItemId,
        CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
        {
            throw new InvalidOperationException("Pluggy credentials are not configured.");
        }

        var apiKey = await GetApiKeyAsync(cancellationToken);

        using var itemDoc = await GetJsonAsync($"/items/{Uri.EscapeDataString(externalItemId)}", apiKey, cancellationToken);
        var itemRoot = itemDoc.RootElement;

        var institutionName = GetString(itemRoot, "connector", "name") ?? "Instituição conectada";
        var primaryColor = GetString(itemRoot, "connector", "primaryColor");
        var brandColor = NormalizeHexColor(primaryColor);
        var rawStatus = GetString(itemRoot, "status") ?? "UPDATED";
        var errorCode = GetString(itemRoot, "error", "code");
        var consentExpiresAt = TryGetDateTimeOffset(itemRoot, "consentExpiresAt");

        var mappedStatus = MapItemStatus(rawStatus, errorCode, consentExpiresAt);

        using var accountsDoc = await GetJsonAsync(
            $"/accounts?itemId={Uri.EscapeDataString(externalItemId)}",
            apiKey,
            cancellationToken);

        var accounts = new List<ProviderAccountData>();
        if (accountsDoc.RootElement.TryGetProperty("results", out var resultsEl) &&
            resultsEl.ValueKind == JsonValueKind.Array)
        {
            foreach (var accEl in resultsEl.EnumerateArray())
            {
                var currency = GetString(accEl, "currencyCode") ?? "BRL";
                if (!string.Equals(currency, "BRL", StringComparison.OrdinalIgnoreCase))
                {
                    logger.LogWarning("Skipping non-BRL Pluggy account due to ADR-013 constraint.");
                    continue;
                }

                var externalAccountId = GetString(accEl, "id");
                if (string.IsNullOrWhiteSpace(externalAccountId))
                {
                    continue;
                }

                var accountType = GetString(accEl, "type") ?? "BANK";
                var accountSubType = GetString(accEl, "subtype") ?? "CHECKING_ACCOUNT";
                var kind = MapAccountKind(accountType, accountSubType);
                var name = GetString(accEl, "name") ?? (kind == "credit_card" ? "Cartão de crédito" : "Conta bancária");
                var lastFourDigits = BankingTaxonomy.ExtractLastFourDigits(GetString(accEl, "number"));

                var rawBalance = TryGetDecimal(accEl, "balance") ?? 0m;
                long balanceCents;
                try
                {
                    balanceCents = MoneyConverter.ConvertDecimalToCents(rawBalance);
                    if (kind == "credit_card" && balanceCents > 0)
                    {
                        balanceCents = -balanceCents;
                    }
                }
                catch (InvalidOperationException)
                {
                    logger.LogWarning("Rejected account balance with fractional cents (ADR-013).");
                    balanceCents = 0;
                }

                var bills = kind == "credit_card"
                    ? await FetchBillsAsync(externalAccountId, apiKey, cancellationToken)
                    : [];

                var transactions = await FetchTransactionsAsync(externalAccountId, apiKey, cancellationToken);

                accounts.Add(new ProviderAccountData(
                    externalAccountId,
                    name,
                    kind,
                    lastFourDigits,
                    "BRL",
                    0,
                    balanceCents,
                    bills,
                    transactions));
            }
        }

        return new ProviderConnectionData(
            externalItemId,
            institutionName,
            brandColor,
            mappedStatus,
            consentExpiresAt,
            errorCode,
            accounts);
    }

    private async Task<IReadOnlyList<ProviderCardBillData>> FetchBillsAsync(
        string externalAccountId,
        string apiKey,
        CancellationToken cancellationToken)
    {
        var bills = new List<ProviderCardBillData>();
        var today = DateParser.TodayInTimeZone(_instanceTimeZone);

        try
        {
            using var doc = await GetJsonAsync(
                $"/bills?accountId={Uri.EscapeDataString(externalAccountId)}",
                apiKey,
                cancellationToken);

            if (!doc.RootElement.TryGetProperty("results", out var resultsEl) ||
                resultsEl.ValueKind != JsonValueKind.Array)
            {
                return bills;
            }

            foreach (var billEl in resultsEl.EnumerateArray())
            {
                var externalBillId = GetString(billEl, "id");
                var rawDue = GetString(billEl, "dueDate");
                if (string.IsNullOrWhiteSpace(externalBillId) || string.IsNullOrWhiteSpace(rawDue))
                {
                    continue;
                }

                var dueOn = DateParser.ParseProviderDate(rawDue, _instanceTimeZone);
                var rawClosing = GetString(billEl, "closingDate");
                var closingOn = string.IsNullOrWhiteSpace(rawClosing)
                    ? dueOn.AddDays(-7)
                    : DateParser.ParseProviderDate(rawClosing, _instanceTimeZone);

                var periodMonth = new DateOnly(closingOn.Year, closingOn.Month, 1);
                var totalDecimal = TryGetDecimal(billEl, "totalAmount") ?? 0m;
                long totalCents;
                try
                {
                    totalCents = Math.Abs(MoneyConverter.ConvertDecimalToCents(totalDecimal));
                }
                catch (InvalidOperationException)
                {
                    logger.LogWarning("Rejected card bill with fractional cents (ADR-013).");
                    continue;
                }

                var isOpen = closingOn >= today;
                bills.Add(new ProviderCardBillData(
                    externalBillId,
                    periodMonth,
                    closingOn,
                    dueOn,
                    totalCents,
                    isOpen,
                    billEl.GetRawText()));
            }
        }
        catch (HttpRequestException ex)
        {
            logger.LogWarning("Could not fetch card bills from Pluggy; status={StatusCode}.", (int?)ex.StatusCode);
        }

        return bills;
    }

    private async Task<IReadOnlyList<ProviderTransactionData>> FetchTransactionsAsync(
        string externalAccountId,
        string apiKey,
        CancellationToken cancellationToken)
    {
        var transactions = new List<ProviderTransactionData>();
        var page = 1;
        var totalPages = 1;

        while (page <= totalPages && page <= 50)
        {
            using var doc = await GetJsonAsync(
                $"/transactions?accountId={Uri.EscapeDataString(externalAccountId)}&pageSize=500&page={page}",
                apiKey,
                cancellationToken);

            var root = doc.RootElement;
            if (root.TryGetProperty("totalPages", out var totalPagesEl) && totalPagesEl.TryGetInt32(out var tp))
            {
                totalPages = tp;
            }

            if (root.TryGetProperty("results", out var resultsEl) && resultsEl.ValueKind == JsonValueKind.Array)
            {
                foreach (var txEl in resultsEl.EnumerateArray())
                {
                    var currency = GetString(txEl, "currencyCode") ?? "BRL";
                    if (!string.Equals(currency, "BRL", StringComparison.OrdinalIgnoreCase))
                    {
                        logger.LogWarning("Rejected non-BRL Pluggy transaction (ADR-013).");
                        continue;
                    }

                    var externalId = GetString(txEl, "id");
                    var rawDate = GetString(txEl, "date");
                    var description = GetString(txEl, "description") ?? "Transação";
                    var rawAmount = TryGetDecimal(txEl, "amount");
                    if (string.IsNullOrWhiteSpace(externalId) ||
                        string.IsNullOrWhiteSpace(rawDate) ||
                        rawAmount is null)
                    {
                        continue;
                    }

                    long amountCents;
                    try
                    {
                        amountCents = MoneyConverter.ConvertDecimalToCents(rawAmount.Value);
                    }
                    catch (InvalidOperationException)
                    {
                        logger.LogWarning("Rejected Pluggy transaction with fractional cents (ADR-013).");
                        continue;
                    }

                    var txType = GetString(txEl, "type");
                    if (string.Equals(txType, "DEBIT", StringComparison.OrdinalIgnoreCase) && amountCents > 0)
                    {
                        amountCents = -amountCents;
                    }
                    else if (string.Equals(txType, "CREDIT", StringComparison.OrdinalIgnoreCase) && amountCents < 0)
                    {
                        amountCents = -amountCents;
                    }

                    var occurredOn = DateParser.ParseProviderDate(rawDate, _instanceTimeZone);
                    var rawStatus = GetString(txEl, "status");
                    var status = string.Equals(rawStatus, "PENDING", StringComparison.OrdinalIgnoreCase)
                        ? "pending"
                        : "posted";

                    var merchantCnpj = MerchantNormalizer.NormalizeCnpj(GetString(txEl, "merchant", "cnpj"));
                    var billId = GetString(txEl, "creditCardMetadata", "billId");
                    var installmentNumber = TryGetInt32(txEl, "creditCardMetadata", "installmentNumber");
                    var installmentTotal = TryGetInt32(txEl, "creditCardMetadata", "totalInstallments");

                    DateOnly? purchaseOn = null;
                    if (installmentNumber is > 1 && installmentTotal is > 1)
                    {
                        purchaseOn = occurredOn.AddMonths(-(installmentNumber.Value - 1));
                    }

                    transactions.Add(new ProviderTransactionData(
                        "pluggy",
                        externalId,
                        occurredOn,
                        purchaseOn,
                        description,
                        merchantCnpj,
                        amountCents,
                        "BRL",
                        status,
                        billId,
                        installmentNumber,
                        installmentTotal,
                        txEl.GetRawText()));
                }
            }

            page++;
        }

        return transactions;
    }

    private Task<string> GetApiKeyAsync(CancellationToken cancellationToken) =>
        tokenCache.GetOrFetchAsync(async ct =>
        {
            using var response = await httpClient.PostAsJsonAsync(
                "/auth",
                new { clientId = _clientId, clientSecret = _clientSecret },
                ct);
            response.EnsureSuccessStatusCode();

            using var doc = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(ct),
                cancellationToken: ct);

            return GetString(doc.RootElement, "apiKey")
                ?? throw new InvalidOperationException("Pluggy auth response did not include apiKey.");
        }, cancellationToken);

    private async Task<JsonDocument> GetJsonAsync(
        string relativeUrl,
        string apiKey,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, relativeUrl);
        request.Headers.Add("X-API-KEY", apiKey);

        using var response = await httpClient.SendAsync(request, cancellationToken);
        if ((int)response.StatusCode == 401)
        {
            tokenCache.Invalidate();
        }

        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
    }

    private static string MapItemStatus(
        string rawStatus,
        string? errorCode,
        DateTimeOffset? consentExpiresAt)
    {
        if (string.Equals(errorCode, "USER_AUTHORIZATION_EXPIRED", StringComparison.OrdinalIgnoreCase) ||
            (consentExpiresAt.HasValue && consentExpiresAt.Value <= DateTimeOffset.UtcNow))
        {
            return "expired";
        }

        return rawStatus.ToUpperInvariant() switch
        {
            "UPDATED" => "up_to_date",
            "UPDATING" or "WAITING_USER_INPUT" => "delayed",
            "LOGIN_ERROR" or "OUTDATED" => "error",
            _ => string.IsNullOrEmpty(errorCode) ? "up_to_date" : "error"
        };
    }

    private static string MapAccountKind(string type, string subtype)
    {
        if (string.Equals(type, "CREDIT", StringComparison.OrdinalIgnoreCase))
        {
            return "credit_card";
        }

        if (string.Equals(subtype, "SAVINGS_ACCOUNT", StringComparison.OrdinalIgnoreCase))
        {
            return "savings";
        }

        return "checking";
    }

    private static string NormalizeHexColor(string? color)
    {
        if (string.IsNullOrWhiteSpace(color))
        {
            return "#A0521A";
        }

        var trimmed = color.Trim();
        return trimmed.StartsWith('#') ? trimmed : $"#{trimmed}";
    }

    private static string? GetString(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var segment in path)
        {
            if (current.ValueKind != JsonValueKind.Object || !current.TryGetProperty(segment, out current))
            {
                return null;
            }
        }

        return current.ValueKind == JsonValueKind.String ? current.GetString() : null;
    }

    private static decimal? TryGetDecimal(JsonElement root, string property)
    {
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty(property, out var element))
        {
            return null;
        }

        if (element.ValueKind == JsonValueKind.Number && element.TryGetDecimal(out var value))
        {
            return value;
        }

        return null;
    }

    private static int? TryGetInt32(JsonElement root, params string[] path)
    {
        var current = root;
        foreach (var segment in path)
        {
            if (current.ValueKind != JsonValueKind.Object || !current.TryGetProperty(segment, out current))
            {
                return null;
            }
        }

        return current.ValueKind == JsonValueKind.Number && current.TryGetInt32(out var value) ? value : null;
    }

    private static DateTimeOffset? TryGetDateTimeOffset(JsonElement root, string property)
    {
        var raw = GetString(root, property);
        return !string.IsNullOrWhiteSpace(raw) && DateTimeOffset.TryParse(raw, out var dto)
            ? dto.ToUniversalTime()
            : null;
    }
}
