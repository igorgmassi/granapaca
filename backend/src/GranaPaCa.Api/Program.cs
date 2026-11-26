using DbUp;
using DbUp.Postgresql;
using GranaPaCa.Modules.Alerts;
using GranaPaCa.Modules.Assistant;
using GranaPaCa.Modules.Banking;
using GranaPaCa.Modules.Categorization;
using GranaPaCa.Modules.Identity;
using GranaPaCa.Modules.Keyring;
using GranaPaCa.Modules.Planning;
using GranaPaCa.Modules.Receipts;
using Microsoft.AspNetCore.Authentication;
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

        DapperTypeHandlers.Register();

        var builder = WebApplication.CreateBuilder(args);

        // Read when first resolved, after every configuration source (including test overrides) is in place.
        builder.Services.AddSingleton(services =>
        {
            var configuration = services.GetRequiredService<IConfiguration>();
            var connectionString = PostgresConnectionResolver.ResolveAndValidate(configuration);
            return NpgsqlDataSource.Create(connectionString);
        });

        builder.Services.AddHealthChecks()
            .AddCheck<PostgresHealthCheck>("postgres", timeout: TimeSpan.FromSeconds(5));

        builder.Services.AddAuthentication(OpaqueBearerAuthenticationHandler.SchemeName)
            .AddScheme<AuthenticationSchemeOptions, OpaqueBearerAuthenticationHandler>(
                OpaqueBearerAuthenticationHandler.SchemeName,
                _ => { });
        builder.Services.AddAuthorization();
        builder.Services.AddProblemDetails();
        builder.Services.AddOpenApi();

        builder.Services.AddKeyringModule(builder.Configuration);
        builder.Services.AddIdentityModule(builder.Configuration);
        builder.Services.AddAlertsModule();
        builder.Services.AddCategorizationModule(builder.Configuration);
        builder.Services.AddBankingModule(builder.Configuration);
        builder.Services.AddPlanningModule();
        builder.Services.AddReceiptsModule(builder.Configuration);
        builder.Services.AddAssistantModule(builder.Configuration);

        var app = builder.Build();

        // Each module embeds its own SQL scripts; the pending ones run here, before the API accepts requests.
        var migration = DeployChanges.To
            .PostgresqlDatabase(new PostgresqlConnectionManager(app.Services.GetRequiredService<NpgsqlDataSource>()))
            .WithScriptsEmbeddedInAssemblies([
                typeof(Program).Assembly,
                typeof(KeyringModule).Assembly,
                typeof(IdentityModule).Assembly,
                typeof(AlertsModule).Assembly,
                typeof(CategorizationModule).Assembly,
                typeof(BankingModule).Assembly,
                typeof(PlanningModule).Assembly,
                typeof(ReceiptsModule).Assembly,
                typeof(AssistantModule).Assembly,
            ])
            .WithTransactionPerScript()
            .LogTo(app.Logger)
            .Build()
            .PerformUpgrade();
        if (!migration.Successful)
        {
            throw new InvalidOperationException("Database migration failed, so the API will not start.", migration.Error);
        }

        app.UseAuthentication();
        app.UseAuthorization();

        app.MapHealthChecks("/health").AllowAnonymous();
        app.MapOpenApi().AllowAnonymous();
        app.MapIdentityEndpoints();
        app.MapAlertsEndpoints();
        app.MapCategorizationEndpoints();
        app.MapBankingEndpoints();
        app.MapPlanningEndpoints();
        app.MapReceiptsEndpoints();
        app.MapAssistantEndpoints();
        app.MapAccountPurgeEndpoints();

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
