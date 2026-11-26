using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text;
using GranaPaCa.Modules.Alerts.Contracts;
using GranaPaCa.Modules.Identity.Contracts;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GranaPaCa.Api;

internal sealed record BackupStatusSnapshot(
    string Status,
    string StepToken,
    string StepLabelPtBr,
    DateTimeOffset? TimestampUtc);

internal static class BackupStatusParser
{
    public const int MaxBytes = 4096;
    public const string FallbackStepToken = "unknown";
    public const string FallbackStepLabelPtBr = "execução do backup";

    private static readonly IReadOnlyDictionary<string, string> KnownStepsPtBr =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["init"] = "inicialização do backup",
            ["prerequisites"] = "verificação de pré-requisitos",
            ["restic_repo_check"] = "acesso ao repositório cifrado",
            ["postgres_healthcheck"] = "verificação do banco de dados",
            ["postgres_backup"] = "backup do banco de dados",
            ["files_backup"] = "backup dos arquivos cifrados",
            ["retention_prune"] = "limpeza de retenção",
            ["integrity_check"] = "verificação de integridade do backup",
            ["write_status"] = "registro do estado do backup",
        };

    public static bool TryParse(string? content, [NotNullWhen(true)] out BackupStatusSnapshot? snapshot)
    {
        snapshot = null;

        if (string.IsNullOrWhiteSpace(content)
            || content.Length > MaxBytes
            || Encoding.UTF8.GetByteCount(content) > MaxBytes)
        {
            return false;
        }

        string? rawStatus = null;
        string? rawStep = null;
        string? rawTimestamp = null;

        foreach (var rawLine in content.TrimStart('\uFEFF').Split('\n'))
        {
            var line = rawLine.TrimEnd('\r').Trim();
            if (line.Length == 0)
            {
                continue;
            }

            var separatorIndex = line.IndexOf('=');
            if (separatorIndex <= 0)
            {
                return false;
            }

            var key = line[..separatorIndex].Trim();
            var value = line[(separatorIndex + 1)..].Trim();

            if (key.Equals("status", StringComparison.OrdinalIgnoreCase))
            {
                rawStatus = value;
            }
            else if (key.Equals("step", StringComparison.OrdinalIgnoreCase))
            {
                rawStep = value;
            }
            else if (key.Equals("timestamp", StringComparison.OrdinalIgnoreCase))
            {
                rawTimestamp = value;
            }
        }

        string normalizedStatus;
        if (string.Equals(rawStatus, "ok", StringComparison.OrdinalIgnoreCase))
        {
            normalizedStatus = "ok";
        }
        else if (string.Equals(rawStatus, "failed", StringComparison.OrdinalIgnoreCase))
        {
            normalizedStatus = "failed";
        }
        else
        {
            return false;
        }

        DateTimeOffset? timestampUtc = null;
        if (!string.IsNullOrWhiteSpace(rawTimestamp)
            && DateTimeOffset.TryParse(
                rawTimestamp,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsedTimestamp))
        {
            timestampUtc = parsedTimestamp.ToUniversalTime();
        }

        var stepToken = FallbackStepToken;
        var stepLabel = FallbackStepLabelPtBr;
        if (!string.IsNullOrWhiteSpace(rawStep) && KnownStepsPtBr.TryGetValue(rawStep, out var mappedLabel))
        {
            stepToken = rawStep.ToLowerInvariant();
            stepLabel = mappedLabel;
        }

        snapshot = new BackupStatusSnapshot(normalizedStatus, stepToken, stepLabel, timestampUtc);
        return true;
    }
}

internal sealed class BackupStatusMonitor(
    IConfiguration configuration,
    IHouseholdDirectory householdDirectory,
    IAlertPublisher alertPublisher,
    ILogger<BackupStatusMonitor> logger)
{
    public const string AlertDedupKey = "backup:failed";
    public const string AlertKind = "backup_failed";
    public const string AlertSeverity = "error";
    public const string AlertTitle = "O backup cifrado falhou";
    public const string AlertActionTarget = "settings";

    public async Task CheckOnceAsync(CancellationToken cancellationToken = default)
    {
        var configuredPath = configuration["Backup:StatusFile"];
        if (string.IsNullOrWhiteSpace(configuredPath))
        {
            configuredPath = configuration["BACKUP_STATUS_FILE"];
        }

        if (string.IsNullOrWhiteSpace(configuredPath))
        {
            return;
        }

        var statusFilePath = configuredPath.Trim();
        if (!File.Exists(statusFilePath))
        {
            return;
        }

        string? content;
        try
        {
            content = await ReadBoundedUtf8Async(statusFilePath, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
        {
            return;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning("Backup status file could not be read; errorCode=backup_status_io_failed");
            return;
        }

        if (content is null)
        {
            logger.LogWarning("Backup status file exceeded size limit; errorCode=backup_status_too_large");
            return;
        }

        if (!BackupStatusParser.TryParse(content, out var snapshot))
        {
            logger.LogWarning("Backup status file could not be parsed; errorCode=backup_status_parse_failed");
            return;
        }

        try
        {
            var householdIds = await householdDirectory.ListHouseholdIdsAsync(cancellationToken);
            if (householdIds.Count == 0)
            {
                return;
            }

            if (snapshot.Status == "failed")
            {
                var message = BuildFailureMessage(snapshot);
                foreach (var householdId in householdIds)
                {
                    await alertPublisher.RaiseAsync(
                        new AlertRequest(
                            householdId,
                            AlertDedupKey,
                            AlertKind,
                            AlertSeverity,
                            AlertTitle,
                            message,
                            AlertActionTarget),
                        cancellationToken);
                }
            }
            else
            {
                foreach (var householdId in householdIds)
                {
                    await alertPublisher.ResolveAsync(householdId, AlertDedupKey, cancellationToken);
                }
            }
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception)
        {
            logger.LogWarning("Backup status alert synchronization failed; errorCode=backup_status_sync_failed");
        }
    }

    private static string BuildFailureMessage(BackupStatusSnapshot snapshot)
    {
        if (snapshot.TimestampUtc is { } timestampUtc)
        {
            var formattedTimestamp = timestampUtc.ToUniversalTime()
                .ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture);
            return $"A última rotina falhou na etapa \"{snapshot.StepLabelPtBr}\" em {formattedTimestamp} UTC. Verifique os logs de backup no servidor e o guia infra/BACKUP.md.";
        }

        return $"A última rotina falhou na etapa \"{snapshot.StepLabelPtBr}\". Verifique os logs de backup no servidor e o guia infra/BACKUP.md.";
    }

    private static async Task<string?> ReadBoundedUtf8Async(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete,
            bufferSize: 4096,
            useAsync: true);

        var buffer = new byte[BackupStatusParser.MaxBytes + 1];
        var totalRead = 0;

        while (totalRead < buffer.Length)
        {
            var bytesRead = await stream.ReadAsync(
                buffer.AsMemory(totalRead, buffer.Length - totalRead),
                cancellationToken);
            if (bytesRead == 0)
            {
                break;
            }

            totalRead += bytesRead;
        }

        if (totalRead > BackupStatusParser.MaxBytes)
        {
            return null;
        }

        return Encoding.UTF8.GetString(buffer, 0, totalRead);
    }
}
