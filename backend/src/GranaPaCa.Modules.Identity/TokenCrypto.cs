using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace GranaPaCa.Modules.Identity;

internal static class TokenCrypto
{
    private const int OpaqueTokenBytes = 32;
    private const string RecoveryCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    internal static string GenerateOpaqueToken()
    {
        Span<byte> bytes = stackalloc byte[OpaqueTokenBytes];
        RandomNumberGenerator.Fill(bytes);
        return Base64Url.EncodeToString(bytes);
    }

    internal static string HashToken(string token)
    {
        ArgumentException.ThrowIfNullOrEmpty(token);
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        return Convert.ToHexStringLower(hash);
    }

    internal static IReadOnlyList<string> GenerateRecoveryCodes(int count = 8)
    {
        var codes = new string[count];
        Span<char> buffer = stackalloc char[9];

        for (var i = 0; i < count; i++)
        {
            for (var j = 0; j < 4; j++)
            {
                buffer[j] = RecoveryCodeAlphabet[RandomNumberGenerator.GetInt32(RecoveryCodeAlphabet.Length)];
            }

            buffer[4] = '-';

            for (var j = 5; j < 9; j++)
            {
                buffer[j] = RecoveryCodeAlphabet[RandomNumberGenerator.GetInt32(RecoveryCodeAlphabet.Length)];
            }

            codes[i] = new string(buffer);
        }

        return codes;
    }

    internal static string NormalizeRecoveryCode(string code)
    {
        var sb = new StringBuilder(code.Length);
        foreach (var ch in code)
        {
            if (ch is '-' || char.IsWhiteSpace(ch))
            {
                continue;
            }

            sb.Append(char.ToUpperInvariant(ch));
        }

        return sb.ToString();
    }

    internal static string HashRecoveryCode(string code) => HashToken(NormalizeRecoveryCode(code));
}
