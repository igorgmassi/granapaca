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
            fileName = "comprovante.pdf",
            contentType = "application/pdf",
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

    [Fact]
    public async Task Csv_export_neutralizes_formula_injection_while_preserving_numeric_amounts()
    {
        var client = await CreateAuthenticatedClientAsync();

        string[] dangerousDescriptions =
        [
            "=CMD|' /C calc'!A0",
            "+SUM(A1:A2)",
            "-2+3",
            "@SUM(1+1)"
        ];

        for (var i = 0; i < dangerousDescriptions.Length; i++)
        {
            var resp = await client.PostAsJsonAsync("/api/v1/transactions/cash", new
            {
                occurredOn = "2026-03-18",
                description = dangerousDescriptions[i],
                amountCents = -7500L,
                kind = "expense",
                category = "other",
                essentiality = "flexible",
                tags = i == 0 ? new[] { "=HYPERLINK(\"https://example.invalid\")" } : Array.Empty<string>(),
            }, Ct);
            Assert.Equal(HttpStatusCode.Created, resp.StatusCode);
        }

        var csvResp = await client.GetAsync("/api/v1/export/transactions.csv?from=2026-03-01&to=2026-04-01", Ct);
        Assert.Equal(HttpStatusCode.OK, csvResp.StatusCode);
        var csv = await csvResp.Content.ReadAsStringAsync(Ct);

        Assert.Contains("'=CMD|' /C calc'!A0", csv);
        Assert.Contains("'+SUM(A1:A2)", csv);
        Assert.Contains("'-2+3", csv);
        Assert.Contains("'@SUM(1+1)", csv);
        Assert.Contains("'=HYPERLINK(", csv);

        // Numeric BRL column must remain unprefixed (quoted as "-75,00" due to comma, never prefixed with ').
        Assert.Contains(";\"-75,00\"\r\n", csv);
        Assert.DoesNotContain("'-75,00", csv);
    }

    [Fact]
    public async Task Assistant_pseudonymizes_all_pii_including_pix_uuid_and_sends_google_key_only_in_header()
    {
        var handler = new CapturingAiHttpMessageHandler();
        await using var customFactory = _api.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.ConfigureHttpClientDefaults(http =>
                    http.ConfigurePrimaryHttpMessageHandler(() => handler));
            });
        });

        var (client, _, _) = await CreateAuthenticatedClientWithCredentialsAsync(customFactory.CreateClient());
        (await client.PostAsync("/api/v1/connections/sync", null, Ct)).EnsureSuccessStatusCode();

        const string googleApiKey = "chave-ficticia-google-header-only-123";
        var putGoogle = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "google",
            model = "gemini-2.0-flash",
            apiKey = googleApiKey,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, putGoogle.StatusCode);

        const string fakeCpf = "123.456.789-00";
        const string fakeCnpj = "12.345.678/0001-99";
        const string fakeEmail = "pessoa.privada@demo.local";
        const string fakePhone = "(27) 99999-1234";
        const string fakeAccount = "123456-7";
        const string fakePixUuid = "550e8400-e29b-41d4-a716-446655440000";

        var chatResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = $"Quanto gastei no Banco Aurora? CPF {fakeCpf} CNPJ {fakeCnpj} email {fakeEmail} tel {fakePhone} conta {fakeAccount} pix {fakePixUuid}",
            month = "2026-03",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, chatResp.StatusCode);
        var chatJson = await chatResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("google", chatJson.GetProperty("providerUsed").GetString());
        Assert.True(chatJson.GetProperty("pseudonymized").GetBoolean());

        var captured = Assert.Single(handler.CapturedRequests);
        Assert.DoesNotContain("key=", captured.RequestUri, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(googleApiKey, captured.RequestUri, StringComparison.Ordinal);
        Assert.True(captured.Headers.TryGetValue("x-goog-api-key", out var sentHeaderKey));
        Assert.Equal(googleApiKey, sentHeaderKey);

        // Zero raw PII or bank names may leave the instance (ADR-023).
        Assert.DoesNotContain(fakeCpf, captured.Body, StringComparison.Ordinal);
        Assert.DoesNotContain(fakeCnpj, captured.Body, StringComparison.Ordinal);
        Assert.DoesNotContain(fakeEmail, captured.Body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(fakePhone, captured.Body, StringComparison.Ordinal);
        Assert.DoesNotContain(fakeAccount, captured.Body, StringComparison.Ordinal);
        Assert.DoesNotContain(fakePixUuid, captured.Body, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Banco Aurora", captured.Body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("[CPF_OCULTO]", captured.Body);
        Assert.Contains("[CNPJ_OCULTO]", captured.Body);
        Assert.Contains("[EMAIL_OCULTO]", captured.Body);
        Assert.Contains("[TELEFONE_OCULTO]", captured.Body);
        Assert.Contains("[CONTA_OCULTA]", captured.Body);
        Assert.Contains("[CHAVE_PIX_OCULTA]", captured.Body);
        Assert.Contains("[BANCO_1]", captured.Body);

        // Pseudonymized token in reply is restored locally for the owner.
        var replyText = chatJson.GetProperty("content").GetString()!;
        Assert.DoesNotContain("[BANCO_1]", replyText, StringComparison.Ordinal);
        Assert.True(
            replyText.Contains("Banco Aurora", StringComparison.Ordinal) ||
            replyText.Contains("Banco Siriema", StringComparison.Ordinal),
            $"Expected restored bank name in reply, got: {replyText}");
    }

    [Fact]
    public async Task Assistant_byok_clears_key_on_provider_or_host_change_and_blocks_ssrf_urls()
    {
        var client = await CreateAuthenticatedClientAsync();

        // Save key for OpenAI.
        (await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai",
            model = "gpt-4o-mini",
            baseUrl = "https://api.openai.com/v1",
            apiKey = "chave-ficticia-openai-001",
        }, Ct)).EnsureSuccessStatusCode();

        // Changing only the model keeps the saved key.
        var sameHostUpdate = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai",
            model = "gpt-4o",
            baseUrl = "https://api.openai.com/v1",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, sameHostUpdate.StatusCode);
        Assert.True((await sameHostUpdate.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("hasApiKey").GetBoolean());

        // Switching baseUrl without supplying a new key MUST clear the previous key.
        var hostChanged = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai",
            model = "gpt-4o",
            baseUrl = "https://api.example.com/v1",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, hostChanged.StatusCode);
        Assert.False((await hostChanged.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("hasApiKey").GetBoolean());

        // Save key again, then switch provider without apiKey -> MUST clear key.
        (await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai",
            model = "gpt-4o-mini",
            apiKey = "chave-ficticia-openai-002",
        }, Ct)).EnsureSuccessStatusCode();

        var providerChanged = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "anthropic",
            model = "claude-3-5-haiku-latest",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, providerChanged.StatusCode);
        Assert.False((await providerChanged.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("hasApiKey").GetBoolean());

        // Cloud providers reject http://, loopback, private LAN, and link-local metadata endpoints.
        string[] blockedCloudUrls =
        [
            "http://api.openai.com/v1",
            "https://127.0.0.1/v1",
            "https://localhost:8443/v1",
            "https://169.254.169.254/latest/meta-data",
            "https://10.0.0.5/v1",
            "https://172.16.0.10/v1",
            "https://192.168.1.20/v1",
            "https://[::1]/v1",
        ];

        foreach (var badUrl in blockedCloudUrls)
        {
            var resp = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
            {
                provider = "openai",
                model = "gpt-4o-mini",
                baseUrl = badUrl,
            }, Ct);
            Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
            Assert.Equal("application/problem+json", resp.Content.Headers.ContentType?.MediaType);
        }

        // Ollama permits localhost HTTP, but still blocks cloud link-local metadata.
        var ollamaMetadata = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "ollama",
            model = "llama3.2",
            baseUrl = "http://169.254.169.254/api",
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, ollamaMetadata.StatusCode);
        Assert.Equal("application/problem+json", ollamaMetadata.Content.Headers.ContentType?.MediaType);

        var ollamaLocal = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "ollama",
            model = "llama3.2",
            baseUrl = "http://localhost:11434",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, ollamaLocal.StatusCode);
    }

    [Fact]
    public async Task Nfce_comma_decimals_full_discount_overflow_consent_mime_and_size_caps_are_enforced()
    {
        var client = await CreateAuthenticatedClientAsync();

        // 1. XML parsing MUST require prior consent (403 ProblemDetails) before extracting items.
        const string commaNfceXml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
              <NFe>
                <infNFe Id="NFe32260300000000000191650010000009991000009999" versao="4.00">
                  <ide><dhEmi>2026-03-22T14:30:00-03:00</dhEmi></ide>
                  <emit><CNPJ>00000000000191</CNPJ><xNome>Mercado Virgulino Ficticio</xNome></emit>
                  <det nItem="1">
                    <prod><xProd>Café Especial</xProd><qCom>1,000</qCom><vUnCom>45,50</vUnCom><vProd>45,50</vProd></prod>
                  </det>
                  <det nItem="2">
                    <prod><xProd>Brinde Promocional</xProd><qCom>1,000</qCom><vUnCom>20,00</vUnCom><vProd>20,00</vProd><vDesc>20,00</vDesc></prod>
                  </det>
                  <total><ICMSTot><vNF>45,50</vNF></ICMSTot></total>
                </infNFe>
              </NFe>
            </nfeProc>
            """;

        var noConsentResp = await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new
        {
            xml = commaNfceXml,
            save = true,
        }, Ct);
        Assert.Equal(HttpStatusCode.Forbidden, noConsentResp.StatusCode);
        Assert.Equal("application/problem+json", noConsentResp.Content.Headers.ContentType?.MediaType);
        var noConsentJson = await noConsentResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("receipt_item_consent_required", noConsentJson.GetProperty("code").GetString());

        // Accept consent -> now comma decimals ("45,50" -> 4550 cents, never 455000) and 100% discount work cleanly.
        (await client.PutAsJsonAsync("/api/v1/receipts/consent", new
        {
            itemAnalysisAccepted = true,
            dietaryNotesAccepted = false,
        }, Ct)).EnsureSuccessStatusCode();

        var parsedResp = await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new
        {
            xml = commaNfceXml,
            save = false,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, parsedResp.StatusCode);
        var parsedJson = await parsedResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(4550L, parsedJson.GetProperty("totalCents").GetInt64());
        var items = parsedJson.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(2, items.Count);
        Assert.Equal(4550L, items[0].GetProperty("totalCents").GetInt64());
        Assert.Equal(0L, items[1].GetProperty("totalCents").GetInt64());

        // 2. Overflow in NFC-e XML returns 400 ProblemDetails (never 500).
        const string overflowNfceXml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
              <NFe>
                <infNFe Id="NFe32260300000000000191650010000009981000009998" versao="4.00">
                  <ide><dhEmi>2026-03-22T14:30:00-03:00</dhEmi></ide>
                  <emit><xNome>Teste Overflow</xNome></emit>
                  <total><ICMSTot><vNF>99999999999999999999.00</vNF></ICMSTot></total>
                </infNFe>
              </NFe>
            </nfeProc>
            """;
        var overflowNfceResp = await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new
        {
            xml = overflowNfceXml,
            save = false,
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, overflowNfceResp.StatusCode);
        Assert.Equal("application/problem+json", overflowNfceResp.Content.Headers.ContentType?.MediaType);

        // 3. Oversized XML (> 10 MB) rejected pre-parse even with save=false.
        var oversizedXml = "<nfeProc>" + new string('a', 10 * 1024 * 1024 + 64) + "</nfeProc>";
        var oversizedXmlResp = await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new
        {
            xml = oversizedXml,
            save = false,
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, oversizedXmlResp.StatusCode);
        Assert.Equal("application/problem+json", oversizedXmlResp.Content.Headers.ContentType?.MediaType);

        // 4. MIME allowlist and malformed ContentType return 400 ProblemDetails.
        string[] rejectedMimes = ["text/html", "image/svg+xml", "application/javascript", "invalid///mime"];
        foreach (var badMime in rejectedMimes)
        {
            var resp = await client.PostAsJsonAsync("/api/v1/receipts", new
            {
                fileName = "anexo.bin",
                contentType = badMime,
                contentBase64 = Convert.ToBase64String(Encoding.UTF8.GetBytes("dados")),
            }, Ct);
            Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
            Assert.Equal("application/problem+json", resp.Content.Headers.ContentType?.MediaType);
        }

        // 5. Planning goal addCents overflow and alert rule expression overflow return 400 ProblemDetails (never 500).
        var goalResp = await client.PostAsJsonAsync("/api/v1/planning/goals", new
        {
            name = "Meta Overflow",
            targetCents = 100000L,
            currentCents = 50000L,
        }, Ct);
        goalResp.EnsureSuccessStatusCode();
        var goalId = (await goalResp.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("id").GetGuid();

        var overflowGoalPatch = await client.PatchAsJsonAsync($"/api/v1/planning/goals/{goalId}", new
        {
            addCents = long.MaxValue,
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, overflowGoalPatch.StatusCode);
        Assert.Equal("application/problem+json", overflowGoalPatch.Content.Headers.ContentType?.MediaType);

        var overflowAlertRule = await client.PostAsJsonAsync("/api/v1/planning/alert-rules", new
        {
            expression = "me avise quando delivery passar de R$ 99999999999999999999",
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, overflowAlertRule.StatusCode);
        Assert.Equal("application/problem+json", overflowAlertRule.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task Full_account_purge_erases_all_wave3_tables_and_encrypted_receipt_files_on_disk()
    {
        var (client, password, manualKey) = await CreateAuthenticatedClientWithCredentialsAsync(_api.CreateClient());

        // Populate every new Wave 3 table + encrypted receipt file on disk.
        (await client.PostAsync("/api/v1/connections/sync", null, Ct)).EnsureSuccessStatusCode();

        var cashResp = await client.PostAsJsonAsync("/api/v1/transactions/cash", new
        {
            occurredOn = "2026-03-22",
            description = "Feira Purge Fictícia",
            amountCents = -4550L,
            kind = "expense",
            category = "food",
            essentiality = "essential",
            tags = new[] { "purge-tag" },
        }, Ct);
        cashResp.EnsureSuccessStatusCode();
        var txId = (await cashResp.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("id").GetGuid();

        (await client.PutAsJsonAsync($"/api/v1/transactions/{txId}/splits", new
        {
            parts = new[]
            {
                new { description = "Parte 1", amountCents = -2550L, category = "food", essentiality = "essential" },
                new { description = "Parte 2", amountCents = -2000L, category = "other", essentiality = "flexible" },
            },
        }, Ct)).EnsureSuccessStatusCode();

        (await client.PutAsJsonAsync("/api/v1/planning/budgets", new
        {
            category = "food",
            monthLimitCents = 80000L,
            alertThresholdPercent = 80,
            isActive = true,
        }, Ct)).EnsureSuccessStatusCode();

        (await client.PostAsJsonAsync("/api/v1/planning/goals", new
        {
            name = "Meta Purge",
            targetCents = 500000L,
            currentCents = 100000L,
        }, Ct)).EnsureSuccessStatusCode();

        (await client.PostAsJsonAsync("/api/v1/planning/alert-rules", new
        {
            expression = "me avise quando delivery passar de R$ 250",
        }, Ct)).EnsureSuccessStatusCode();

        (await client.PutAsJsonAsync("/api/v1/receipts/consent", new
        {
            itemAnalysisAccepted = true,
            dietaryNotesAccepted = false,
        }, Ct)).EnsureSuccessStatusCode();

        (await client.PostAsJsonAsync("/api/v1/receipts", new
        {
            transactionId = txId,
            fileName = "nota-purge.pdf",
            contentType = "application/pdf",
            contentBase64 = Convert.ToBase64String(Encoding.UTF8.GetBytes("PDF-FICTICIO-PURGE")),
        }, Ct)).EnsureSuccessStatusCode();

        const string nfceXml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <nfeProc xmlns="http://www.portalfiscal.inf.br/nfe" versao="4.00">
              <NFe>
                <infNFe Id="NFe32260300000000000191650010000007771000007777" versao="4.00">
                  <ide><dhEmi>2026-03-22T14:30:00-03:00</dhEmi></ide>
                  <emit><xNome>Mercado Purge</xNome></emit>
                  <det nItem="1"><prod><xProd>Arroz</xProd><qCom>1.000</qCom><vUnCom>45.50</vUnCom><vProd>45.50</vProd></prod></det>
                  <total><ICMSTot><vNF>45.50</vNF></ICMSTot></total>
                </infNFe>
              </NFe>
            </nfeProc>
            """;
        (await client.PostAsJsonAsync("/api/v1/receipts/nfce/parse", new { xml = nfceXml, transactionId = txId, save = true }, Ct))
            .EnsureSuccessStatusCode();

        (await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "none",
            clearApiKey = true,
        }, Ct)).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/assistant/chat", new { message = "Quanto gastei?", month = "2026-03" }, Ct))
            .EnsureSuccessStatusCode();
        (await client.PostAsync("/api/v1/assistant/suggestions/generate", null, Ct)).EnsureSuccessStatusCode();

        Assert.NotEmpty(Directory.GetFiles(_api.ReceiptsStoragePath, "*", SearchOption.AllDirectories));

        // Execute full account purge.
        var purgeResp = await client.PostAsJsonAsync("/api/v1/account/purge", new
        {
            password,
            totpCode = KeyringAndIdentityTests.ComputeTotp(manualKey),
            confirmationText = "APAGAR TUDO",
        }, Ct);
        Assert.Equal(HttpStatusCode.NoContent, purgeResp.StatusCode);

        // Verify ALL 12 new Wave 3 tables are empty and encrypted receipt files were removed from disk post-commit.
        string[] wave3Tables =
        [
            "banking.tag",
            "banking.transaction_tag",
            "banking.transaction_split",
            "planning.budget",
            "planning.goal",
            "planning.spending_alert_rule",
            "receipts.consent",
            "receipts.receipt",
            "receipts.receipt_item",
            "assistant.provider_config",
            "assistant.chat_message",
            "assistant.categorization_suggestion",
        ];

        await using (var conn = await _api.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync(Ct))
        {
            foreach (var table in wave3Tables)
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = $"SELECT COUNT(*) FROM {table}";
                var count = Convert.ToInt64(await cmd.ExecuteScalarAsync(Ct));
                Assert.True(count == 0, $"Expected {table} to be empty after purge, but found {count} row(s).");
            }
        }

        var remainingFiles = Directory.Exists(_api.ReceiptsStoragePath)
            ? Directory.GetFiles(_api.ReceiptsStoragePath, "*", SearchOption.AllDirectories)
            : [];
        Assert.Empty(remainingFiles);
    }

    private async Task<HttpClient> CreateAuthenticatedClientAsync()
    {
        var (client, _, _) = await CreateAuthenticatedClientWithCredentialsAsync(_api.CreateClient());
        return client;
    }

    private static async Task<(HttpClient Client, string Password, string ManualKey)> CreateAuthenticatedClientWithCredentialsAsync(
        HttpClient client)
    {
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
        return (client, password, manualKey);
    }

    private sealed record CapturedAiHttpRequest(
        string RequestUri,
        Dictionary<string, string> Headers,
        string Body);

    private sealed class CapturingAiHttpMessageHandler : HttpMessageHandler
    {
        public List<CapturedAiHttpRequest> CapturedRequests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            var body = request.Content is not null
                ? await request.Content.ReadAsStringAsync(cancellationToken)
                : string.Empty;

            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var h in request.Headers)
            {
                headers[h.Key] = string.Join(",", h.Value);
            }

            CapturedRequests.Add(new CapturedAiHttpRequest(
                request.RequestUri?.ToString() ?? string.Empty,
                headers,
                body));

            const string replyJson = """
                {
                  "candidates": [
                    {
                      "content": {
                        "parts": [
                          { "text": "Resumo do período 2026-03 no [BANCO_1] conferido." }
                        ]
                      }
                    }
                  ]
                }
                """;

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(replyJson, Encoding.UTF8, "application/json")
            };
        }
    }
}
