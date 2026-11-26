using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace GranaPaCa.Api;

internal sealed class BackupStatusMonitorWorker(
    BackupStatusMonitor monitor,
    IConfiguration configuration,
    ILogger<BackupStatusMonitorWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var enabled = configuration.GetValue("Backup:EnableStatusMonitor", true);
        if (!enabled)
        {
            logger.LogInformation("BackupStatusMonitorWorker is disabled by configuration.");
            return;
        }

        var initialDelaySeconds = Math.Max(0, configuration.GetValue("Backup:InitialDelaySeconds", 5));
        var pollIntervalSeconds = Math.Max(1, configuration.GetValue("Backup:PollIntervalSeconds", 60));

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

        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(pollIntervalSeconds));
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await monitor.CheckOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }

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
}
