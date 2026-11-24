using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class Wave3BackendTests : IAsyncLifetime
{
    private readonly ApiFactory _api = new();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public ValueTask InitializeAsync() => _api.InitializeAsync();
    public ValueTask DisposeAsync() => _api.DisposeAsync();

    [Fact]
    public async Task Cash_tags_splits_payment_method_bulk_adjustments_and_exports_work_end_to_end()
    {
        var client = await CreateAuthenticatedClientAsync();

        // Sync synthetic data so we have rich multi-month data.
        var syncResp = await client.PostAsync("/api/v1/connections/sync", null, Ct);
        syncResp.EnsureSuccessStatusCode();

        // 1. Idempotent cash quick-entry (offline outbox replay safe).
        const string mutationId = "cash-client-mut-001";
        var cashReq = new
        {
            occurredOn = "2026-03-18",
            description = "Feira do Bairro",
            amountCents = -7500L,
            kind = "expense",
            category = "food",
            essentiality = "essential",
            tags = new[] { "feira", "casa" },
            clientMutationId = mutationId,
        };
        var cash1 = await client.PostAsJsonAsync("/api/v1/transactions/cash", cashReq, Ct);
        Assert.Equal(HttpStatusCode.Created, cash1.StatusCode);
        var cash1Json = await cash1.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var cashTxId = cash1Json.GetProperty("id").GetGuid();

        var cash2 = await client.PostAsJsonAsync("/api/v1/transactions/cash", cashReq, Ct);
        Assert.Equal(HttpStatusCode.OK, cash2.StatusCode);
        var cash2Json = await cash2.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(cashTxId, cash2Json.GetProperty("id").GetGuid());

        // 2. Filter by paymentMethod=cash and tag=feira.
        var filtered = await client.GetFromJsonAsync<JsonElement>(
            "/api/v1/transactions?paymentMethod=cash&tag=feira", Ct);
        Assert.Equal(1, filtered.GetProperty("totalCount").GetInt32());
        Assert.Equal(cashTxId, filtered.GetProperty("items")[0].GetProperty("id").GetGuid());

        // 3. Tags CRUD.
        var createTag = await client.PostAsJsonAsync("/api/v1/tags", new { name = "viagem", color = "#22649C" }, Ct);
        Assert.Equal(HttpStatusCode.Created, createTag.StatusCode);
        var tagId = (await createTag.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("id").GetGuid();

        var tagsList = await client.GetFromJsonAsync<JsonElement>("/api/v1/tags", Ct);
        Assert.True(tagsList.GetProperty("items").GetArrayLength() >= 3);

        var deleteTag = await client.DeleteAsync($"/api/v1/tags/{tagId}", Ct);
        Assert.Equal(HttpStatusCode.NoContent, deleteTag.StatusCode);

        // 4. Splits exact-cent validation (RN-24 / ADR-013).
        var badSplit = await client.PutAsJsonAsync($"/api/v1/transactions/{cashTxId}/splits", new
        {
            parts = new[]
            {
                new { description = "Frutas", amountCents = -4000L, category = "food", essentiality = "essential" },
                new { description = "Flores", amountCents = -3000L, category = "leisure", essentiality = "flexible" },
            },
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, badSplit.StatusCode);

        var goodSplit = await client.PutAsJsonAsync($"/api/v1/transactions/{cashTxId}/splits", new
        {
            parts = new[]
            {
                new { description = "Frutas e legumes", amountCents = -5500L, category = "food", essentiality = "essential" },
                new { description = "Pastel da feira", amountCents = -2000L, category = "food", essentiality = "flexible" },
            },
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, goodSplit.StatusCode);

        var splitsGet = await client.GetFromJsonAsync<JsonElement>($"/api/v1/transactions/{cashTxId}/splits", Ct);
        Assert.Equal(2, splitsGet.GetProperty("parts").GetArrayLength());

        // 5. Bulk adjustment marking atypical + paymentMethod.
        var bulkResp = await client.PostAsJsonAsync("/api/v1/transactions/bulk-adjustments", new
        {
            transactionIds = new[] { cashTxId },
            isAtypical = true,
            reason = "Compra atípica de evento",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, bulkResp.StatusCode);
        var bulkJson = await bulkResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(1, bulkJson.GetProperty("updatedCount").GetInt32());

        // 6. Exports: CSV, complete JSON backup, printable HTML report.
        var csvResp = await client.GetAsync("/api/v1/export/transactions.csv?from=2026-03-01&to=2026-04-01", Ct);
        Assert.Equal(HttpStatusCode.OK, csvResp.StatusCode);
        var csvBody = await csvResp.Content.ReadAsStringAsync(Ct);
        Assert.Contains("Feira do Bairro", csvBody);
        Assert.Contains("Forma de Pagamento", csvBody);

        var jsonResp = await client.GetFromJsonAsync<JsonElement>("/api/v1/export/backup.json", Ct);
        Assert.True(jsonResp.GetProperty("transactions").GetArrayLength() >= 70);
        Assert.True(jsonResp.GetProperty("splits").GetArrayLength() >= 2);

        var htmlResp = await client.GetAsync("/api/v1/export/report.html?month=2026-03", Ct);
        Assert.Equal(HttpStatusCode.OK, htmlResp.StatusCode);
        var htmlBody = await htmlResp.Content.ReadAsStringAsync(Ct);
        Assert.Contains("<!DOCTYPE html>", htmlBody, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("2026-03", htmlBody);
    }

    [Fact]
    public async Task Planning_budgets_goals_heatmap_503020_subscriptions_and_threshold_alerts_work()
    {
        var client = await CreateAuthenticatedClientAsync();
        (await client.PostAsync("/api/v1/connections/sync", null, Ct)).EnsureSuccessStatusCode();

        // Upsert food budget low enough to trigger an alert in March 2026.
        var budgetResp = await client.PutAsJsonAsync("/api/v1/planning/budgets", new
        {
            category = "food",
            monthLimitCents = 50000L,
            alertThresholdPercent = 80,
            isActive = true,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, budgetResp.StatusCode);

        // Create & update goal.
        var goalResp = await client.PostAsJsonAsync("/api/v1/planning/goals", new
        {
            name = "Reserva de emergência",
            targetCents = 2000000L,
            currentCents = 1200000L,
            targetDate = "2026-12-31",
        }, Ct);
        Assert.Equal(HttpStatusCode.Created, goalResp.StatusCode);
        var goalId = (await goalResp.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("id").GetGuid();

        var patchGoal = await client.PatchAsJsonAsync($"/api/v1/planning/goals/{goalId}", new { addCents = 150000L }, Ct);
        Assert.Equal(HttpStatusCode.OK, patchGoal.StatusCode);
        Assert.Equal(1350000L, (await patchGoal.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("currentCents").GetInt64());

        // Create natural-language spending alert rule.
        var alertRuleResp = await client.PostAsJsonAsync("/api/v1/planning/alert-rules", new
        {
            expression = "me avise quando supermercado passar de R$ 300",
        }, Ct);
        Assert.Equal(HttpStatusCode.Created, alertRuleResp.StatusCode);

        // Evaluate alerts for 2026-03 -> should raise budget + spending alert in Alerts module!
        var evalResp = await client.PostAsync("/api/v1/planning/evaluate-alerts?month=2026-03", null, Ct);
        Assert.Equal(HttpStatusCode.OK, evalResp.StatusCode);

        var alerts = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.True(alerts.GetProperty("unreadCount").GetInt32() >= 1);

        // Overview returns 50/30/20, projection, month-over-month, 31-day March heatmap, subscriptions.
        var overview = await client.GetFromJsonAsync<JsonElement>("/api/v1/planning/overview?month=2026-03", Ct);
        Assert.Equal("2026-03", overview.GetProperty("month").GetString());
        Assert.True(overview.GetProperty("rule503020").GetProperty("needsCents").GetInt64() > 0);
        Assert.Equal(31, overview.GetProperty("calendarHeatmap").GetArrayLength());
        Assert.True(overview.GetProperty("subscriptions").GetArrayLength() >= 1);
        Assert.Equal(1, overview.GetProperty("budgets").GetArrayLength());
        Assert.Equal(1, overview.GetProperty("goals").GetArrayLength());
    }

    [Fact]
    public async Task Receipts_encrypted_volume_storage_nfce_es_parser_and_split_application_work()
    {
        var client = await CreateAuthenticatedClientAsync();

        // Create a cash transaction matching the synthetic NFC-e total (R$ 45,50 -> -4550 cents).
        var cashResp = await client.PostAsJsonAsync("/api/v1/transactions/cash", new
        {
            occurredOn = "2026-03-22",
            description = "Supermercado Capixaba Fictício",
            amountCents = -4550L,
            kind = "expense",
            category = "food",
            essentiality = "essential",
        }, Ct);
        cashResp.EnsureSuccessStatusCode();
        var txId = (await cashResp.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("id").GetGuid();

        // Consent flow (asked on first receipt).
        var consentBefore = await client.GetFromJsonAsync<JsonElement>("/api/v1/receipts/consent", Ct);
        Assert.False(consentBefore.GetProperty("hasDecided").GetBoolean());

        var consentPut = await client.PutAsJsonAsync("/api/v1/receipts/consent", new
        {
            itemAnalysisAccepted = true,
            dietaryNotesAccepted = false,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, consentPut.StatusCode);

        // Upload receipt file -> encrypted at rest (ADR-025), decrypted identically on download.
        var rawContent = Encoding.UTF8.GetBytes("COMPROVANTE-FICTICIO-SEGREDO-EM-CLARO-NAO-PODE-APARECER");
        var uploadResp = await client.PostAsJsonAsync("/api/v1/receipts", new
        {
            transactionId = txId,
            fileName = "comprovante.txt",
            contentType = "text/plain",
            contentBase64 = Convert.ToBase64String(rawContent),
        }, Ct);
        Assert.Equal(HttpStatusCode.Created, uploadResp.StatusCode);
        var uploadedId = (await uploadResp.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("id").GetGuid();

        // Verify file on disk has ZERO plaintext!
        var diskFiles = Directory.GetFiles(_api.ReceiptsStoragePath, "*", SearchOption.AllDirectories);
        Assert.NotEmpty(diskFiles);
        foreach (var diskFile in diskFiles)
        {
            var diskBytes = await File.ReadAllBytesAsync(diskFile, Ct);
            Assert.DoesNotContain("COMPROVANTE-FICTICIO", Encoding.UTF8.GetString(diskBytes));
        }

        // Download decrypts back to exact bytes.
        var downloaded = await client.GetByteArrayAsync($"/api/v1/receipts/{uploadedId}/download", Ct);
        Assert.Equal(rawContent, downloaded);

        // Parse SEFAZ-ES NFC-e 4.00 XML and apply items as transaction splits!
        const string sampleNfceXml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
              <NFe>
                <infNFe Id="NFe32260300000000000191650010000001231000001234" versao="4.00">
                  <ide><dhEmi>2026-03-22T14:30:00-03:00</dhEmi></ide>
                  <emit><CNPJ>00000000000191</CNPJ><xNome>Supermercado Capixaba Ficticio Ltda</xNome></emit>
                  <det nItem="1">
                    <prod><xProd>Arroz Integral 1kg</xProd><qCom>2.000</qCom><vUnCom>12.50</vUnCom><vProd>25.00</vProd></prod>
                  </det>
                  <det nItem="2">
                    <prod><xProd>Sabonete Neutro</xProd><qCom>1.000</qCom><vUnCom>20.50</vUnCom><vProd>20.50</vProd></prod>
                  </det>
                  <total><ICMSTot><vNF>45.50</vNF></ICMSTot></total>
                </infNFe>
              </NFe>
            </nfeProc>
            """;

        var parseResp = await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new
        {
            xml = sampleNfceXml,
            transactionId = txId,
            save = true,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, parseResp.StatusCode);
        var parsed = await parseResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("ES", parsed.GetProperty("state").GetString());
        Assert.Equal(4550L, parsed.GetProperty("totalCents").GetInt64());
        Assert.Equal(2, parsed.GetProperty("items").GetArrayLength());
        var nfceReceiptId = parsed.GetProperty("id").GetGuid();

        var applyResp = await client.PostAsJsonAsync($"/api/v1/receipts/{nfceReceiptId}/apply-splits", new
        {
            transactionId = txId,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, applyResp.StatusCode);
        var applied = await applyResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(2, applied.GetProperty("splitsApplied").GetInt32());

        // QR Code ES URL parsing also works.
        var qrResp = await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new
        {
            qrUrl = "https://app.sefaz.es.gov.br/ConsultaNFCe?p=32260300000000000191650010000001231000001234|2|1|1|abc123",
            save = false,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, qrResp.StatusCode);
        var qrJson = await qrResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("ES", qrJson.GetProperty("state").GetString());
    }

    [Fact]
    public async Task Assistant_encrypts_byok_key_answers_with_exact_numbers_streams_sse_and_gates_suggestions()
    {
        var client = await CreateAuthenticatedClientAsync();
        (await client.PostAsync("/api/v1/connections/sync", null, Ct)).EnsureSuccessStatusCode();

        // 1. Configure BYOK provider key -> stored encrypted (never plaintext in DB, never echoed by GET!).
        const string fakeApiKey = "chave-ficticia-teste-local-assistant";
        var putProvider = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai",
            model = "gpt-5-mini",
            apiKey = fakeApiKey,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, putProvider.StatusCode);

        var getProvider = await client.GetFromJsonAsync<JsonElement>("/api/v1/assistant/provider", Ct);
        Assert.Equal("openai", getProvider.GetProperty("provider").GetString());
        Assert.True(getProvider.GetProperty("hasApiKey").GetBoolean());
        Assert.DoesNotContain(fakeApiKey, getProvider.GetRawText());

        // RNF-06 DB verification: raw API key must never appear in assistant.provider_config.
        await using (var cmd = _api.Services.GetRequiredService<NpgsqlDataSource>()
            .CreateCommand("SELECT api_key_enc FROM assistant.provider_config LIMIT 1"))
        {
            var enc = (byte[])(await cmd.ExecuteScalarAsync(Ct))!;
            Assert.DoesNotContain(fakeApiKey, Encoding.UTF8.GetString(enc));
        }

        // Switch back to local deterministic mode ('none') so chat runs offline with zero external calls.
        (await client.PutAsJsonAsync("/api/v1/assistant/provider", new { provider = "none", clearApiKey = true }, Ct))
            .EnsureSuccessStatusCode();

        // 2. Read-only financial chat citing exact numbers and period.
        var chatResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quanto gastei e qual categoria pesou mais?",
            month = "2026-03",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, chatResp.StatusCode);
        var chatJson = await chatResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", chatJson.GetProperty("periodUsed").GetString());
        Assert.True(chatJson.GetProperty("numbersCited").GetArrayLength() >= 1);
        Assert.False(string.IsNullOrWhiteSpace(chatJson.GetProperty("content").GetString()));

        // 3. SSE streaming endpoint (ADR-018).
        var streamResp = await client.PostAsJsonAsync("/api/v1/assistant/chat/stream", new
        {
            message = "Quanto sobrou no mês?",
            month = "2026-03",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, streamResp.StatusCode);
        Assert.Equal("text/event-stream", streamResp.Content.Headers.ContentType?.MediaType);
        var sseText = await streamResp.Content.ReadAsStringAsync(Ct);
        Assert.Contains("event: meta", sseText);
        Assert.Contains("event: token", sseText);
        Assert.Contains("event: done", sseText);

        // 4. Categorization suggestions require explicit confirmation.
        var genResp = await client.PostAsync("/api/v1/assistant/suggestions/generate", null, Ct);
        Assert.Equal(HttpStatusCode.OK, genResp.StatusCode);
        var genJson = await genResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.True(genJson.GetProperty("pendingCount").GetInt32() >= 1);

        var suggestionId = genJson.GetProperty("items")[0].GetProperty("id").GetGuid();
        var confirmResp = await client.PostAsJsonAsync(
            $"/api/v1/assistant/suggestions/{suggestionId}/decide",
            new { action = "confirm" }, Ct);
        Assert.Equal(HttpStatusCode.OK, confirmResp.StatusCode);
        var confirmJson = await confirmResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("confirmed", confirmJson.GetProperty("suggestion").GetProperty("status").GetString());
        Assert.NotEqual(JsonValueKind.Null, confirmJson.GetProperty("rulePayload").ValueKind);
    }

    private async Task<HttpClient> CreateAuthenticatedClientAsync()
    {
        var client = _api.CreateClient();
        const string email = "bia@demo.local";
        const string password = "SenhaForte!2026#Test";

        (await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email,
            displayName = "Bia Demo",
            password,
        }, Ct)).EnsureSuccessStatusCode();

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
        return client;
    }
}
