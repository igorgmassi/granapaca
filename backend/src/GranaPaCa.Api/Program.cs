using DbUp;
using DbUp.Postgresql;
using GranaPaCa.Modules.Sample;
using Npgsql;

namespace GranaPaCa.Api;

// A regular Main instead of top-level statements: ArchUnitNET skips the compiler-generated <Main>$,
// so the module boundary test would not see how the host uses the modules.
public sealed class Program
{
    public static void Main(string[] args)
    {
        // The chiseled image has no shell or curl, so the container healthcheck runs "dotnet GranaPaCa.Api.dll healthcheck".
        if (args is ["healthcheck"])
        {
            Environment.ExitCode = CheckOwnHealth();
            return;
        }

        var builder = WebApplication.CreateBuilder(args);

        // Read when first resolved, after every configuration source (including test overrides) is in place.
        builder.Services.AddSingleton(services => NpgsqlDataSource.Create(
            services.GetRequiredService<IConfiguration>().GetConnectionString("Postgres")
            ?? throw new InvalidOperationException("Set the connection string ConnectionStrings__Postgres.")));
        builder.Services.AddHealthChecks().AddCheck<PostgresHealthCheck>("postgres", timeout: TimeSpan.FromSeconds(5));

        var app = builder.Build();

        // Each module embeds its own SQL scripts; the pending ones run here, before the API accepts requests.
        var migration = DeployChanges.To
            .PostgresqlDatabase(new PostgresqlConnectionManager(app.Services.GetRequiredService<NpgsqlDataSource>()))
            .WithScriptsEmbeddedInAssemblies([typeof(SampleModule).Assembly])
            .WithTransactionPerScript()
            .LogTo(app.Logger)
            .Build()
            .PerformUpgrade();
        if (!migration.Successful)
        {
            throw new InvalidOperationException("Database migration failed, so the API will not start.", migration.Error);
        }

        app.MapHealthChecks("/health");
        app.MapSampleEndpoints();

        app.Run();
    }

    private static int CheckOwnHealth()
    {
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        try
        {
            // 8080 is the port the .NET container images listen on.
            return http.GetAsync("http://localhost:8080/health").Result.IsSuccessStatusCode ? 0 : 1;
        }
        catch (AggregateException)
        {
            return 1;
        }
    }
}
