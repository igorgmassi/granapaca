using System.Buffers.Binary;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace GranaPaCa.Modules.Identity;

internal static class TotpService
{
    private const int SecretLengthBytes = 20;
    private const int PeriodSeconds = 30;
    private const int Digits = 6;
    private const int AllowedWindowSteps = 1;
    private const string Issuer = "GranaPaCa";
    private const string Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    internal static byte[] GenerateSecret() => RandomNumberGenerator.GetBytes(SecretLengthBytes);

    internal static string BuildOtpAuthUri(string email, string base32Secret)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(email);
        ArgumentException.ThrowIfNullOrWhiteSpace(base32Secret);

        return $"otpauth://totp/{Issuer}:{Uri.EscapeDataString(email)}?secret={base32Secret}&issuer={Issuer}&algorithm=SHA1&digits={Digits}&period={PeriodSeconds}";
    }

    internal static string EncodeBase32(ReadOnlySpan<byte> data)
    {
        if (data.IsEmpty)
        {
            return string.Empty;
        }

        var outputLength = (data.Length * 8 + 4) / 5;
        var chars = new char[outputLength];
        var buffer = 0;
        var bitsLeft = 0;
        var index = 0;

        foreach (var b in data)
        {
            buffer = (buffer << 8) | b;
            bitsLeft += 8;

            while (bitsLeft >= 5)
            {
                bitsLeft -= 5;
                chars[index++] = Base32Alphabet[(buffer >> bitsLeft) & 0x1F];
            }
        }

        if (bitsLeft > 0)
        {
            chars[index++] = Base32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F];
        }

        return new string(chars, 0, index);
    }

    internal static byte[] DecodeBase32(string encoded)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(encoded);

        var buffer = 0;
        var bitsLeft = 0;
        var output = new List<byte>(encoded.Length * 5 / 8);

        foreach (var rawChar in encoded)
        {
            if (rawChar is ' ' or '-' or '=')
            {
                continue;
            }

            var c = char.ToUpperInvariant(rawChar);
            var value = c switch
            {
                >= 'A' and <= 'Z' => c - 'A',
                >= '2' and <= '7' => c - '2' + 26,
                _ => throw new FormatException($"Invalid Base32 character '{rawChar}'."),
            };

            buffer = (buffer << 5) | value;
            bitsLeft += 5;

            if (bitsLeft >= 8)
            {
                bitsLeft -= 8;
                output.Add((byte)((buffer >> bitsLeft) & 0xFF));
            }
        }

        return [.. output];
    }

    internal static string ComputeCode(ReadOnlySpan<byte> secret, long counter)
    {
        Span<byte> counterBytes = stackalloc byte[8];
        BinaryPrimitives.WriteInt64BigEndian(counterBytes, counter);

        Span<byte> hash = stackalloc byte[20];
        HMACSHA1.HashData(secret, counterBytes, hash);

        var offset = hash[19] & 0x0F;
        var binaryCode =
            ((hash[offset] & 0x7F) << 24) |
            ((hash[offset + 1] & 0xFF) << 16) |
            ((hash[offset + 2] & 0xFF) << 8) |
            (hash[offset + 3] & 0xFF);

        var otp = binaryCode % 1_000_000;
        return otp.ToString("D6", CultureInfo.InvariantCulture);
    }

    internal static bool VerifyCode(ReadOnlySpan<byte> secret, string? code, DateTimeOffset? now = null)
    {
        if (secret.IsEmpty || string.IsNullOrWhiteSpace(code))
        {
            return false;
        }

        Span<byte> candidateBytes = stackalloc byte[Digits];
        var length = 0;
        foreach (var ch in code)
        {
            if (char.IsWhiteSpace(ch))
            {
                continue;
            }

            if (ch is < '0' or > '9' || length >= Digits)
            {
                return false;
            }

            candidateBytes[length++] = (byte)ch;
        }

        if (length != Digits)
        {
            return false;
        }

        var currentStep = (now ?? DateTimeOffset.UtcNow).ToUnixTimeSeconds() / PeriodSeconds;
        var matched = false;
        Span<byte> expectedBytes = stackalloc byte[Digits];

        for (var delta = -AllowedWindowSteps; delta <= AllowedWindowSteps; delta++)
        {
            var expected = ComputeCode(secret, currentStep + delta);
            Encoding.ASCII.GetBytes(expected, expectedBytes);
            matched |= CryptographicOperations.FixedTimeEquals(candidateBytes, expectedBytes);
        }

        return matched;
    }
}
