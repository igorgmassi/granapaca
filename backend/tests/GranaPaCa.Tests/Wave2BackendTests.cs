using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using GranaPaCa.Modules.Alerts.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class Wave2BackendTests : IAsyncLifetime
{
    private readonly ApiFactory _api = new();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public ValueTask InitializeAsync() => _api.InitializeAsync();
    public ValueTask DisposeAsync() => _api.DisposeAsync();

    [Fact]
    public async Task Incremental_cursor_sync_returns_full_snapshot_then_only_deltas_and_tombstones()
    {
        var anonymousClient = _api.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymousClient.GetAsync("/api/v1/sync/changes", Ct)).StatusCode);

        var (client, _, _, _) = await CreateAuthenticatedClientAsync();

        // Invalid cursor values are rejected with 400 Bad Request.
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync("/api/v1/sync/changes?cursor=invalido", Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync("/api/v1/sync/changes?cursor=2026-03-15", Ct)).StatusCode);

        // Populate household via synthetic sync.
        var syncResp = await client.PostAsync("/api/v1/connections/sync", null, Ct);
        syncResp.EnsureSuccessStatusCode();

        // 1. Initial sync without cursor returns full snapshot.
        var fullResp = await client.GetAsync("/api/v1/sync/changes", Ct);
        Assert.Equal(HttpStatusCode.OK, fullResp.StatusCode);
        var fullJson = await fullResp.Content.ReadFromJsonAsync<JsonElement>(Ct);

        Assert.True(fullJson.GetProperty("isFullSync").GetBoolean());
        Assert.Equal(JsonValueKind.Null, fullJson.GetProperty("cursor").ValueKind);
        var cursor1 = fullJson.GetProperty("nextCursor").GetString();
        Assert.False(string.IsNullOrWhiteSpace(cursor1));
        Assert.Equal(2, fullJson.GetProperty("connections").GetArrayLength());
        Assert.True(fullJson.GetProperty("accounts").GetArrayLength() >= 3);
        Assert.True(fullJson.GetProperty("cardBills").GetArrayLength() >= 3);
        var initialTxCount = fullJson.GetProperty("transactions").GetArrayLength();
        Assert.True(initialTxCount >= 70);
        Assert.Equal(0, fullJson.GetProperty("removedTransactionIds").GetArrayLength());

        var targetTxId = fullJson.GetProperty("transactions")[0].GetProperty("id").GetGuid();
        var secondTxId = fullJson.GetProperty("transactions")[1].GetProperty("id").GetGuid();

        // 2. Subsequent call with nextCursor returns zero changed records.
        var emptyDelta = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/sync/changes?cursor={Uri.EscapeDataString(cursor1!)}", Ct);
        Assert.False(emptyDelta.GetProperty("isFullSync").GetBoolean());
        Assert.Equal(0, emptyDelta.GetProperty("connections").GetArrayLength());
        Assert.Equal(0, emptyDelta.GetProperty("accounts").GetArrayLength());
        Assert.Equal(0, emptyDelta.GetProperty("cardBills").GetArrayLength());
        Assert.Equal(0, emptyDelta.GetProperty("transactions").GetArrayLength());
        Assert.Equal(0, emptyDelta.GetProperty("removedTransactionIds").GetArrayLength());
        Assert.Equal(0, emptyDelta.GetProperty("adjustments").GetArrayLength());
        var cursor2 = emptyDelta.GetProperty("nextCursor").GetString()!;

        // 3. Applying a manual adjustment surfaces ONLY that transaction and its adjustment.
        var adjustResp = await client.PostAsJsonAsync($"/api/v1/transactions/{targetTxId}/adjustments", new
        {
            category = "other",
            reason = "Ajuste de teste para sincronização incremental",
        }, Ct);
        adjustResp.EnsureSuccessStatusCode();

        var afterAdjustDelta = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/sync/changes?cursor={Uri.EscapeDataString(cursor2)}", Ct);
        Assert.Equal(1, afterAdjustDelta.GetProperty("transactions").GetArrayLength());
        Assert.Equal(targetTxId, afterAdjustDelta.GetProperty("transactions")[0].GetProperty("id").GetGuid());
        Assert.Equal("other", afterAdjustDelta.GetProperty("transactions")[0].GetProperty("category").GetString());
        Assert.True(afterAdjustDelta.GetProperty("transactions")[0].GetProperty("hasManualAdjustments").GetBoolean());
        Assert.Equal(1, afterAdjustDelta.GetProperty("adjustments").GetArrayLength());
        Assert.Equal(targetTxId, afterAdjustDelta.GetProperty("adjustments")[0].GetProperty("transactionId").GetGuid());
        Assert.Equal(0, afterAdjustDelta.GetProperty("connections").GetArrayLength());
        var cursor3 = afterAdjustDelta.GetProperty("nextCursor").GetString()!;

        // 4. Importing a single CSV transaction surfaces ONLY that new transaction (not the 70+ existing ones).
        var importResp = await client.PostAsJsonAsync("/api/v1/imports/csv", new
        {
            institutionName = "Banco Delta Demo",
            accountName = "Conta Delta",
            accountKind = "checking",
            content = "Data;Descrição;Valor\n20/03/2026;Padaria Delta Fictícia;-27,50\n",
        }, Ct);
        importResp.EnsureSuccessStatusCode();

        var afterImportDelta = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/sync/changes?cursor={Uri.EscapeDataString(cursor3)}", Ct);
        Assert.Equal(1, afterImportDelta.GetProperty("connections").GetArrayLength());
        Assert.Equal(1, afterImportDelta.GetProperty("accounts").GetArrayLength());
        Assert.Equal(1, afterImportDelta.GetProperty("transactions").GetArrayLength());
        Assert.Equal("Padaria Delta Fictícia", afterImportDelta.GetProperty("transactions")[0].GetProperty("description").GetString());
        Assert.Equal(-2750L, afterImportDelta.GetProperty("transactions")[0].GetProperty("amountCents").GetInt64());
        var cursor4 = afterImportDelta.GetProperty("nextCursor").GetString()!;

        // 5. Appending an ADR-012 removal version surfaces the tombstone ID in removedTransactionIds.
        await using (var conn = await _api.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync(Ct))
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                INSERT INTO banking.transaction_version (
                    id, transaction_id, version_number, content_hash, occurred_on,
                    description, amount_cents, currency, status, is_removed
                )
                SELECT
                    @VersionId, transaction_id, version_number + 1, content_hash || '-removed',
                    occurred_on, description, amount_cents, currency, status, true
                FROM banking.transaction_version
                WHERE transaction_id = @TxId
                ORDER BY version_number DESC
                LIMIT 1
                """;
            cmd.Parameters.AddWithValue("VersionId", Guid.CreateVersion7());
            cmd.Parameters.AddWithValue("TxId", secondTxId);
            await cmd.ExecuteNonQueryAsync(Ct);
        }

        var afterRemovalDelta = await client.GetFromJsonAsync<JsonElement>(
            $"/api/v1/sync/changes?cursor={Uri.EscapeDataString(cursor4)}", Ct);
        Assert.Equal(0, afterRemovalDelta.GetProperty("transactions").GetArrayLength());
        var removedIds = afterRemovalDelta.GetProperty("removedTransactionIds")
            .EnumerateArray()
            .Select(e => e.GetGuid())
            .ToList();
        Assert.Single(removedIds);
        Assert.Equal(secondTxId, removedIds[0]);
    }

    [Fact]
    public async Task Ofx_1x_sgml_ofx_2x_xml_and_brazilian_csv_imports_are_exact_encrypted_categorized_and_idempotent()
    {
        var anonymousClient = _api.CreateClient();
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await anonymousClient.PostAsJsonAsync("/api/v1/imports/ofx", new { content = "<OFX></OFX>" }, Ct)).StatusCode);
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await anonymousClient.PostAsJsonAsync("/api/v1/imports/csv", new { content = "Data;Descrição;Valor" }, Ct)).StatusCode);

        var (client, _, _, _) = await CreateAuthenticatedClientAsync();

        // Reject malformed inputs and fractional cents (ADR-013).
        Assert.Equal(
            HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/imports/ofx", new { content = "nao e um ofx" }, Ct)).StatusCode);
        Assert.Equal(
            HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/imports/csv", new { content = "ColunaA;ColunaB\n1;2" }, Ct)).StatusCode);

        const string fractionalOfx = """
            OFXHEADER:100
            DATA:OFXSGML
            VERSION:102

            <OFX>
            <BANKMSGSRSV1>
            <STMTTRNRS>
            <STMTRS>
            <CURDEF>BRL
            <BANKTRANLIST>
            <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20260315
            <TRNAMT>-45.905
            <FITID>FRAC-001
            <MEMO>Valor com meio centavo
            </STMTTRN>
            </BANKTRANLIST>
            </STMTRS>
            </STMTTRNRS>
            </BANKMSGSRSV1>
            </OFX>
            """;
        Assert.Equal(
            HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/imports/ofx", new { content = fractionalOfx }, Ct)).StatusCode);

        const string fractionalCsv = "Data;Descrição;Valor\n15/03/2026;Item Inválido;-12,345\n";
        Assert.Equal(
            HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/v1/imports/csv", new { content = fractionalCsv }, Ct)).StatusCode);

        // 1. Import OFX 1.x (SGML without closing leaf tags), including UTC midnight date (ADR-015) and outgoing transfer.
        const string ofx1Sgml = """
            OFXHEADER:100
            DATA:OFXSGML
            VERSION:102
            ENCODING:UTF-8

            <OFX>
            <SIGNONMSGSRSV1>
            <SONRS>
            <FI>
            <ORG>Banco Fictício Horizonte
            </FI>
            </SONRS>
            </SIGNONMSGSRSV1>
            <BANKMSGSRSV1>
            <STMTTRNRS>
            <STMTRS>
            <CURDEF>BRL
            <BANKACCTFROM>
            <BANKID>0999
            <ACCTID>00012345-6
            <ACCTTYPE>CHECKING
            </BANKACCTFROM>
            <BANKTRANLIST>
            <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20260315120000[-3:BRT]
            <TRNAMT>-185.40
            <FITID>OFX-DEMO-001
            <NAME>Supermercado Horizonte
            <MEMO>Compra débito
            </STMTTRN>
            <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20260316000000[0:GMT]
            <TRNAMT>-89.90
            <FITID>OFX-DEMO-002
            <MEMO>Farmácia Bela Vista
            </STMTTRN>
            <STMTTRN>
            <TRNTYPE>XFER
            <DTPOSTED>20260316140000[-3:BRT]
            <TRNAMT>-500.00
            <FITID>OFX-DEMO-003
            <MEMO>Pix Transferência Própria
            </STMTTRN>
            <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20260317
            <TRNAMT>-42.00
            <FITID>OFX-DEMO-004
            <MEMO>Bazar Fictício Desconhecido
            </STMTTRN>
            </BANKTRANLIST>
            <LEDGERBAL>
            <BALAMT>2450.00
            </LEDGERBAL>
            </STMTRS>
            </STMTTRNRS>
            </BANKMSGSRSV1>
            </OFX>
            """;

        var ofx1Resp = await client.PostAsJsonAsync("/api/v1/imports/ofx", new
        {
            accountName = "Conta Corrente Horizonte",
            content = ofx1Sgml,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, ofx1Resp.StatusCode);
        var ofx1Json = await ofx1Resp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(4, ofx1Json.GetProperty("inserted").GetInt32());
        Assert.Equal(0, ofx1Json.GetProperty("skippedDuplicates").GetInt32());
        // Before the matching CSV transfer arrives, both the unknown merchant and unpaired Pix outflow are uncategorized.
        Assert.Equal(2, ofx1Json.GetProperty("uncategorizedCount").GetInt32());

        // Re-importing exact same OFX 1.x produces zero duplicates.
        var ofx1RepeatResp = await client.PostAsJsonAsync("/api/v1/imports/ofx", new
        {
            accountName = "Conta Corrente Horizonte",
            content = ofx1Sgml,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, ofx1RepeatResp.StatusCode);
        var ofx1RepeatJson = await ofx1RepeatResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(0, ofx1RepeatJson.GetProperty("inserted").GetInt32());
        Assert.Equal(4, ofx1RepeatJson.GetProperty("skippedDuplicates").GetInt32());

        // 2. Import OFX 2.x (XML) credit card statement.
        const string ofx2Xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <?OFX OFXHEADER="200" VERSION="220" SECURITY="NONE"?>
            <OFX>
              <CREDITCARDMSGSRSV1>
                <CCSTMTTRNRS>
                  <CCSTMTRS>
                    <CURDEF>BRL</CURDEF>
                    <CCACCTFROM>
                      <ACCTID>9999000011114321</ACCTID>
                    </CCACCTFROM>
                    <BANKTRANLIST>
                      <STMTTRN>
                        <TRNTYPE>DEBIT</TRNTYPE>
                        <DTPOSTED>20260318193000[-3:BRT]</DTPOSTED>
                        <TRNAMT>-129.90</TRNAMT>
                        <FITID>CC-DEMO-001</FITID>
                        <NAME>Restaurante Cantina Demo</NAME>
                      </STMTTRN>
                    </BANKTRANLIST>
                  </CCSTMTRS>
                </CCSTMTTRNRS>
              </CREDITCARDMSGSRSV1>
            </OFX>
            """;

        var ofx2Resp = await client.PostAsJsonAsync("/api/v1/imports/ofx", new
        {
            institutionName = "Cartão Fictício Norte",
            accountName = "Cartão Norte",
            content = ofx2Xml,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, ofx2Resp.StatusCode);
        var ofx2Json = await ofx2Resp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(1, ofx2Json.GetProperty("inserted").GetInt32());
        Assert.Equal(0, ofx2Json.GetProperty("uncategorizedCount").GetInt32());

        // 3. Import Brazilian CSV (UTF-8 BOM, ';' delimiter, dd/MM/yyyy, -1.234,56, duplicate coffees, and incoming own transfer).
        const string brazilianCsv =
            "\uFEFFData;Descrição;Valor\r\n" +
            "15/03/2026;Supermercado Estrela;-1.234,56\r\n" +
            "15/03/2026;Padaria Sabor Real;-18,50\r\n" +
            "15/03/2026;Padaria Sabor Real;-18,50\r\n" +
            "16/03/2026;Pix Transferência Própria;500,00\r\n" +
            "2026-03-17;Loja de Artesanato Local;-75.00\r\n";

        var csvResp = await client.PostAsJsonAsync("/api/v1/imports/csv", new
        {
            institutionName = "Banco Fictício Sul",
            accountName = "Conta Corrente Sul",
            accountKind = "checking",
            content = brazilianCsv,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, csvResp.StatusCode);
        var csvJson = await csvResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(5, csvJson.GetProperty("inserted").GetInt32());
        Assert.Equal(0, csvJson.GetProperty("skippedDuplicates").GetInt32());
        Assert.Equal(1, csvJson.GetProperty("transfersLinked").GetInt32());

        // Re-importing exact same CSV is 100% idempotent with 0 duplicates inserted.
        var csvRepeatResp = await client.PostAsJsonAsync("/api/v1/imports/csv", new
        {
            institutionName = "Banco Fictício Sul",
            accountName = "Conta Corrente Sul",
            accountKind = "checking",
            content = brazilianCsv,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, csvRepeatResp.StatusCode);
        var csvRepeatJson = await csvRepeatResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal(0, csvRepeatJson.GetProperty("inserted").GetInt32());
        Assert.Equal(5, csvRepeatJson.GetProperty("skippedDuplicates").GetInt32());

        // 4. Verify exact cents, ADR-015 dates, automatic categorization, and transfer pairing via /api/v1/transactions.
        var txsPage = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions?pageSize=50", Ct);
        var items = txsPage.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(10, items.Count);

        var mercadoCsv = items.Single(i => i.GetProperty("description").GetString() == "Supermercado Estrela");
        Assert.Equal(-123456L, mercadoCsv.GetProperty("amountCents").GetInt64());
        Assert.Equal("2026-03-15", mercadoCsv.GetProperty("occurredOn").GetString());
        Assert.Equal("food", mercadoCsv.GetProperty("category").GetString());
        Assert.Equal("essential", mercadoCsv.GetProperty("essentiality").GetString());

        var farmaciaOfx = items.Single(i => i.GetProperty("description").GetString() == "Farmácia Bela Vista");
        Assert.Equal(-8990L, farmaciaOfx.GetProperty("amountCents").GetInt64());
        Assert.Equal("2026-03-16", farmaciaOfx.GetProperty("occurredOn").GetString());
        Assert.Equal("health", farmaciaOfx.GetProperty("category").GetString());

        var padariaRows = items.Where(i => i.GetProperty("description").GetString() == "Padaria Sabor Real").ToList();
        Assert.Equal(2, padariaRows.Count);
        Assert.All(padariaRows, row => Assert.Equal(-1850L, row.GetProperty("amountCents").GetInt64()));

        var linkedTransfers = items.Where(i => i.GetProperty("kind").GetString() == "own_transfer").ToList();
        Assert.Equal(2, linkedTransfers.Count);

        var reviewQueue = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions/review-queue", Ct);
        Assert.Equal(1, reviewQueue.GetProperty("totalTransactions").GetInt32());

        var creditCardTx = items.Single(i => i.GetProperty("description").GetString() == "Restaurante Cantina Demo");
        Assert.Equal("credit_card", creditCardTx.GetProperty("accountKind").GetString());
        Assert.Equal(-12990L, creditCardTx.GetProperty("amountCents").GetInt64());
        Assert.Equal("food", creditCardTx.GetProperty("category").GetString());

        // Verify raw payloads are AES-GCM encrypted (no plaintext merchant names in raw_payload_enc).
        await using (var conn = await _api.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync(Ct))
        {
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = """
                SELECT v.raw_payload_enc
                FROM banking.transaction_version v
                JOIN banking.transaction_source s ON s.transaction_id = v.transaction_id
                WHERE s.source = 'file'
                """;
            await using var reader = await cmd.ExecuteReaderAsync(Ct);
            var payloadCount = 0;
            while (await reader.ReadAsync(Ct))
            {
                var rawEnc = (byte[])reader[0];
                Assert.True(rawEnc.Length >= 45);
                var asText = Encoding.UTF8.GetString(rawEnc);
                Assert.DoesNotContain("Supermercado", asText, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain("Padaria", asText, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain("Farmácia", asText, StringComparison.OrdinalIgnoreCase);
                payloadCount++;
            }

            Assert.Equal(10, payloadCount);
        }

        // Verify credit card last four digits parsed from OFX 2.x.
        var banks = (await client.GetFromJsonAsync<JsonElement>("/api/v1/banks", Ct))
            .GetProperty("items").EnumerateArray().ToList();
        var cardBank = banks.Single(b => b.GetProperty("institutionName").GetString() == "Cartão Fictício Norte");
        var cardAccount = cardBank.GetProperty("accounts")[0];
        Assert.Equal("credit_card", cardAccount.GetProperty("kind").GetString());
        Assert.Equal("4321", cardAccount.GetProperty("lastFourDigits").GetString());
    }

    [Fact]
    public async Task Full_account_purge_verifies_credentials_and_erases_all_data_and_keys()
    {
        var anonymousClient = _api.CreateClient();
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await anonymousClient.PostAsJsonAsync("/api/v1/account/purge", new
            {
                password = "x",
                totpCode = "123456",
                confirmationText = "APAGAR TUDO",
            }, Ct)).StatusCode);

        var (client, householdId, password, manualKey) = await CreateAuthenticatedClientAsync();

        // Populate every module schema: banking (sync + adjustments + undo + CSV import), categorization (profiles + rule), alerts, keyring.
        (await client.PostAsync("/api/v1/connections/sync", null, Ct)).EnsureSuccessStatusCode();

        var txs = await client.GetFromJsonAsync<JsonElement>("/api/v1/transactions?pageSize=5", Ct);
        var txId = txs.GetProperty("items")[0].GetProperty("id").GetGuid();

        var adjResp = await client.PostAsJsonAsync($"/api/v1/transactions/{txId}/adjustments", new
        {
            category = "other",
            reason = "Ajuste antes de apagar",
        }, Ct);
        adjResp.EnsureSuccessStatusCode();
        var adjId = (await adjResp.Content.ReadFromJsonAsync<JsonElement>(Ct))
            .GetProperty("appliedAdjustments")[0].GetProperty("id").GetGuid();
        (await client.PostAsync($"/api/v1/transactions/{txId}/adjustments/{adjId}/undo", null, Ct))
            .EnsureSuccessStatusCode();

        (await client.PostAsJsonAsync("/api/v1/rules", new
        {
            name = "Regra temporária",
            matchPattern = "armarinho",
            category = "shopping",
            essentiality = "flexible",
        }, Ct)).EnsureSuccessStatusCode();

        (await client.PutAsJsonAsync("/api/v1/profiles", new
        {
            occupations = new[] { "desenvolvedor" },
            homeTraits = new[] { "casa-sozinho" },
            transportModes = new[] { "transporte-aplicativo" },
            acceptedRuleIds = Array.Empty<string>(),
        }, Ct)).EnsureSuccessStatusCode();

        var alertPublisher = _api.Services.GetRequiredService<IAlertPublisher>();
        await alertPublisher.RaiseAsync(new AlertRequest(
            householdId,
            "purge-test-alert",
            "info_test",
            "info",
            "Alerta de teste",
            "Será removido no apagar tudo."), Ct);

        // 1. Reject invalid confirmation text (400).
        var badConfirm = await client.PostAsJsonAsync("/api/v1/account/purge", new
        {
            password,
            totpCode = KeyringAndIdentityTests.ComputeTotp(manualKey),
            confirmationText = "apagar tudo",
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, badConfirm.StatusCode);

        // 2. Reject missing credentials (400).
        var missingCreds = await client.PostAsJsonAsync("/api/v1/account/purge", new
        {
            password = "",
            totpCode = "",
            confirmationText = "APAGAR TUDO",
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, missingCreds.StatusCode);

        // 3. Reject wrong password (401).
        var wrongPassword = await client.PostAsJsonAsync("/api/v1/account/purge", new
        {
            password = "SenhaErrada!2026#Test",
            totpCode = KeyringAndIdentityTests.ComputeTotp(manualKey),
            confirmationText = "APAGAR TUDO",
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, wrongPassword.StatusCode);

        // 4. Reject wrong TOTP code (401).
        var wrongTotp = await client.PostAsJsonAsync("/api/v1/account/purge", new
        {
            password,
            totpCode = "000000",
            confirmationText = "APAGAR TUDO",
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, wrongTotp.StatusCode);

        // 5. Valid password + valid TOTP + exact confirmation text -> 204 No Content.
        var purgeResp = await client.PostAsJsonAsync("/api/v1/account/purge", new
        {
            password,
            totpCode = KeyringAndIdentityTests.ComputeTotp(manualKey),
            confirmationText = "APAGAR TUDO",
        }, Ct);
        Assert.Equal(HttpStatusCode.NoContent, purgeResp.StatusCode);

        // Caller token is immediately invalidated.
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/summary", Ct)).StatusCode);

        // Server returns to fresh unconfigured state.
        var serverInfo = await anonymousClient.GetFromJsonAsync<JsonElement>("/api/v1/server-info", Ct);
        Assert.False(serverInfo.GetProperty("ownerConfigured").GetBoolean());

        // Every single table across banking, categorization, alerts, keyring, and identity is completely empty.
        string[] tablesToVerifyEmpty =
        [
            "banking.connection",
            "banking.account",
            "banking.balance_snapshot",
            "banking.card_bill",
            "banking.transaction",
            "banking.transaction_source",
            "banking.transaction_version",
            "banking.adjustment",
            "banking.transfer_link",
            "banking.classification",
            "categorization.rule",
            "categorization.profile_config",
            "alerts.alert",
            "keyring.data_key",
            "identity.household",
            "identity.owner",
            "identity.session",
            "identity.recovery_code",
            "identity.pending_totp_session",
            "identity.used_refresh_token",
            "identity.auth_attempt",
        ];

        await using (var conn = await _api.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync(Ct))
        {
            foreach (var table in tablesToVerifyEmpty)
            {
                await using var cmd = conn.CreateCommand();
                cmd.CommandText = $"SELECT COUNT(*) FROM {table}";
                var count = Convert.ToInt64(await cmd.ExecuteScalarAsync(Ct));
                Assert.True(count == 0, $"Expected {table} to be empty after purge, but found {count} row(s).");
            }
        }

        // Instance can be freshly configured again after purge.
        var freshSetup = await anonymousClient.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email = "nova-conta@demo.local",
            displayName = "Nova Pessoa Demo",
            password = "NovaSenhaForte!2026#Test",
        }, Ct);
        Assert.Equal(HttpStatusCode.Created, freshSetup.StatusCode);
    }

    [Fact]
    public async Task Openapi_v1_document_returns_valid_openapi_3_1_json_with_all_api_paths()
    {
        var client = _api.CreateClient();
        var response = await client.GetAsync("/openapi/v1.json", Ct);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var doc = await response.Content.ReadFromJsonAsync<JsonElement>(Ct);

        var version = doc.GetProperty("openapi").GetString();
        Assert.NotNull(version);
        Assert.StartsWith("3.1", version, StringComparison.Ordinal);

        var paths = doc.GetProperty("paths");
        string[] expectedPaths =
        [
            "/api/v1/server-info",
            "/api/v1/auth/setup",
            "/api/v1/auth/login",
            "/api/v1/summary",
            "/api/v1/transactions",
            "/api/v1/sync/changes",
            "/api/v1/imports/ofx",
            "/api/v1/imports/csv",
            "/api/v1/account/purge",
            "/api/v1/rules",
            "/api/v1/alerts",
        ];

        foreach (var path in expectedPaths)
        {
            Assert.True(paths.TryGetProperty(path, out _), $"Expected OpenAPI path '{path}' to be documented.");
        }
    }

    private async Task<(HttpClient Client, Guid HouseholdId, string Password, string ManualKey)> CreateAuthenticatedClientAsync()
    {
        var client = _api.CreateClient();
        const string email = "wave2@demo.local";
        const string password = "SenhaForte!2026#Wave2";

        var setupResp = await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email,
            displayName = "Pessoa Wave2",
            password,
        }, Ct);
        setupResp.EnsureSuccessStatusCode();
        var setupJson = await setupResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var householdId = setupJson.GetProperty("householdId").GetGuid();

        var loginResp = await client.PostAsJsonAsync("/api/v1/auth/login", new { email, password }, Ct);
        loginResp.EnsureSuccessStatusCode();
        var pendingToken = (await loginResp.Content.ReadFromJsonAsync<JsonElement>(Ct))
            .GetProperty("pendingToken").GetString()!;

        var totpSetupResp = await client.PostAsJsonAsync("/api/v1/auth/totp/setup", new { pendingToken }, Ct);
        totpSetupResp.EnsureSuccessStatusCode();
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
        return (client, householdId, password, manualKey);
    }
}
