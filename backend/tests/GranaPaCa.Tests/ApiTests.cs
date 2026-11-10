using System.Net;
using System.Net.Http.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class ApiTests(ApiFactory api) : IClassFixture<ApiFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

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
