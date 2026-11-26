using Dapper;
using GranaPaCa.Modules.Banking.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Npgsql;

namespace GranaPaCa.Modules.Banking;

internal sealed class DailySyncWorker(
    IServiceScopeFactory scopeFactory,
    NpgsqlDataSource dataSource,
    IConfiguration configuration,
    ILogger<DailySyncWorker> logger) : BackgroundService
{
    private const int MaxAttempts = 3;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var enabled = configuration.GetValue("Banking:EnableBackgroundSync", true);
        if (!enabled)
        {
            logger.LogInformation("DailySyncWorker is disabled by configuration.");
            return;
        }

        var initialDelaySeconds = Math.Max(0, configuration.GetValue("Banking:InitialSyncDelaySeconds", 60));
        var intervalHours = Math.Max(1, configuration.GetValue("Banking:SyncIntervalHours", 24));
        var interval = TimeSpan.FromHours(intervalHours);

        if (initialDelaySeconds > 0)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(initialDelaySeconds), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }

        using var timer = new PeriodicTimer(interval);
        while (!stoppingToken.IsCancellationRequested)
        {
            await RunCycleAsync(stoppingToken);

            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken))
                {
                    break;
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task RunCycleAsync(CancellationToken stoppingToken)
    {
        List<Guid> householdIds;
        try
        {
            await using var connection = await dataSource.OpenConnectionAsync(stoppingToken);
            householdIds = (await connection.QueryAsync<Guid>(new CommandDefinition(
                "SELECT DISTINCT household_id FROM banking.connection",
                cancellationToken: stoppingToken))).ToList();
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (Exception)
        {
            logger.LogWarning("DailySyncWorker failed to list households; errorCode=db_query_failed");
            return;
        }

        foreach (var householdId in householdIds)
        {
            if (stoppingToken.IsCancellationRequested)
            {
                break;
            }

            await SyncWithBackoffAsync(householdId, stoppingToken);
        }
    }

    private async Task SyncWithBackoffAsync(Guid householdId, CancellationToken stoppingToken)
    {
        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                await using var scope = scopeFactory.CreateAsyncScope();
                var syncTrigger = scope.ServiceProvider.GetRequiredService<IBankingSyncTrigger>();
                var summary = await syncTrigger.SyncHouseholdAsync(householdId, stoppingToken);

                if (summary.FailedConnections == 0 || attempt == MaxAttempts)
                {
                    return;
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception)
            {
                logger.LogWarning(
                    "DailySyncWorker attempt failed: attempt={Attempt} errorCode=sync_cycle_failed",
                    attempt);
            }

            if (attempt < MaxAttempts)
            {
                var backoff = TimeSpan.FromSeconds(Math.Pow(2, attempt));
                try
                {
                    await Task.Delay(backoff, stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    return;
                }
            }
        }
    }
}
