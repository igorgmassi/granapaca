using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Konscious.Security.Cryptography;

namespace GranaPaCa.Modules.Identity;

internal static class PasswordHasher
{
    private const int SaltLengthBytes = 16;
    private const int HashLengthBytes = 32;
    private const int DefaultMemorySizeKiB = 65536; // 64 MiB
    private const int DefaultIterations = 3;
    private const int DefaultDegreeOfParallelism = 1;

    private static readonly Lazy<string> LazyDummyHash = new(
        () => Hash(Convert.ToHexString(RandomNumberGenerator.GetBytes(24))),
        LazyThreadSafetyMode.ExecutionAndPublication);

    internal static string Hash(string password)
    {
        ArgumentNullException.ThrowIfNull(password);

        var salt = RandomNumberGenerator.GetBytes(SaltLengthBytes);
        var hash = ComputeHash(password, salt, DefaultMemorySizeKiB, DefaultIterations, DefaultDegreeOfParallelism, HashLengthBytes);

        return string.Create(
            CultureInfo.InvariantCulture,
            $"$argon2id$m={DefaultMemorySizeKiB},t={DefaultIterations},p={DefaultDegreeOfParallelism}${Convert.ToBase64String(salt)}${Convert.ToBase64String(hash)}");
    }

    internal static bool Verify(string password, string encodedHash)
    {
        if (string.IsNullOrEmpty(password) || string.IsNullOrEmpty(encodedHash))
        {
            return false;
        }

        if (!TryParse(encodedHash, out var memorySizeKiB, out var iterations, out var parallelism, out var salt, out var expectedHash))
        {
            return false;
        }

        var computed = ComputeHash(password, salt, memorySizeKiB, iterations, parallelism, expectedHash.Length);
        try
        {
            return CryptographicOperations.FixedTimeEquals(computed, expectedHash);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(computed);
        }
    }

    internal static void VerifyDummy(string? password)
    {
        _ = Verify(string.IsNullOrEmpty(password) ? "invalid-placeholder" : password, LazyDummyHash.Value);
    }

    private static byte[] ComputeHash(
        string password,
        byte[] salt,
        int memorySizeKiB,
        int iterations,
        int parallelism,
        int hashLength)
    {
        var passwordBytes = Encoding.UTF8.GetBytes(password);
        try
        {
            using var argon2 = new Argon2id(passwordBytes)
            {
                Salt = salt,
                MemorySize = memorySizeKiB,
                Iterations = iterations,
                DegreeOfParallelism = parallelism,
            };

            return argon2.GetBytes(hashLength);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(passwordBytes);
        }
    }

    private static bool TryParse(
        string encodedHash,
        out int memorySizeKiB,
        out int iterations,
        out int parallelism,
        out byte[] salt,
        out byte[] hash)
    {
        memorySizeKiB = 0;
        iterations = 0;
        parallelism = 0;
        salt = [];
        hash = [];

        var parts = encodedHash.Split('$');
        if (parts.Length != 5 || !string.IsNullOrEmpty(parts[0]) || !string.Equals(parts[1], "argon2id", StringComparison.Ordinal))
        {
            return false;
        }

        var paramParts = parts[2].Split(',');
        if (paramParts.Length != 3)
        {
            return false;
        }

        foreach (var param in paramParts)
        {
            if (param.StartsWith("m=", StringComparison.Ordinal) &&
                int.TryParse(param.AsSpan(2), NumberStyles.None, CultureInfo.InvariantCulture, out var m))
            {
                memorySizeKiB = m;
            }
            else if (param.StartsWith("t=", StringComparison.Ordinal) &&
                     int.TryParse(param.AsSpan(2), NumberStyles.None, CultureInfo.InvariantCulture, out var t))
            {
                iterations = t;
            }
            else if (param.StartsWith("p=", StringComparison.Ordinal) &&
                     int.TryParse(param.AsSpan(2), NumberStyles.None, CultureInfo.InvariantCulture, out var p))
            {
                parallelism = p;
            }
            else
            {
                return false;
            }
        }

        if (memorySizeKiB is < 8192 or > 1048576 || iterations is < 1 or > 20 || parallelism is < 1 or > 16)
        {
            return false;
        }

        if (!TryDecodeBase64(parts[3], out salt) || !TryDecodeBase64(parts[4], out hash))
        {
            return false;
        }

        return salt.Length >= 8 && hash.Length >= 16;
    }

    private static bool TryDecodeBase64(string value, out byte[] bytes)
    {
        bytes = [];
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var padded = (value.Length % 4) switch
        {
            2 => value + "==",
            3 => value + "=",
            _ => value,
        };

        try
        {
            bytes = Convert.FromBase64String(padded);
            return true;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}

internal static class PasswordPolicy
{
    private const int MinLength = 12;
    private const int MaxLength = 256;

    private static readonly HashSet<string> CommonWeakPasswords = new(StringComparer.OrdinalIgnoreCase)
    {
        "Password123!",
        "Password1234!",
        "Password12345!",
        "P@ssw0rd1234!",
        "Admin123456!",
        "Administrator1!",
        "Qwerty123456!",
        "Qwertyuiop1!",
        "Welcome1234!",
        "Welcome12345!",
        "Changeme1234!",
        "Letmein12345!",
        "Senha123456!",
        "Mudar123456!",
        "Teste123456!",
        "Granapaca123!",
        "GranaPaca1234!",
        "1234567890Aa!",
        "Abcdefgh1234!",
        "Aa1234567890!",
    };

    internal static (bool IsValid, string? ErrorMessage) Validate(string? password)
    {
        if (string.IsNullOrEmpty(password) || password.Length < MinLength)
        {
            return (false, "A senha deve ter pelo menos 12 caracteres.");
        }

        if (password.Length > MaxLength)
        {
            return (false, "A senha excede o tamanho máximo permitido.");
        }

        var hasLower = false;
        var hasUpper = false;
        var hasDigit = false;
        var hasSpecial = false;

        foreach (var ch in password)
        {
            if (char.IsLower(ch))
            {
                hasLower = true;
            }
            else if (char.IsUpper(ch))
            {
                hasUpper = true;
            }
            else if (char.IsDigit(ch))
            {
                hasDigit = true;
            }
            else
            {
                hasSpecial = true;
            }
        }

        if (!hasLower)
        {
            return (false, "A senha deve conter pelo menos uma letra minúscula.");
        }

        if (!hasUpper)
        {
            return (false, "A senha deve conter pelo menos uma letra maiúscula.");
        }

        if (!hasDigit)
        {
            return (false, "A senha deve conter pelo menos um número.");
        }

        if (!hasSpecial)
        {
            return (false, "A senha deve conter pelo menos um caractere especial.");
        }

        if (CommonWeakPasswords.Contains(password))
        {
            return (false, "A senha escolhida é muito comum. Escolha uma senha mais forte.");
        }

        return (true, null);
    }
}
