using System.Net;
using GranaPaCa.Api;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class ApiTests(ApiFactory api) : IClassFixture<ApiFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    // DbUp journals each script by its full resource name, so renaming the project, root namespace,
    // Migrations folder or file would run it again on existing databases. Append new scripts; never edit an entry.
    private static readonly string[] AppliedMigrations =
    [
        "GranaPaCa.Api.Migrations.0001_drop_sample_schema.sql",
        "GranaPaCa.Modules.Alerts.Migrations.0001_create_alerts_schema.sql",
        "GranaPaCa.Modules.Assistant.Migrations.0001_create_assistant_schema.sql",
        "GranaPaCa.Modules.Banking.Migrations.0001_create_banking_schema.sql",
        "GranaPaCa.Modules.Banking.Migrations.0002_add_sync_updated_at.sql",
        "GranaPaCa.Modules.Banking.Migrations.0003_cash_tags_splits_payment_method.sql",
        "GranaPaCa.Modules.Categorization.Migrations.0001_create_categorization_schema.sql",
        "GranaPaCa.Modules.Categorization.Migrations.0002_add_rule_updated_at.sql",
        "GranaPaCa.Modules.Identity.Migrations.0001_create_identity_schema.sql",
        "GranaPaCa.Modules.Keyring.Migrations.0001_create_keyring_schema.sql",
        "GranaPaCa.Modules.Planning.Migrations.0001_create_planning_schema.sql",
        "GranaPaCa.Modules.Receipts.Migrations.0001_create_receipts_schema.sql",
    ];

    [Fact]
    public async Task Migration_names_in_the_journal_never_change()
    {
        await using var query = api.Services.GetRequiredService<NpgsqlDataSource>()
            .CreateCommand("SELECT array_agg(scriptname) FROM schemaversions");
        var journal = (string[])(await query.ExecuteScalarAsync(Ct))!;

        Assert.Equal(AppliedMigrations.Order(StringComparer.Ordinal), journal.Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task Health_reports_postgres_as_healthy()
    {
        var response = await api.CreateClient().GetAsync("/health", Ct);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var report = await api.Services.GetRequiredService<HealthCheckService>().CheckHealthAsync(Ct);
        Assert.Equal(HealthStatus.Healthy, report.Entries["postgres"].Status);
    }

    [Fact]
    public async Task Sample_schema_and_endpoint_were_removed()
    {
        await using var query = api.Services.GetRequiredService<NpgsqlDataSource>()
            .CreateCommand("SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 'sample'");
        var count = Convert.ToInt64(await query.ExecuteScalarAsync(Ct));
        Assert.Equal(0, count);

        var response = await api.CreateClient().GetAsync("/sample/items", Ct);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Protected_endpoints_reject_unauthenticated_requests()
    {
        var client = api.CreateClient();

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/summary", Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/transactions", Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/alerts", Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/v1/rules", Ct)).StatusCode);
    }

    [Theory]
    [InlineData("")]
    [InlineData("short")]
    [InlineData("postgres")]
    [InlineData("1234567890123456")]
    [InlineData("aaaaaaaaaaaaaaaaaaaa")]
    public void Weak_database_passwords_are_rejected(string weakPassword)
    {
        Assert.Throws<InvalidOperationException>(() =>
            PostgresConnectionResolver.ValidatePasswordStrength(weakPassword));
    }

    [Fact]
    public void Strong_database_password_is_accepted()
    {
        var generated = Convert.ToHexStringLower(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        PostgresConnectionResolver.ValidatePasswordStrength(generated);
    }
}
