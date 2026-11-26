using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using GranaPaCa.Modules.Assistant;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class FreeAiAssistantTests : IAsyncLifetime
{
    private readonly ApiFactory _api = new();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public ValueTask InitializeAsync() => _api.InitializeAsync();
    public ValueTask DisposeAsync() => _api.DisposeAsync();

    [Fact]
    public async Task Presets_endpoint_requires_auth_and_returns_all_free_local_and_cloud_tiers()
    {
        var unauthClient = _api.CreateClient();
        var unauthResp = await unauthClient.GetAsync("/api/v1/assistant/presets", Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, unauthResp.StatusCode);

        var client = await CreateAuthenticatedClientAsync("presets@demo.local");
        var resp = await client.GetAsync("/api/v1/assistant/presets", Ct);
        Assert.Equal(HttpStatusCode.OK, resp.StatusCode);

        var json = await resp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var items = json.GetProperty("items");
        Assert.Equal(8, items.GetArrayLength());

        var byProvider = items.EnumerateArray()
            .ToDictionary(el => el.GetProperty("provider").GetString()!, StringComparer.Ordinal);

        string[] expectedProviders =
        [
            "none",
            "google",
            "groq",
            "openrouter",
            "ollama",
            "openai_compatible",
            "openai",
            "anthropic"
        ];

        foreach (var provider in expectedProviders)
        {
            Assert.True(byProvider.ContainsKey(provider), $"Missing provider preset '{provider}'.");
            var preset = byProvider[provider];
            Assert.False(string.IsNullOrWhiteSpace(preset.GetProperty("displayName").GetString()));
            Assert.False(string.IsNullOrWhiteSpace(preset.GetProperty("costTier").GetString()));
            Assert.False(string.IsNullOrWhiteSpace(preset.GetProperty("setupEffort").GetString()));
            Assert.False(string.IsNullOrWhiteSpace(preset.GetProperty("privacyNote").GetString()));
        }

        // Verify zero-cost and free-tier preset details.
        var none = byProvider["none"];
        Assert.Equal("free", none.GetProperty("costTier").GetString());
        Assert.False(none.GetProperty("requiresApiKey").GetBoolean());
        Assert.True(none.GetProperty("isLocal").GetBoolean());
        Assert.Contains("Paçoca", none.GetProperty("displayName").GetString()!);

        var google = byProvider["google"];
        Assert.Equal("free_tier", google.GetProperty("costTier").GetString());
        Assert.Equal("gemini-2.5-flash-lite", google.GetProperty("recommendedModel").GetString());
        Assert.True(google.GetProperty("requiresApiKey").GetBoolean());
        Assert.True(google.GetProperty("pseudonymizationActive").GetBoolean());

        var groq = byProvider["groq"];
        Assert.Equal("free_tier", groq.GetProperty("costTier").GetString());
        Assert.Equal("llama-3.3-70b-versatile", groq.GetProperty("recommendedModel").GetString());
        Assert.Equal("https://api.groq.com/openai/v1/", groq.GetProperty("defaultBaseUrl").GetString());
        Assert.True(groq.GetProperty("requiresApiKey").GetBoolean());

        var openrouter = byProvider["openrouter"];
        Assert.Equal("free_tier", openrouter.GetProperty("costTier").GetString());
        Assert.Equal("meta-llama/llama-3.3-70b-instruct:free", openrouter.GetProperty("recommendedModel").GetString());
        Assert.Equal("https://openrouter.ai/api/v1/", openrouter.GetProperty("defaultBaseUrl").GetString());
        Assert.True(openrouter.GetProperty("requiresApiKey").GetBoolean());

        var ollama = byProvider["ollama"];
        Assert.Equal("free", ollama.GetProperty("costTier").GetString());
        Assert.Equal("qwen2.5:7b", ollama.GetProperty("recommendedModel").GetString());
        Assert.Equal("http://host.docker.internal:11434/", ollama.GetProperty("defaultBaseUrl").GetString());
        Assert.False(ollama.GetProperty("requiresApiKey").GetBoolean());
        Assert.True(ollama.GetProperty("isLocal").GetBoolean());

        var customCompat = byProvider["openai_compatible"];
        Assert.False(customCompat.GetProperty("requiresApiKey").GetBoolean());
        Assert.True(customCompat.GetProperty("pseudonymizationActive").GetBoolean());

        Assert.Equal("paid", byProvider["openai"].GetProperty("costTier").GetString());
        Assert.Equal("paid", byProvider["anthropic"].GetProperty("costTier").GetString());
    }

    [Fact]
    public async Task Free_tier_providers_groq_and_openrouter_encrypt_keys_at_rest_and_never_echo_them()
    {
        var client = await CreateAuthenticatedClientAsync("freekeys@demo.local");

        // 1. Configure Groq with fictitious test key -> encrypted at rest (RNF-06).
        const string fakeGroqKey = "chave-ficticia-groq-teste-local";
        var putGroq = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "groq",
            model = "llama-3.3-70b-versatile",
            baseUrl = "https://api.groq.com/openai/v1/",
            apiKey = fakeGroqKey,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, putGroq.StatusCode);
        var putGroqJson = await putGroq.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("groq", putGroqJson.GetProperty("provider").GetString());
        Assert.True(putGroqJson.GetProperty("hasApiKey").GetBoolean());
        Assert.DoesNotContain(fakeGroqKey, putGroqJson.GetRawText());

        var getGroq = await client.GetFromJsonAsync<JsonElement>("/api/v1/assistant/provider", Ct);
        Assert.Equal("groq", getGroq.GetProperty("provider").GetString());
        Assert.Equal("llama-3.3-70b-versatile", getGroq.GetProperty("model").GetString());
        Assert.True(getGroq.GetProperty("hasApiKey").GetBoolean());
        Assert.DoesNotContain(fakeGroqKey, getGroq.GetRawText());

        await AssertApiKeyNotPlaintextInDbAsync(fakeGroqKey);

        // 2. Configure OpenRouter with fictitious test key -> encrypted at rest (RNF-06).
        const string fakeOpenRouterKey = "chave-ficticia-openrouter-teste-local";
        var putOpenRouter = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openrouter",
            model = "meta-llama/llama-3.3-70b-instruct:free",
            baseUrl = "https://openrouter.ai/api/v1/",
            apiKey = fakeOpenRouterKey,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, putOpenRouter.StatusCode);

        var getOpenRouter = await client.GetFromJsonAsync<JsonElement>("/api/v1/assistant/provider", Ct);
        Assert.Equal("openrouter", getOpenRouter.GetProperty("provider").GetString());
        Assert.Equal("meta-llama/llama-3.3-70b-instruct:free", getOpenRouter.GetProperty("model").GetString());
        Assert.True(getOpenRouter.GetProperty("hasApiKey").GetBoolean());
        Assert.DoesNotContain(fakeOpenRouterKey, getOpenRouter.GetRawText());

        await AssertApiKeyNotPlaintextInDbAsync(fakeOpenRouterKey);

        // 3. Configure custom OpenAI-compatible local server without an API key.
        var putCustom = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai_compatible",
            model = "local-model",
            baseUrl = "http://localhost:1234/v1/",
            clearApiKey = true,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, putCustom.StatusCode);

        var getCustom = await client.GetFromJsonAsync<JsonElement>("/api/v1/assistant/provider", Ct);
        Assert.Equal("openai_compatible", getCustom.GetProperty("provider").GetString());
        Assert.False(getCustom.GetProperty("hasApiKey").GetBoolean());
    }

    [Fact]
    public async Task Local_deterministic_engine_answers_months_merchants_top_expenses_categories_and_comparisons()
    {
        var client = await CreateAuthenticatedClientAsync("localengine@demo.local");
        (await client.PostAsync("/api/v1/connections/sync", null, Ct)).EnsureSuccessStatusCode();

        // Ensure zero-cost native local mode ('none').
        (await client.PutAsJsonAsync("/api/v1/assistant/provider", new { provider = "none", clearApiKey = true }, Ct))
            .EnsureSuccessStatusCode();

        // 1. Portuguese month name in message without explicit Month parameter -> 2026-02.
        var febResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quanto gastei em fevereiro?",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, febResp.StatusCode);
        var febJson = await febResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-02", febJson.GetProperty("periodUsed").GetString());
        Assert.Equal("local", febJson.GetProperty("providerUsed").GetString());
        Assert.False(febJson.GetProperty("pseudonymized").GetBoolean());
        Assert.Contains("2026-02", febJson.GetProperty("content").GetString()!);
        Assert.True(febJson.GetProperty("numbersCited").GetArrayLength() >= 3);

        // 2. Merchant-specific query with Portuguese month name ("março") -> exact count & cents for Supermercado Bom Preço.
        // Cross-check exact cents against the ledger (/api/v1/transactions).
        var marchTxsJson = await client.GetFromJsonAsync<JsonElement>(
            "/api/v1/transactions?from=2026-03-01&to=2026-04-01&pageSize=200", Ct);
        var expectedSupermercadoCents = marchTxsJson.GetProperty("items").EnumerateArray()
            .Where(t => t.GetProperty("description").GetString()!.Contains("Supermercado", StringComparison.OrdinalIgnoreCase))
            .Sum(t => Math.Abs(t.GetProperty("amountCents").GetInt64()));
        Assert.Equal(89228L, expectedSupermercadoCents);

        var marketResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quanto gastei no supermercado em março?",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, marketResp.StatusCode);
        var marketJson = await marketResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", marketJson.GetProperty("periodUsed").GetString());
        var marketContent = marketJson.GetProperty("content").GetString()!;
        Assert.Contains("2 lançamentos", marketContent);
        Assert.Contains("Supermercado Bom Preço", marketContent);
        Assert.Contains("R$ 892,28", marketContent);
        Assert.Contains(
            marketJson.GetProperty("numbersCited").EnumerateArray(),
            n => n.GetProperty("amountCents").GetInt64() == expectedSupermercadoCents);

        // 3. Another merchant-specific query ("padaria") -> exact count & cents.
        var expectedPadariaCents = marchTxsJson.GetProperty("items").EnumerateArray()
            .Where(t => t.GetProperty("description").GetString()!.Contains("Padaria", StringComparison.OrdinalIgnoreCase))
            .Sum(t => Math.Abs(t.GetProperty("amountCents").GetInt64()));
        Assert.True(expectedPadariaCents > 0);

        var bakeryResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quanto gastei na padaria em março?",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, bakeryResp.StatusCode);
        var bakeryJson = await bakeryResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", bakeryJson.GetProperty("periodUsed").GetString());
        var bakeryContent = bakeryJson.GetProperty("content").GetString()!;
        Assert.Contains("2 lançamentos", bakeryContent);
        Assert.Contains("Padaria Pão de Ontem", bakeryContent);
        Assert.Contains(
            bakeryJson.GetProperty("numbersCited").EnumerateArray(),
            n => n.GetProperty("amountCents").GetInt64() == expectedPadariaCents);

        // 4. Top 5 largest expenses query -> lists top 5 expenses with exact dates & values.
        var topResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quais foram meus maiores gastos em março?",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, topResp.StatusCode);
        var topJson = await topResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", topJson.GetProperty("periodUsed").GetString());
        var topContent = topJson.GetProperty("content").GetString()!;
        Assert.Contains("5 maiores gastos", topContent);
        Assert.Contains("Aluguel", topContent);
        Assert.Contains("08/03/2026", topContent);
        Assert.Contains("Supermercado Bom Preço", topContent);
        Assert.True(topJson.GetProperty("numbersCited").GetArrayLength() >= 6);

        // 5. Category-specific query ("alimentação").
        var foodResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quanto gastei com alimentação em março?",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, foodResp.StatusCode);
        var foodJson = await foodResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", foodJson.GetProperty("periodUsed").GetString());
        Assert.Contains("Alimentação", foodJson.GetProperty("content").GetString()!);
        var foodCitedCents = foodJson.GetProperty("numbersCited")[0].GetProperty("amountCents").GetInt64();
        Assert.True(foodCitedCents > expectedSupermercadoCents, "Alimentação category should include supermercado plus restaurant/bakery.");

        // 6. Month-over-month comparison query.
        var compareResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Comparar março com mês passado",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, compareResp.StatusCode);
        var compareJson = await compareResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", compareJson.GetProperty("periodUsed").GetString());
        var compareContent = compareJson.GetProperty("content").GetString()!;
        Assert.Contains("2026-03", compareContent);
        Assert.Contains("2026-02", compareContent);
        Assert.True(compareJson.GetProperty("numbersCited").GetArrayLength() >= 4);

        // 7. Additional core financial queries: quanto sobrou, 50/30/20, projeção, assinaturas.
        foreach (var prompt in new[]
        {
            "Quanto sobrou em março?",
            "Como está meu 50/30/20 em março?",
            "Qual a projeção para fechar o mês em março?",
            "Quais são minhas assinaturas em março?"
        })
        {
            var resp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new { message = prompt }, Ct);
            Assert.Equal(HttpStatusCode.OK, resp.StatusCode);
            var payload = await resp.Content.ReadFromJsonAsync<JsonElement>(Ct);
            Assert.Equal("2026-03", payload.GetProperty("periodUsed").GetString());
            Assert.True(payload.GetProperty("numbersCited").GetArrayLength() >= 2);
            Assert.False(string.IsNullOrWhiteSpace(payload.GetProperty("content").GetString()));
        }

        // 8. When an external free-tier provider (e.g. groq) is unreachable, pseudonymization runs and falls back cleanly.
        (await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "groq",
            model = "llama-3.3-70b-versatile",
            baseUrl = "https://unreachable.invalid/v1/",
            apiKey = "chave-ficticia-groq-fallback",
        }, Ct)).EnsureSuccessStatusCode();

        var fallbackResp = await client.PostAsJsonAsync("/api/v1/assistant/chat", new
        {
            message = "Quanto gastei em março?",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, fallbackResp.StatusCode);
        var fallbackJson = await fallbackResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("2026-03", fallbackJson.GetProperty("periodUsed").GetString());
        Assert.Equal("local-fallback", fallbackJson.GetProperty("providerUsed").GetString());
        Assert.True(fallbackJson.GetProperty("pseudonymized").GetBoolean());
    }

    [Fact]
    public async Task Free_tier_providers_enforce_https_on_remote_hosts_block_metadata_and_document_presets_openapi()
    {
        var client = await CreateAuthenticatedClientAsync("ssrf-presets@demo.local");

        // Remote plain HTTP must be rejected even for openai_compatible and ollama, as well as groq and openrouter.
        (string Provider, string BadUrl)[] blockedCases =
        [
            ("openai_compatible", "http://remote-llm.example.com/v1/"),
            ("openai_compatible", "http://169.254.169.254/latest/meta-data"),
            ("openai_compatible", "http://metadata.google.internal/v1/"),
            ("ollama", "http://remote-ollama.example.com:11434/"),
            ("ollama", "http://169.254.169.254/api"),
            ("groq", "http://api.groq.com/openai/v1/"),
            ("groq", "https://127.0.0.1/v1/"),
            ("groq", "https://169.254.169.254/v1/"),
            ("openrouter", "http://openrouter.ai/api/v1/"),
            ("openrouter", "https://10.0.0.5/v1/"),
            ("openrouter", "https://169.254.169.254/v1/"),
        ];

        foreach (var (provider, badUrl) in blockedCases)
        {
            var resp = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
            {
                provider,
                model = "test-model",
                baseUrl = badUrl,
                apiKey = "chave-ficticia-teste",
            }, Ct);
            Assert.Equal(HttpStatusCode.BadRequest, resp.StatusCode);
            Assert.Equal("application/problem+json", resp.Content.Headers.ContentType?.MediaType);
        }

        // Remote HTTPS and local/private HTTP remain allowed for openai_compatible.
        var httpsCompat = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai_compatible",
            model = "custom-model",
            baseUrl = "https://llm.example.com/v1/",
            apiKey = "chave-ficticia-https",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, httpsCompat.StatusCode);

        var defaultCompat = await client.PutAsJsonAsync("/api/v1/assistant/provider", new
        {
            provider = "openai_compatible",
            model = "local-model",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, defaultCompat.StatusCode);

        // OpenAPI 3.1 documents /api/v1/assistant/presets with 200 and 401 responses.
        var openapi = await _api.CreateClient().GetFromJsonAsync<JsonElement>("/openapi/v1.json", Ct);
        var presetsResponses = openapi
            .GetProperty("paths")
            .GetProperty("/api/v1/assistant/presets")
            .GetProperty("get")
            .GetProperty("responses");
        Assert.True(presetsResponses.TryGetProperty("200", out _));
        Assert.True(presetsResponses.TryGetProperty("401", out _));
    }

    private async Task AssertApiKeyNotPlaintextInDbAsync(string rawKey)
    {
        await using var cmd = _api.Services.GetRequiredService<NpgsqlDataSource>()
            .CreateCommand("SELECT api_key_enc FROM assistant.provider_config LIMIT 1");
        var enc = (byte[])(await cmd.ExecuteScalarAsync(Ct))!;
        Assert.NotEmpty(enc);
        Assert.DoesNotContain(rawKey, Encoding.UTF8.GetString(enc));
    }

    private async Task<HttpClient> CreateAuthenticatedClientAsync(string email)
    {
        var client = _api.CreateClient();
        const string password = "SenhaForte!2026#Test";

        (await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email,
            displayName = "Pessoa Teste",
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

public sealed class FreeAiAssistantUnitTests
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public void PrivacyPseudonymizer_strips_cpf_cnpj_email_phone_and_account_digits()
    {
        var pseudonymizer = new PrivacyPseudonymizer();
        var bankToken = pseudonymizer.RegisterBank("Banco Aurora");
        var accountToken = pseudonymizer.RegisterAccount("Conta Corrente Aurora");
        var merchantToken = pseudonymizer.RegisterMerchant("Supermercado Bom Preço");

        const string sensitiveInput =
            "Cliente pessoa.teste@exemplo.local com CPF 111.222.333-44 (raw 55566677788), " +
            "CNPJ 11.222.333/0001-81 (raw 22333444000172), telefone (27) 90000-1234 e (11) 900004321, " +
            "agência 0001, conta corrente 12345-6, conta 98765-4, cartão final 4321 no Banco Aurora " +
            "(Conta Corrente Aurora) gastou no Supermercado Bom Preço.";

        var sanitized = pseudonymizer.SanitizeAndPseudonymize(sensitiveInput);

        // Irreversible PII must be completely removed.
        Assert.DoesNotContain("pessoa.teste@exemplo.local", sanitized);
        Assert.DoesNotContain("111.222.333-44", sanitized);
        Assert.DoesNotContain("55566677788", sanitized);
        Assert.DoesNotContain("11.222.333/0001-81", sanitized);
        Assert.DoesNotContain("22333444000172", sanitized);
        Assert.DoesNotContain("90000-1234", sanitized);
        Assert.DoesNotContain("900004321", sanitized);
        Assert.DoesNotContain("0001", sanitized);
        Assert.DoesNotContain("12345-6", sanitized);
        Assert.DoesNotContain("98765-4", sanitized);
        Assert.DoesNotContain("4321", sanitized);

        // Registered entities must be replaced with reversible tokens.
        Assert.DoesNotContain("Banco Aurora", sanitized);
        Assert.DoesNotContain("Conta Corrente Aurora", sanitized);
        Assert.DoesNotContain("Supermercado Bom Preço", sanitized);

        Assert.Contains("[EMAIL_OCULTO]", sanitized);
        Assert.Contains("[CPF_OCULTO]", sanitized);
        Assert.Contains("[CNPJ_OCULTO]", sanitized);
        Assert.Contains("[TELEFONE_OCULTO]", sanitized);
        Assert.Contains("[CONTA_OCULTA]", sanitized);
        Assert.Contains(bankToken, sanitized);
        Assert.Contains(accountToken, sanitized);
        Assert.Contains(merchantToken, sanitized);

        // Restore brings back only registered entity names, never redacted PII.
        var restored = pseudonymizer.Restore($"Resumo de {bankToken} para {merchantToken} (CPF [CPF_OCULTO]).");
        Assert.Contains("Banco Aurora", restored);
        Assert.Contains("Supermercado Bom Preço", restored);
        Assert.Contains("[CPF_OCULTO]", restored);
    }

    [Fact]
    public async Task ExternalAiProviderClient_routes_groq_openrouter_and_openai_compatible_cleanly()
    {
        var capturedRequests = new List<(Uri Uri, string? AuthHeader, string? TitleHeader, string Body)>();
        var handler = new StubCompletionHandler(capturedRequests);
        using var httpClient = new HttpClient(handler);
        var client = new ExternalAiProviderClient(httpClient, NullLogger<ExternalAiProviderClient>.Instance);

        // 1. Groq default routing.
        var groqReply = await client.TryCompleteAsync(
            new ExternalCompletionRequest(
                Provider: "groq",
                Model: string.Empty,
                BaseUrl: null,
                ApiKey: "chave-ficticia-groq",
                SystemPrompt: "Sistema",
                UserPrompt: "Resumo [BANCO_1]"),
            Ct);
        Assert.Equal("Resposta simulada [BANCO_1]", groqReply);
        Assert.Equal("https://api.groq.com/openai/v1/chat/completions", capturedRequests[0].Uri.ToString());
        Assert.Equal("Bearer chave-ficticia-groq", capturedRequests[0].AuthHeader);
        Assert.Contains("llama-3.3-70b-versatile", capturedRequests[0].Body);

        // 2. OpenRouter default routing + X-Title header.
        var openRouterReply = await client.TryCompleteAsync(
            new ExternalCompletionRequest(
                Provider: "openrouter",
                Model: string.Empty,
                BaseUrl: null,
                ApiKey: "chave-ficticia-openrouter",
                SystemPrompt: "Sistema",
                UserPrompt: "Resumo [ESTAB_1]"),
            Ct);
        Assert.Equal("Resposta simulada [BANCO_1]", openRouterReply);
        Assert.Equal("https://openrouter.ai/api/v1/chat/completions", capturedRequests[1].Uri.ToString());
        Assert.Equal("Bearer chave-ficticia-openrouter", capturedRequests[1].AuthHeader);
        Assert.Equal("GranaPaCa", capturedRequests[1].TitleHeader);
        Assert.Contains("meta-llama/llama-3.3-70b-instruct:free", capturedRequests[1].Body);

        // 3. OpenAI-compatible local endpoint WITHOUT API key (e.g. LM Studio / llama.cpp / vLLM).
        var localCompatReply = await client.TryCompleteAsync(
            new ExternalCompletionRequest(
                Provider: "openai_compatible",
                Model: "qwen2.5-7b-instruct",
                BaseUrl: "http://localhost:1234/v1/",
                ApiKey: null,
                SystemPrompt: "Sistema",
                UserPrompt: "Resumo local"),
            Ct);
        Assert.Equal("Resposta simulada [BANCO_1]", localCompatReply);
        Assert.Equal("http://localhost:1234/v1/chat/completions", capturedRequests[2].Uri.ToString());
        Assert.Null(capturedRequests[2].AuthHeader);
        Assert.Contains("qwen2.5-7b-instruct", capturedRequests[2].Body);

        // 4. OpenAI-compatible with null BaseUrl falls back to preset DefaultOpenAiCompatibleBaseUrl.
        var defaultCompatReply = await client.TryCompleteAsync(
            new ExternalCompletionRequest(
                Provider: "openai_compatible",
                Model: string.Empty,
                BaseUrl: null,
                ApiKey: null,
                SystemPrompt: "Sistema",
                UserPrompt: "Resumo padrão"),
            Ct);
        Assert.Equal("Resposta simulada [BANCO_1]", defaultCompatReply);
        Assert.Equal("http://host.docker.internal:1234/v1/chat/completions", capturedRequests[3].Uri.ToString());
        Assert.Contains("local-model", capturedRequests[3].Body);
    }

    private sealed class StubCompletionHandler(
        List<(Uri Uri, string? AuthHeader, string? TitleHeader, string Body)> captured) : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            var body = request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken);
            var title = request.Headers.TryGetValues("X-Title", out var values)
                ? values.FirstOrDefault()
                : null;
            captured.Add((request.RequestUri!, request.Headers.Authorization?.ToString(), title, body));

            const string jsonResponse = """
                {
                  "choices": [
                    {
                      "message": {
                        "role": "assistant",
                        "content": "Resposta simulada [BANCO_1]"
                      }
                    }
                  ]
                }
                """;

            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(jsonResponse, Encoding.UTF8, "application/json")
            };
        }
    }
}
