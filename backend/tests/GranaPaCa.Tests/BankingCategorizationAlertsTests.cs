using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using GranaPaCa.Modules.Alerts.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class BankingCategorizationAlertsTests : IAsyncLifetime
{
    private readonly ApiFactory _api = new();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public ValueTask InitializeAsync() => _api.InitializeAsync();
    public ValueTask DisposeAsync() => _api.DisposeAsync();

    [Fact]
    public async Task End_to_end_synthetic_sync_queries_adjustments_rules_profiles_and_alerts()
    {
        var (client, householdId) = await CreateAuthenticatedClientAsync();

        // 1. Sync synthetic provider twice -> idempotent deduplication, transfers paired, raw payloads encrypted.
        var sync1Resp = await client.PostAsync("/api/v1/connections/sync", null, Ct);
        Assert.Equal(HttpStatusCode.OK, sync1Resp.StatusCode);
        var sync1 = await sync1Resp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(2, sync1.GetProperty("connectionsProcessed").GetInt32());
        Assert.True(sync1.GetProperty("transactionsInserted").GetInt32() >= 70);
        Assert.True(sync1.GetProperty("transfersLinked").GetInt32() > 0);

        var sync2Resp = await client.PostAsync("/api/v1/connections/sync", null, Ct);
        Assert.Equal(HttpStatusCode.OK, sync2Resp.StatusCode);
        var sync2 = await sync2Resp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(0, sync2.GetProperty("transactionsInserted").GetInt32());
        Assert.Equal(0, sync2.GetProperty("transactionsVersioned").GetInt32());

        // Verify RNF-06 (encrypted raw payload) and ADR-012 (append-only triggers).
        await using (var conn = await _api.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync(Ct))
        {
            await using var payloadCmd = conn.CreateCommand();
            payloadCmd.CommandText = "SELECT raw_payload_enc FROM banking.transaction_version WHERE raw_payload_enc IS NOT NULL LIMIT 1";
            var rawEnc = (byte[])(await payloadCmd.ExecuteScalarAsync(Ct))!;
            Assert.DoesNotContain("Supermercado", Encoding.UTF8.GetString(rawEnc));

            await using var updateCmd = conn.CreateCommand();
            updateCmd.CommandText = "UPDATE banking.transaction_version SET description = 'tampered' WHERE version_number = 1";
            var pgEx = await Assert.ThrowsAsync<PostgresException>(() => updateCmd.ExecuteNonQueryAsync(Ct));
            Assert.Contains("append-only", pgEx.MessageText, StringComparison.OrdinalIgnoreCase);
        }

        // 2. RF-16 & RF-17 & RF-19: Summary without double counting; per-bank totals add up to whole.
        var summaryAll = await client.GetFromJsonAsync<JsonElement>("/api/v1/summary?month=2026-03", Ct);
        var spentAll = summaryAll.GetProperty("spentCents").GetInt64();
        var receivedAll = summaryAll.GetProperty("receivedCents").GetInt64();
        var leftoverAll = summaryAll.GetProperty("leftoverCents").GetInt64();
        var balanceAll = summaryAll.GetProperty("balanceCents").GetInt64();
        Assert.True(summaryAll.GetProperty("hasConnections").GetBoolean());
        Assert.Equal(receivedAll - spentAll, leftoverAll);
        Assert.True(summaryAll.GetProperty("cardBillCents").GetInt64() > 0);

        var banksResp = await client.GetFromJsonAsync<JsonElement>("/api/v1/banks", Ct);
        var banks = banksResp.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(2, banks.Count);

        long sumBankBalance = 0, sumBankSpent = 0, sumBankReceived = 0;
        foreach (var bank in banks)
        {
            var bankId = bank.GetProperty("id").GetGuid();
            var bankSummary = await client.GetFromJsonAsync<JsonElement>($"/api/v1/summary?month=2026-03&bankId={bankId}", Ct);
            sumBankBalance += bankSummary.GetProperty("balanceCents").GetInt64();
            sumBankSpent += bankSummary.GetProperty("spentCents").GetInt64();
            sumBankReceived += bankSummary.GetProperty("receivedCents").GetInt64();
        }
        Assert.Equal(balanceAll, sumBankBalance);
        Assert.Equal(spentAll, sumBankSpent);
        Assert.Equal(receivedAll, sumBankReceived);

        // 3. RF-20: Credit card shows only last 4 digits, open & closed bills, and installment purchases.
        var auroraBank = banks.First(b => b.GetProperty("institutionName").GetString()!.Contains("Aurora"));
        var auroraDetail = await client.GetFromJsonAsync<JsonElement>($"/api/v1/banks/{auroraBank.GetProperty("id").GetGuid()}", Ct);
        var cardAccount = auroraDetail.GetProperty("accounts").EnumerateArray()
            .First(a => a.GetProperty("kind").GetString() == "credit_card");
        Assert.Equal("4821", cardAccount.GetProperty("lastFourDigits").GetString());

        var cardBills = await client.GetFromJsonAsync<JsonElement>($"/api/v1/cards/{cardAccount.GetProperty("id").GetGuid()}/bills", Ct);
        var billsArray = cardBills.GetProperty("items").EnumerateArray().ToList();
        Assert.True(billsArray.Count >= 3);
        var openBill = billsArray.First(b => b.GetProperty("isOpen").GetBoolean());
        var billDetail = await client.GetFromJsonAsync<JsonElement>($"/api/v1/cards/bills/{openBill.GetProperty("id").GetGuid()}", Ct);
        var billTxs = billDetail.GetProperty("purchases").EnumerateArray().ToList();
        Assert.Contains(billTxs, tx =>
            tx.GetProperty("installmentNumber").ValueKind == JsonValueKind.Number
            && tx.GetProperty("installmentTotal").GetInt32() == 10);

        // 4. RF-18 & RF-34 & RF-35 & RF-36: Accent-insensitive search + charts match filtered history!
        var searchResp = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions?search=FARMACIA", Ct);
        Assert.True(searchResp.GetProperty("totalCount").GetInt32() >= 1);
        Assert.All(searchResp.GetProperty("items").EnumerateArray(), item =>
            Assert.Contains("Farmácia", item.GetProperty("description").GetString()!));

        var marchExpenses = await client.GetFromJsonAsync<JsonElement>(
            "/api/v1/transactions?from=2026-03-01&to=2026-04-01&kind=expense&pageSize=200", Ct);
        var donut = await client.GetFromJsonAsync<JsonElement>(
            "/api/v1/spending/donut?from=2026-03-01&to=2026-04-01", Ct);
        var ranking = await client.GetFromJsonAsync<JsonElement>(
            "/api/v1/spending/ranking?from=2026-03-01&to=2026-04-01", Ct);

        Assert.Equal(-marchExpenses.GetProperty("totalCents").GetInt64(), donut.GetProperty("totalCents").GetInt64());
        Assert.Equal(donut.GetProperty("totalCents").GetInt64(), ranking.GetProperty("totalCents").GetInt64());
        Assert.True(donut.GetProperty("slices").GetArrayLength() <= 5);

        // 5. RF-31: Review queue contains uncategorized merchant grouped with count.
        var reviewQueue = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions/review-queue", Ct);
        var queueItems = reviewQueue.GetProperty("groups").EnumerateArray().ToList();
        var armarinhoGroup = queueItems.First(g =>
            g.GetProperty("merchantNormalized").GetString()!.Contains("armarinho"));
        Assert.Equal(2, armarinhoGroup.GetProperty("count").GetInt32());
        var firstUncatTxId = armarinhoGroup.GetProperty("sampleTransactionIds")[0].GetGuid();

        // 6. RF-24 & RF-25: Adjust category independently of essentiality, then undo -> append-only history!
        var txDetailBefore = await client.GetFromJsonAsync<JsonElement>($"/api/v1/transactions/{firstUncatTxId}", Ct);
        var origEssentiality = txDetailBefore.GetProperty("essentiality").ValueKind == JsonValueKind.Null
            ? null
            : txDetailBefore.GetProperty("essentiality").GetString();

        var adjustResp = await client.PostAsJsonAsync($"/api/v1/transactions/{firstUncatTxId}/adjustments", new
        {
            category = "shopping",
            reason = "Material de costura para casa",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, adjustResp.StatusCode);
        var adjustJson = await adjustResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(1, adjustJson.GetProperty("similarCount").GetInt32()); // 1 other similar Armarinho Estrela tx!
        var appliedAdjId = adjustJson.GetProperty("appliedAdjustments")[0].GetProperty("id").GetGuid();

        var txDetailAfter = await client.GetFromJsonAsync<JsonElement>($"/api/v1/transactions/{firstUncatTxId}", Ct);
        Assert.Equal("shopping", txDetailAfter.GetProperty("category").GetString());
        Assert.Equal(
            origEssentiality,
            txDetailAfter.GetProperty("essentiality").ValueKind == JsonValueKind.Null
                ? null
                : txDetailAfter.GetProperty("essentiality").GetString());

        // Undo the adjustment -> restores null category and appends undo entry to history!
        var undoResp = await client.PostAsync(
            $"/api/v1/transactions/{firstUncatTxId}/adjustments/{appliedAdjId}/undo", null, Ct);
        Assert.Equal(HttpStatusCode.OK, undoResp.StatusCode);
        var txDetailUndone = await client.GetFromJsonAsync<JsonElement>($"/api/v1/transactions/{firstUncatTxId}", Ct);
        Assert.Equal(JsonValueKind.Null, txDetailUndone.GetProperty("category").ValueKind);
        Assert.Equal(2, txDetailUndone.GetProperty("adjustments").GetArrayLength());

        // 7. RF-26 & RF-27: Create user rule -> classifies both Armarinho transactions; disabling reverts them.
        var createRuleResp = await client.PostAsJsonAsync("/api/v1/rules", new
        {
            name = "Armarinho Estrela",
            matchMerchant = "Armarinho Estrela",
            category = "shopping",
            essentiality = "flexible",
            explanation = "Compras de armarinho",
        }, Ct);
        Assert.Equal(HttpStatusCode.Created, createRuleResp.StatusCode);
        var ruleJson = await createRuleResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var ruleId = ruleJson.GetProperty("id").GetGuid();
        Assert.Equal(2, ruleJson.GetProperty("matchCount").GetInt32());

        var reviewQueueAfterRule = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions/review-queue", Ct);
        Assert.Equal(0, reviewQueueAfterRule.GetProperty("totalTransactions").GetInt32());

        // Disable rule -> falls back to uncategorized.
        var disableRuleResp = await client.PatchAsJsonAsync($"/api/v1/rules/{ruleId}", new { isActive = false }, Ct);
        Assert.Equal(HttpStatusCode.OK, disableRuleResp.StatusCode);
        var reviewQueueAfterDisable = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions/review-queue", Ct);
        Assert.Equal(2, reviewQueueAfterDisable.GetProperty("totalTransactions").GetInt32());

        // 8. RF-08: Profile catalog, preview, and saving profile rules without touching manual adjustments.
        var catalog = await client.GetFromJsonAsync<JsonElement>("/api/v1/profiles/catalog", Ct);
        Assert.True(catalog.GetProperty("occupations").GetArrayLength() >= 5);

        var previewResp = await client.PostAsJsonAsync("/api/v1/profiles/preview", new
        {
            occupations = new[] { "desenvolvedor" },
            homeTraits = new[] { "casa-sozinho" },
            transportModes = new[] { "transporte-aplicativo" },
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, previewResp.StatusCode);
        var previewJson = await previewResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var templateIds = previewJson.GetProperty("rules").EnumerateArray()
            .Select(r => r.GetProperty("templateId").GetString()!).ToArray();
        Assert.NotEmpty(templateIds);

        var saveProfilesResp = await client.PutAsJsonAsync("/api/v1/profiles", new
        {
            occupations = new[] { "desenvolvedor" },
            homeTraits = new[] { "casa-sozinho" },
            transportModes = new[] { "transporte-aplicativo" },
            acceptedRuleIds = templateIds,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, saveProfilesResp.StatusCode);

        // 9. RF-56: Alerts deduplication, unread count, mark read, and auto-resolve!
        var publisher = _api.Services.GetRequiredService<IAlertPublisher>();
        await publisher.RaiseAsync(new AlertRequest(
            householdId,
            "consent_expiring:demo-aurora",
            "consent_expiring",
            "warning",
            "Autorização perto de vencer",
            "A conexão com o Banco Aurora vence em 15 dias.",
            "connections"), Ct);
        // Raising the same dedupKey a second time does not create a duplicate.
        await publisher.RaiseAsync(new AlertRequest(
            householdId,
            "consent_expiring:demo-aurora",
            "consent_expiring",
            "warning",
            "Autorização perto de vencer",
            "Duplicado ignorado.",
            "connections"), Ct);

        var alertsBefore = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Equal(1, alertsBefore.GetProperty("unreadCount").GetInt32());
        var alertId = alertsBefore.GetProperty("items")[0].GetProperty("id").GetGuid();

        var markReadResp = await client.PostAsync($"/api/v1/alerts/{alertId}/read", null, Ct);
        Assert.Equal(HttpStatusCode.NoContent, markReadResp.StatusCode);

        var alertsAfterRead = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Equal(0, alertsAfterRead.GetProperty("unreadCount").GetInt32());

        // Auto-resolve closes the alert.
        await publisher.ResolveAsync(householdId, "consent_expiring:demo-aurora", Ct);
        var alertsAfterResolve = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Equal(0, alertsAfterResolve.GetProperty("items").GetArrayLength());
    }

    private async Task<(HttpClient Client, Guid HouseholdId)> CreateAuthenticatedClientAsync()
    {
        var client = _api.CreateClient();
        const string email = "bia@demo.local";
        const string password = "SenhaForte!2026#Test";

        var setupResp = await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email,
            displayName = "Bia Demo",
            password,
        }, Ct);
        setupResp.EnsureSuccessStatusCode();
        var setupJson = await setupResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var householdId = setupJson.GetProperty("householdId").GetGuid();

        var loginResp = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password }, Ct);
        var pendingToken = (await loginResp.Content.ReadFromJsonAsync<JsonElement>(Ct))
            .GetProperty("pendingToken").GetString()!;

        var totpSetupResp = await client.PostAsJsonAsync("/api/v1/auth/totp/setup", new { pendingToken }, Ct);
        var manualKey = (await totpSetupResp.Content.ReadFromJsonAsync<JsonElement>(Ct))
            .GetProperty("manualKey").GetString()!;

        var confirmResp = await client.PostAsJsonAsync("/api/v1/auth/totp/confirm", new
        {
            pendingToken,
            totpCode = KeyringAndIdentityTests.ComputeTotp(manualKey),
        }, Ct);
        confirmResp.EnsureSuccessStatusCode();
        var accessToken = (await confirmResp.Content.ReadFromJsonAsync<JsonElement>(Ct))
            .GetProperty("accessToken").GetString()!;

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        return (client, householdId);
    }
}
