using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using GranaPaCa.Api;
using Microsoft.Extensions.DependencyInjection;

namespace GranaPaCa.Tests;

public sealed class BackupStatusParserTests
{
    [Fact]
    public void TryParse_parses_ok_status_with_utc_timestamp()
    {
        const string payload = """
            timestamp=2026-11-26T03:30:00Z
            status=ok
            step=completed
            """;

        var ok = BackupStatusParser.TryParse(payload, out var snapshot);

        Assert.True(ok);
        Assert.NotNull(snapshot);
        Assert.Equal("ok", snapshot.Status);
        Assert.Equal(BackupStatusParser.FallbackStepToken, snapshot.StepToken);
        Assert.Equal(BackupStatusParser.FallbackStepLabelPtBr, snapshot.StepLabelPtBr);
        Assert.Equal(new DateTimeOffset(2026, 11, 26, 3, 30, 0, TimeSpan.Zero), snapshot.TimestampUtc);
    }

    [Fact]
    public void TryParse_parses_failed_status_with_crlf_endings()
    {
        const string payload = "timestamp=2026-11-26T03:35:12Z\r\nstatus=failed\r\nstep=postgres_backup\r\n";

        var ok = BackupStatusParser.TryParse(payload, out var snapshot);

        Assert.True(ok);
        Assert.NotNull(snapshot);
        Assert.Equal("failed", snapshot.Status);
        Assert.Equal("postgres_backup", snapshot.StepToken);
        Assert.Equal("backup do banco de dados", snapshot.StepLabelPtBr);
        Assert.Equal(new DateTimeOffset(2026, 11, 26, 3, 35, 12, TimeSpan.Zero), snapshot.TimestampUtc);
    }

    [Theory]
    [InlineData("init", "inicialização do backup")]
    [InlineData("prerequisites", "verificação de pré-requisitos")]
    [InlineData("restic_repo_check", "acesso ao repositório cifrado")]
    [InlineData("postgres_healthcheck", "verificação do banco de dados")]
    [InlineData("postgres_backup", "backup do banco de dados")]
    [InlineData("files_backup", "backup dos arquivos cifrados")]
    [InlineData("retention_prune", "limpeza de retenção")]
    [InlineData("integrity_check", "verificação de integridade do backup")]
    [InlineData("write_status", "registro do estado do backup")]
    public void TryParse_maps_known_backup_steps_to_pt_br_labels(string step, string expectedLabel)
    {
        var payload = $"status=failed\nstep={step}\n";

        var ok = BackupStatusParser.TryParse(payload, out var snapshot);

        Assert.True(ok);
        Assert.NotNull(snapshot);
        Assert.Equal(step, snapshot.StepToken);
        Assert.Equal(expectedLabel, snapshot.StepLabelPtBr);
    }

    [Fact]
    public void TryParse_falls_back_safely_for_unknown_or_untrusted_step_tokens()
    {
        const string payload = "status=failed\nstep=<script>alert(1)</script> /etc/shadow\n";

        var ok = BackupStatusParser.TryParse(payload, out var snapshot);

        Assert.True(ok);
        Assert.NotNull(snapshot);
        Assert.Equal(BackupStatusParser.FallbackStepToken, snapshot.StepToken);
        Assert.Equal(BackupStatusParser.FallbackStepLabelPtBr, snapshot.StepLabelPtBr);
        Assert.DoesNotContain("script", snapshot.StepLabelPtBr, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("shadow", snapshot.StepLabelPtBr, StringComparison.OrdinalIgnoreCase);
        Assert.Null(snapshot.TimestampUtc);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   \r\n  ")]
    [InlineData("status=running\nstep=init\n")]
    [InlineData("step=postgres_backup\n")]
    [InlineData("not_a_key_value_line")]
    public void TryParse_rejects_invalid_payloads(string payload)
    {
        var ok = BackupStatusParser.TryParse(payload, out var snapshot);

        Assert.False(ok);
        Assert.Null(snapshot);
    }

    [Fact]
    public void TryParse_rejects_payloads_larger_than_4_kib()
    {
        var prefix = "status=failed\nstep=postgres_backup\nextra=";
        var exactLimit = prefix + new string('a', BackupStatusParser.MaxBytes - prefix.Length);
        var overLimit = exactLimit + "b";

        Assert.True(BackupStatusParser.TryParse(exactLimit, out var okSnapshot));
        Assert.NotNull(okSnapshot);
        Assert.False(BackupStatusParser.TryParse(overLimit, out var rejectedSnapshot));
        Assert.Null(rejectedSnapshot);
    }
}

public sealed class BackupStatusMonitorTests : IAsyncLifetime
{
    private readonly ApiFactory _api = new();
    private readonly string _statusDir = Path.Combine(Path.GetTempPath(), $"granapaca-backup-status-{Guid.NewGuid():N}");
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public ValueTask InitializeAsync()
    {
        Directory.CreateDirectory(_statusDir);
        return _api.InitializeAsync();
    }

    public async ValueTask DisposeAsync()
    {
        await _api.DisposeAsync();
        if (Directory.Exists(_statusDir))
        {
            Directory.Delete(_statusDir, recursive: true);
        }
    }

    [Fact]
    public async Task Backup_failure_raises_deduplicated_inbox_alert_and_success_resolves_it()
    {
        var statusFilePath = Path.Combine(_statusDir, "granapaca-backup.status");
        using var configuredFactory = _api.WithWebHostBuilder(builder =>
            builder.UseSetting("Backup:StatusFile", statusFilePath));

        var client = await CreateAuthenticatedClientAsync(configuredFactory);
        var monitor = configuredFactory.Services.GetRequiredService<BackupStatusMonitor>();

        // Missing file -> clean no-op, zero alerts.
        await monitor.CheckOnceAsync(Ct);
        var initialAlerts = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Equal(0, initialAlerts.GetProperty("unreadCount").GetInt32());
        Assert.Empty(initialAlerts.GetProperty("items").EnumerateArray());

        // Failed backup -> creates unread error alert pointing to settings.
        await File.WriteAllTextAsync(
            statusFilePath,
            "timestamp=2026-11-26T03:30:00Z\nstatus=failed\nstep=postgres_backup\n",
            Ct);

        await monitor.CheckOnceAsync(Ct);
        await monitor.CheckOnceAsync(Ct);

        var activeAlerts = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Equal(1, activeAlerts.GetProperty("unreadCount").GetInt32());
        var activeItems = activeAlerts.GetProperty("items").EnumerateArray().ToList();
        var alert = Assert.Single(activeItems);
        Assert.Equal(BackupStatusMonitor.AlertDedupKey, alert.GetProperty("dedupKey").GetString());
        Assert.Equal(BackupStatusMonitor.AlertKind, alert.GetProperty("kind").GetString());
        Assert.Equal(BackupStatusMonitor.AlertSeverity, alert.GetProperty("severity").GetString());
        Assert.Equal(BackupStatusMonitor.AlertTitle, alert.GetProperty("title").GetString());
        Assert.Equal(BackupStatusMonitor.AlertActionTarget, alert.GetProperty("actionTarget").GetString());
        Assert.False(alert.GetProperty("isRead").GetBoolean());
        Assert.Equal(JsonValueKind.Null, alert.GetProperty("resolvedAt").ValueKind);

        var message = alert.GetProperty("message").GetString()!;
        Assert.Contains("backup do banco de dados", message, StringComparison.Ordinal);
        Assert.Contains("26/11/2026 03:30 UTC", message, StringComparison.Ordinal);

        // Subsequent successful backup -> resolves the active alert automatically.
        await File.WriteAllTextAsync(
            statusFilePath,
            "timestamp=2026-11-27T03:30:00Z\nstatus=ok\nstep=completed\n",
            Ct);

        await monitor.CheckOnceAsync(Ct);

        var alertsAfterRecovery = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Equal(0, alertsAfterRecovery.GetProperty("unreadCount").GetInt32());
        Assert.Empty(alertsAfterRecovery.GetProperty("items").EnumerateArray());

        var allAlerts = await client.GetFromJsonAsync<JsonElement>("/api/v1/alerts?includeResolved=true", Ct);
        var resolvedItems = allAlerts.GetProperty("items").EnumerateArray().ToList();
        var resolvedAlert = Assert.Single(resolvedItems);
        Assert.Equal(BackupStatusMonitor.AlertDedupKey, resolvedAlert.GetProperty("dedupKey").GetString());
        Assert.Equal(JsonValueKind.String, resolvedAlert.GetProperty("resolvedAt").ValueKind);
    }

    [Fact]
    public async Task Unconfigured_oversized_malformed_and_untrusted_step_files_are_handled_safely()
    {
        // Unconfigured Backup:StatusFile -> clean no-op.
        var unconfiguredClient = await CreateAuthenticatedClientAsync(_api);
        var unconfiguredMonitor = _api.Services.GetRequiredService<BackupStatusMonitor>();
        await unconfiguredMonitor.CheckOnceAsync(Ct);

        var initialAlerts = await unconfiguredClient.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Empty(initialAlerts.GetProperty("items").EnumerateArray());

        var statusFilePath = Path.Combine(_statusDir, "edge-case.status");
        using var configuredFactory = _api.WithWebHostBuilder(builder =>
            builder.UseSetting("BACKUP_STATUS_FILE", statusFilePath));
        var monitor = configuredFactory.Services.GetRequiredService<BackupStatusMonitor>();

        // Oversized file (> 4 KiB) -> ignored cleanly.
        await File.WriteAllTextAsync(
            statusFilePath,
            "status=failed\nstep=postgres_backup\npad=" + new string('x', BackupStatusParser.MaxBytes + 64),
            Ct);
        await monitor.CheckOnceAsync(Ct);

        // Malformed content -> ignored cleanly.
        await File.WriteAllTextAsync(statusFilePath, "corrupted content without equals", Ct);
        await monitor.CheckOnceAsync(Ct);

        var alertsAfterInvalid = await unconfiguredClient.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        Assert.Empty(alertsAfterInvalid.GetProperty("items").EnumerateArray());

        // Unknown/untrusted step -> raises alert with safe fallback label and never echoes raw text.
        await File.WriteAllTextAsync(
            statusFilePath,
            "status=failed\nstep=evil_payload_do_not_echo\n",
            Ct);
        await monitor.CheckOnceAsync(Ct);

        var alertsAfterFallback = await unconfiguredClient.GetFromJsonAsync<JsonElement>("/api/v1/alerts", Ct);
        var alert = Assert.Single(alertsAfterFallback.GetProperty("items").EnumerateArray().ToList());
        var message = alert.GetProperty("message").GetString()!;
        Assert.Contains(BackupStatusParser.FallbackStepLabelPtBr, message, StringComparison.Ordinal);
        Assert.DoesNotContain("evil_payload_do_not_echo", message, StringComparison.Ordinal);
    }

    private static async Task<HttpClient> CreateAuthenticatedClientAsync(
        Microsoft.AspNetCore.Mvc.Testing.WebApplicationFactory<Program> factory)
    {
        var client = factory.CreateClient();
        const string email = "backup-monitor@demo.local";
        const string password = "SenhaForte!2026#Test";

        var setupResp = await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email,
            displayName = "Owner Demo",
            password,
        }, Ct);
        setupResp.EnsureSuccessStatusCode();

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
        return client;
    }
}
