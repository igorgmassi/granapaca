using Dapper;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Routing;
using Npgsql;

namespace GranaPaCa.Modules.Sample;

// Template for real modules: the host calls this entry point, and the module's tables live in the "sample" schema.
public static class SampleModule
{
    public static IEndpointRouteBuilder MapSampleEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/sample/items", async (NpgsqlDataSource dataSource, CancellationToken cancellationToken) =>
        {
            await using var connection = dataSource.CreateConnection();
            return await connection.QueryAsync<SampleItem>(new CommandDefinition(
                "SELECT id, name FROM sample.item ORDER BY id", cancellationToken: cancellationToken));
        });
        return endpoints;
    }
}

internal sealed record SampleItem(Guid Id, string Name);
