using System.Security.Cryptography;
using GranaPaCa.Api;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Testcontainers.PostgreSql;

namespace GranaPaCa.Tests;

// Starts a real PostgreSQL before the API, which applies all module migrations on startup.
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:18-alpine").Build();
    private readonly string _ephemeralMasterKey = $"mk-test:{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32))}";

    public async ValueTask InitializeAsync() => await _postgres.StartAsync();

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await _postgres.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        var profilesDir = FindProfilesDirectory();
        builder.UseSetting("ConnectionStrings:Postgres", _postgres.GetConnectionString());
        builder.UseSetting("Database:AllowWeakPasswordForTests", "true");
        builder.UseSetting("Keyring:MasterKey", _ephemeralMasterKey);
        builder.UseSetting("Banking:EnableBackgroundSync", "false");
        if (profilesDir is not null)
        {
            builder.UseSetting("Profiles:Directory", profilesDir);
        }
    }

    private static string? FindProfilesDirectory()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "profiles");
            if (Directory.Exists(candidate) && File.Exists(Path.Combine(candidate, "schema.json")))
            {
                return candidate;
            }

            dir = dir.Parent;
        }

        return null;
    }
}
