using GranaPaCa.Modules.Keyring.Contracts;
using Microsoft.Extensions.Configuration;

namespace GranaPaCa.Modules.Receipts;

/// <summary>
/// Encrypted local volume store for receipts (ADR-025).
/// Plaintext receipt bytes are never written to disk; every file is AES-256-GCM envelope encrypted via Keyring.
/// </summary>
internal sealed class EncryptedReceiptFileStore
{
    public const string EncryptionPurpose = "receipts.file";
    public const string EncryptionTable = "receipts.receipt";
    public const string EncryptionColumn = "file_content";
    private const string DefaultStoragePath = "/var/lib/granapaca/files";

    private readonly IEnvelopeEncryptor _encryptor;
    private readonly string _rootDirectory;

    public EncryptedReceiptFileStore(IEnvelopeEncryptor encryptor, IConfiguration configuration)
    {
        _encryptor = encryptor;
        var configuredPath = configuration["Receipts:StoragePath"]
            ?? configuration["RECEIPTS_STORAGE_PATH"]
            ?? DefaultStoragePath;

        _rootDirectory = ResolveWritableDirectory(configuredPath);
    }

    public async Task<string> SaveEncryptedAsync(
        Guid householdId,
        Guid receiptId,
        ReadOnlyMemory<byte> plaintextBytes,
        CancellationToken cancellationToken)
    {
        var ciphertext = await _encryptor.EncryptAsync(
            householdId,
            EncryptionPurpose,
            plaintextBytes,
            EncryptionTable,
            EncryptionColumn,
            receiptId,
            cancellationToken);

        var relPath = $"{householdId:N}/{receiptId:N}.enc";
        var fullPath = ResolveSafeFullPath(relPath);
        var directory = Path.GetDirectoryName(fullPath)!;
        Directory.CreateDirectory(directory);

        var tempPath = fullPath + ".tmp";
        await File.WriteAllBytesAsync(tempPath, ciphertext, cancellationToken);
        File.Move(tempPath, fullPath, overwrite: true);

        return relPath;
    }

    public async Task<byte[]?> ReadDecryptedAsync(
        Guid receiptId,
        string? storageRelPath,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(storageRelPath))
        {
            return null;
        }

        var fullPath = ResolveSafeFullPath(storageRelPath);
        if (!File.Exists(fullPath))
        {
            return null;
        }

        var ciphertext = await File.ReadAllBytesAsync(fullPath, cancellationToken);
        return await _encryptor.DecryptAsync(
            ciphertext,
            EncryptionTable,
            EncryptionColumn,
            receiptId,
            cancellationToken);
    }

    public void DeleteFile(string? storageRelPath)
    {
        if (string.IsNullOrWhiteSpace(storageRelPath))
        {
            return;
        }

        try
        {
            var fullPath = ResolveSafeFullPath(storageRelPath);
            if (File.Exists(fullPath))
            {
                File.Delete(fullPath);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            // File deletion is best-effort after DB removal.
        }
    }

    public void DeleteHouseholdFiles(Guid householdId, IEnumerable<string?> storageRelPaths)
    {
        foreach (var path in storageRelPaths)
        {
            DeleteFile(path);
        }

        try
        {
            var householdDir = ResolveSafeFullPath(householdId.ToString("N"));
            if (Directory.Exists(householdDir))
            {
                Directory.Delete(householdDir, recursive: true);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            // Directory cleanup is best-effort during purge.
        }
    }

    private string ResolveSafeFullPath(string relativePath)
    {
        var normalized = relativePath
            .Replace('\\', Path.DirectorySeparatorChar)
            .Replace('/', Path.DirectorySeparatorChar)
            .TrimStart(Path.DirectorySeparatorChar);

        var rootFull = Path.GetFullPath(_rootDirectory);
        var combined = Path.GetFullPath(Path.Combine(rootFull, normalized));

        if (!combined.StartsWith(rootFull + Path.DirectorySeparatorChar, StringComparison.Ordinal) &&
            !string.Equals(combined, rootFull, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Receipt storage path escapes the configured storage root.");
        }

        return combined;
    }

    private static string ResolveWritableDirectory(string configuredPath)
    {
        if (TryEnsureWritable(configuredPath, out var resolved))
        {
            return resolved;
        }

        var fallback = Path.Combine(Path.GetTempPath(), "granapaca-receipts");
        Directory.CreateDirectory(fallback);
        return Path.GetFullPath(fallback);
    }

    private static bool TryEnsureWritable(string path, out string fullPath)
    {
        fullPath = string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        try
        {
            var candidate = Path.GetFullPath(path);
            Directory.CreateDirectory(candidate);
            var probe = Path.Combine(candidate, $".write-probe-{Guid.NewGuid():N}");
            using (File.Create(probe))
            {
            }

            File.Delete(probe);
            fullPath = candidate;
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
    }
}
