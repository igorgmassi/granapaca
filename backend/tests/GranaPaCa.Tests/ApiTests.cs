using System.Net;
using System.Net.Http.Json;
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
        "GranaPaCa.Modules.Sample.Migrations.0001_create_sample_schema.sql",
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
    public async Task Sample_items_come_from_the_migrated_schema()
    {
        var id = Guid.CreateVersion7();
        await using (var insert = api.Services.GetRequiredService<NpgsqlDataSource>()
            .CreateCommand("INSERT INTO sample.item (id, name) VALUES ($1, $2)"))
        {
            insert.Parameters.Add(new NpgsqlParameter { Value = id });
            insert.Parameters.Add(new NpgsqlParameter { Value = "first item" });
            await insert.ExecuteNonQueryAsync(Ct);
        }

        var items = await api.CreateClient().GetFromJsonAsync<Item[]>("/sample/items", Ct);

        Assert.Contains(new Item(id, "first item"), items!);
    }

    private sealed record Item(Guid Id, string Name);
}
