using GranaPaCa.Api;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class PostgresHealthCheckTests
{
    [Fact]
    public async Task Fails_when_postgres_is_unreachable()
    {
        await using var dataSource = NpgsqlDataSource.Create("Host=127.0.0.1;Port=1;Timeout=2");

        await Assert.ThrowsAnyAsync<NpgsqlException>(() => new PostgresHealthCheck(dataSource)
            .CheckHealthAsync(new HealthCheckContext(), TestContext.Current.CancellationToken));
    }
}
