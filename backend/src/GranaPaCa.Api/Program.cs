using GranaPaCa.Api;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

// Read when first resolved, after every configuration source (including test overrides) is in place.
builder.Services.AddSingleton(services => NpgsqlDataSource.Create(
    services.GetRequiredService<IConfiguration>().GetConnectionString("Postgres")
    ?? throw new InvalidOperationException("Set the connection string ConnectionStrings__Postgres.")));
builder.Services.AddHealthChecks().AddCheck<PostgresHealthCheck>("postgres");

var app = builder.Build();

app.MapHealthChecks("/health");

app.Run();
