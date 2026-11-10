using DbUp;
using DbUp.Postgresql;
using GranaPaCa.Api;
using GranaPaCa.Modules.Sample;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

// Read when first resolved, after every configuration source (including test overrides) is in place.
builder.Services.AddSingleton(services => NpgsqlDataSource.Create(
    services.GetRequiredService<IConfiguration>().GetConnectionString("Postgres")
    ?? throw new InvalidOperationException("Set the connection string ConnectionStrings__Postgres.")));
builder.Services.AddHealthChecks().AddCheck<PostgresHealthCheck>("postgres");

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
