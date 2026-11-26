using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

namespace GranaPaCa.Modules.Keyring;

internal sealed class MasterKeyRing : IDisposable
{
    private const int KeyLengthBytes = 32;
    private const string DefaultKeyId = "mk-1";

    private readonly Dictionary<string, byte[]> _keys;
    private bool _disposed;

    private MasterKeyRing(string primaryKeyId, Dictionary<string, byte[]> keys)
    {
        PrimaryKeyId = primaryKeyId;
        _keys = keys;
    }

    internal string PrimaryKeyId { get; }

    internal byte[] PrimaryKey => GetKey(PrimaryKeyId);

    internal static MasterKeyRing Load(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var rawPrimary = ResolvePrimaryMaterial(configuration);
        var (primaryId, primaryBytes) = ParseKeyEntry(rawPrimary, "primary master key");

        var keys = new Dictionary<string, byte[]>(StringComparer.Ordinal)
        {
            [primaryId] = primaryBytes,
        };

        try
        {
            foreach (var rawPrevious in ResolvePreviousEntries(configuration))
            {
                var (prevId, prevBytes) = ParseKeyEntry(rawPrevious, "previous master key");
                if (!keys.TryAdd(prevId, prevBytes))
                {
                    CryptographicOperations.ZeroMemory(prevBytes);
                    throw new InvalidOperationException(
                        $"Duplicate master key identifier '{prevId}' configured in keyring.");
                }
            }
        }
        catch
        {
            foreach (var material in keys.Values)
            {
                CryptographicOperations.ZeroMemory(material);
            }

            throw;
        }

        return new MasterKeyRing(primaryId, keys);
    }

    internal byte[] GetKey(string keyId)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        if (!_keys.TryGetValue(keyId, out var key))
        {
            throw new CryptographicException(
                $"Master key '{keyId}' is not available in the configured master key ring.");
        }

        return key;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        foreach (var material in _keys.Values)
        {
            CryptographicOperations.ZeroMemory(material);
        }

        _keys.Clear();
    }

    private static string ResolvePrimaryMaterial(IConfiguration configuration)
    {
        var filePath = FirstNonEmpty(
            configuration["GRANAPACA_MASTER_KEY_FILE"],
            configuration["Keyring:MasterKeyFile"]);

        if (filePath is not null)
        {
            if (!File.Exists(filePath))
            {
                throw new InvalidOperationException(
                    $"Master key file '{filePath}' was not found (RN-39).");
            }

            string content;
            try
            {
                content = File.ReadAllText(filePath).Trim();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                throw new InvalidOperationException(
                    $"Could not read master key file '{filePath}' (RN-39).", ex);
            }

            if (string.IsNullOrWhiteSpace(content))
            {
                throw new InvalidOperationException(
                    $"Master key file '{filePath}' is empty (RN-39).");
            }

            return content;
        }

        var directValue = FirstNonEmpty(
            configuration["GRANAPACA_MASTER_KEY"],
            configuration["Keyring:MasterKey"]);

        if (directValue is null)
        {
            throw new InvalidOperationException(
                "Master key is missing (RN-39). Configure GRANAPACA_MASTER_KEY_FILE, Keyring:MasterKeyFile, GRANAPACA_MASTER_KEY, or Keyring:MasterKey.");
        }

        return directValue;
    }

    private static IEnumerable<string> ResolvePreviousEntries(IConfiguration configuration)
    {
        var raw = FirstNonEmpty(
            configuration["Keyring:PreviousMasterKeys"],
            configuration["GRANAPACA_PREVIOUS_MASTER_KEYS"]);

        if (raw is not null)
        {
            foreach (var part in raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (!string.IsNullOrWhiteSpace(part))
                {
                    yield return part;
                }
            }

            yield break;
        }

        foreach (var child in configuration.GetSection("Keyring:PreviousMasterKeys").GetChildren())
        {
            var value = child.Value?.Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                yield return value;
            }
        }
    }

    private static (string KeyId, byte[] Material) ParseKeyEntry(string rawEntry, string sourceDescription)
    {
        var trimmed = rawEntry.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            throw new InvalidOperationException($"The {sourceDescription} cannot be empty.");
        }

        string keyId;
        string encodedMaterial;

        var separatorIndex = trimmed.IndexOf(':');
        if (separatorIndex >= 0)
        {
            keyId = trimmed[..separatorIndex].Trim();
            encodedMaterial = trimmed[(separatorIndex + 1)..].Trim();
            if (string.IsNullOrEmpty(keyId))
            {
                throw new InvalidOperationException(
                    $"The {sourceDescription} has an empty key identifier before ':'.");
            }
        }
        else
        {
            keyId = DefaultKeyId;
            encodedMaterial = trimmed;
        }

        var keyBytes = DecodeKeyMaterial(encodedMaterial, keyId);
        if (keyBytes.Length != KeyLengthBytes)
        {
            CryptographicOperations.ZeroMemory(keyBytes);
            throw new InvalidOperationException(
                $"Master key '{keyId}' must be exactly {KeyLengthBytes} bytes (256 bits).");
        }

        if (IsAllZero(keyBytes))
        {
            throw new InvalidOperationException(
                $"Master key '{keyId}' must not be all zeros.");
        }

        return (keyId, keyBytes);
    }

    private static byte[] DecodeKeyMaterial(string encoded, string keyId)
    {
        if (string.IsNullOrWhiteSpace(encoded))
        {
            throw new InvalidOperationException(
                $"Master key '{keyId}' has no key material.");
        }

        if (encoded.Length == KeyLengthBytes * 2 && IsHexString(encoded))
        {
            return Convert.FromHexString(encoded);
        }

        try
        {
            return Convert.FromBase64String(encoded);
        }
        catch (FormatException ex)
        {
            throw new InvalidOperationException(
                $"Master key '{keyId}' must be a 64-character hex string or a base64 string decoding to 32 bytes.",
                ex);
        }
    }

    private static bool IsHexString(string value)
    {
        foreach (var c in value)
        {
            if (!Uri.IsHexDigit(c))
            {
                return false;
            }
        }

        return true;
    }

    private static bool IsAllZero(ReadOnlySpan<byte> bytes)
    {
        byte acc = 0;
        foreach (var b in bytes)
        {
            acc |= b;
        }

        return acc == 0;
    }

    private static string? FirstNonEmpty(params string?[] candidates)
    {
        foreach (var candidate in candidates)
        {
            var trimmed = candidate?.Trim();
            if (!string.IsNullOrEmpty(trimmed))
            {
                return trimmed;
            }
        }

        return null;
    }
}

internal sealed class MasterKeyStartupValidator(MasterKeyRing keyRing) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        _ = keyRing.PrimaryKeyId;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
