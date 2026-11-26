using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using GranaPaCa.Modules.Keyring.Contracts;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace GranaPaCa.Tests;

public sealed class KeyringAndIdentityTests : IAsyncLifetime
{
    private readonly ApiFactory _api = new();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public ValueTask InitializeAsync() => _api.InitializeAsync();
    public ValueTask DisposeAsync() => _api.DisposeAsync();

    [Fact]
    public async Task Envelope_encryption_binds_aad_rotates_deks_and_supports_cryptographic_erasure()
    {
        var encryptor = _api.Services.GetRequiredService<IEnvelopeEncryptor>();
        var householdId = Guid.CreateVersion7();
        var rowId = Guid.CreateVersion7();
        var secretBytes = Encoding.UTF8.GetBytes("segredo-ficticio-para-teste");

        var envelope = await encryptor.EncryptAsync(
            householdId, "test.secret", secretBytes, "test.table", "secret_enc", rowId, Ct);

        // Ciphertext must not contain plaintext.
        Assert.DoesNotContain("segredo-ficticio", Encoding.UTF8.GetString(envelope));

        var decrypted = await encryptor.DecryptAsync(envelope, "test.table", "secret_enc", rowId, Ct);
        Assert.Equal(secretBytes, decrypted);

        // Moving ciphertext to another row must fail AAD authentication (ADR-016).
        await Assert.ThrowsAsync<AuthenticationTagMismatchException>(() =>
            encryptor.DecryptAsync(envelope, "test.table", "secret_enc", Guid.CreateVersion7(), Ct));

        // Rotating the DEK keeps older envelopes decryptable while encrypting new ones with a new DEK.
        await encryptor.RotateDataKeyAsync(householdId, "test.secret", Ct);
        var envelope2 = await encryptor.EncryptAsync(
            householdId, "test.secret", secretBytes, "test.table", "secret_enc", rowId, Ct);

        Assert.Equal(secretBytes, await encryptor.DecryptAsync(envelope, "test.table", "secret_enc", rowId, Ct));
        Assert.Equal(secretBytes, await encryptor.DecryptAsync(envelope2, "test.table", "secret_enc", rowId, Ct));
        Assert.NotEqual(envelope[1..17], envelope2[1..17]);

        // Destroying household keys makes prior ciphertexts unrecoverable (RF-07).
        await encryptor.DestroyHouseholdKeysAsync(householdId, Ct);
        await Assert.ThrowsAnyAsync<Exception>(() =>
            encryptor.DecryptAsync(envelope, "test.table", "secret_enc", rowId, Ct));
    }

    [Fact]
    public async Task Full_identity_lifecycle_setup_totp_recovery_refresh_reuse_and_no_plaintext_secrets()
    {
        var client = _api.CreateClient();

        // RF-01: server-info reports unconfigured owner and synthetic fallback mode.
        var infoBefore = await client.GetFromJsonAsync<JsonElement>("/api/v1/server-info", Ct);
        Assert.Equal("GranaPaCa", infoBefore.GetProperty("app").GetString());
        Assert.False(infoBefore.GetProperty("ownerConfigured").GetBoolean());
        Assert.Equal("synthetic", infoBefore.GetProperty("providerMode").GetString());

        // RF-02: fresh instance rejects any login.
        var loginBeforeSetup = await client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "bia@demo.local",
            password = "SenhaForte!2026#Test",
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, loginBeforeSetup.StatusCode);

        // RF-02: weak password is rejected.
        var weakSetup = await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email = "bia@demo.local",
            displayName = "Bia Demo",
            password = "123",
        }, Ct);
        Assert.Equal(HttpStatusCode.BadRequest, weakSetup.StatusCode);

        // RF-02: create single owner.
        const string ownerPassword = "SenhaForte!2026#Test";
        var setupResp = await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email = "bia@demo.local",
            displayName = "Bia Demo",
            password = ownerPassword,
        }, Ct);
        Assert.Equal(HttpStatusCode.Created, setupResp.StatusCode);

        // Second owner setup is blocked with 409 Conflict.
        var secondSetup = await client.PostAsJsonAsync("/api/v1/auth/setup", new
        {
            email = "outro@demo.local",
            displayName = "Outro",
            password = ownerPassword,
        }, Ct);
        Assert.Equal(HttpStatusCode.Conflict, secondSetup.StatusCode);

        // RF-03: first login requires TOTP enrollment.
        var login1 = await client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "bia@demo.local",
            password = ownerPassword,
            deviceName = "Pixel Demo",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, login1.StatusCode);
        var login1Json = await login1.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("totp_setup_required", login1Json.GetProperty("status").GetString());
        var pendingToken = login1Json.GetProperty("pendingToken").GetString()!;

        // TOTP setup returns manual key and otpauth URI.
        var totpSetupResp = await client.PostAsJsonAsync("/api/v1/auth/totp/setup", new { pendingToken }, Ct);
        Assert.Equal(HttpStatusCode.OK, totpSetupResp.StatusCode);
        var totpSetup = await totpSetupResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var manualKey = totpSetup.GetProperty("manualKey").GetString()!;
        var otpauthUri = totpSetup.GetProperty("otpauthUri").GetString()!;
        Assert.StartsWith("otpauth://totp/GranaPaCa:", otpauthUri);

        // Confirm TOTP with valid RFC 6238 code.
        var validCode = ComputeTotp(manualKey);
        var confirmResp = await client.PostAsJsonAsync("/api/v1/auth/totp/confirm", new
        {
            pendingToken,
            totpCode = validCode,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, confirmResp.StatusCode);
        var confirmJson = await confirmResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        Assert.Equal("authenticated", confirmJson.GetProperty("status").GetString());
        var accessToken1 = confirmJson.GetProperty("accessToken").GetString()!;
        var refreshToken1 = confirmJson.GetProperty("refreshToken").GetString()!;
        var recoveryCodes = confirmJson.GetProperty("recoveryCodes").EnumerateArray()
            .Select(x => x.GetString()!).ToArray();
        Assert.Equal(8, recoveryCodes.Length);

        // RNF-06: verify zero plaintext secrets exist in the database.
        await using (var cmd = _api.Services.GetRequiredService<NpgsqlDataSource>().CreateCommand(
            """
            SELECT o.password_hash, o.totp_secret_enc,
                   (SELECT string_agg(code_hash, ',') FROM identity.recovery_code),
                   (SELECT string_agg(access_token_hash || ':' || refresh_token_hash, ',') FROM identity.session)
            FROM identity.owner o
            LIMIT 1
            """))
        {
            await using var reader = await cmd.ExecuteReaderAsync(Ct);
            Assert.True(await reader.ReadAsync(Ct));
            var passwordHash = reader.GetString(0);
            var totpEnc = (byte[])reader.GetValue(1);
            var recoveryHashes = reader.GetString(2);
            var sessionHashes = reader.GetString(3);

            Assert.StartsWith("$argon2id$", passwordHash);
            Assert.DoesNotContain(ownerPassword, passwordHash);
            Assert.DoesNotContain(manualKey, Encoding.UTF8.GetString(totpEnc));
            Assert.DoesNotContain(recoveryCodes[0], recoveryHashes);
            Assert.DoesNotContain(accessToken1, sessionHashes);
            Assert.DoesNotContain(refreshToken1, sessionHashes);
        }

        // RF-03: wrong password and wrong TOTP return identical error payload.
        var badPwd = await client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "bia@demo.local",
            password = "WrongPassword!2026#",
            totpCode = validCode,
        }, Ct);
        var badTotp = await client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "bia@demo.local",
            password = ownerPassword,
            totpCode = "000000",
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, badPwd.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, badTotp.StatusCode);
        Assert.Equal(
            await badPwd.Content.ReadAsStringAsync(Ct),
            await badTotp.Content.ReadAsStringAsync(Ct));

        // RF-03: recovery code works once and is rejected on reuse.
        var recoveryLogin = await client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "bia@demo.local",
            password = ownerPassword,
            recoveryCode = recoveryCodes[0],
            deviceName = "Backup Laptop",
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, recoveryLogin.StatusCode);

        var recoveryReplay = await client.PostAsJsonAsync("/api/v1/auth/login", new
        {
            email = "bia@demo.local",
            password = ownerPassword,
            recoveryCode = recoveryCodes[0],
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, recoveryReplay.StatusCode);

        // ADR-019: refresh rotates tokens; replaying old refresh revokes entire token family.
        var refreshResp = await client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = refreshToken1,
        }, Ct);
        Assert.Equal(HttpStatusCode.OK, refreshResp.StatusCode);
        var refreshJson = await refreshResp.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var accessToken2 = refreshJson.GetProperty("accessToken").GetString()!;
        var refreshToken2 = refreshJson.GetProperty("refreshToken").GetString()!;
        Assert.NotEqual(accessToken1, accessToken2);
        Assert.NotEqual(refreshToken1, refreshToken2);

        // Authenticated request with new access token works.
        using (var req = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/sessions"))
        {
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken2);
            var sessionsResp = await client.SendAsync(req, Ct);
            Assert.Equal(HttpStatusCode.OK, sessionsResp.StatusCode);
        }

        // Replay old refresh token -> triggers reuse detection and revokes family!
        var replayResp = await client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = refreshToken1,
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, replayResp.StatusCode);

        // Even the newer tokens in that family are now revoked!
        var revokedRefresh = await client.PostAsJsonAsync("/api/v1/auth/refresh", new
        {
            refreshToken = refreshToken2,
        }, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, revokedRefresh.StatusCode);

        using (var req = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/sessions"))
        {
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken2);
            var revokedSession = await client.SendAsync(req, Ct);
            Assert.Equal(HttpStatusCode.Unauthorized, revokedSession.StatusCode);
        }

        // Logout revokes current session on another device.
        var recoveryJson = await recoveryLogin.Content.ReadFromJsonAsync<JsonElement>(Ct);
        var backupToken = recoveryJson.GetProperty("accessToken").GetString()!;
        using (var logoutReq = new HttpRequestMessage(HttpMethod.Post, "/api/v1/auth/logout"))
        {
            logoutReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", backupToken);
            var logoutResp = await client.SendAsync(logoutReq, Ct);
            Assert.Equal(HttpStatusCode.NoContent, logoutResp.StatusCode);
        }

        using (var afterLogout = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/sessions"))
        {
            afterLogout.Headers.Authorization = new AuthenticationHeaderValue("Bearer", backupToken);
            Assert.Equal(HttpStatusCode.Unauthorized, (await client.SendAsync(afterLogout, Ct)).StatusCode);
        }
    }

    internal static string ComputeTotp(string base32Secret)
    {
        var key = Base32Decode(base32Secret);
        var counter = DateTimeOffset.UtcNow.ToUnixTimeSeconds() / 30;
        var counterBytes = BitConverter.GetBytes(counter);
        if (BitConverter.IsLittleEndian)
        {
            Array.Reverse(counterBytes);
        }

        var hash = HMACSHA1.HashData(key, counterBytes);
        var offset = hash[^1] & 0x0F;
        var binary =
            ((hash[offset] & 0x7F) << 24)
            | (hash[offset + 1] << 16)
            | (hash[offset + 2] << 8)
            | hash[offset + 3];
        return (binary % 1_000_000).ToString("D6");
    }

    private static byte[] Base32Decode(string base32)
    {
        const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        var cleaned = base32.Trim().Replace("=", "").Replace(" ", "").ToUpperInvariant();
        var output = new List<byte>(cleaned.Length * 5 / 8);
        int bitBuffer = 0, bitCount = 0;
        foreach (var ch in cleaned)
        {
            var value = alphabet.IndexOf(ch);
            if (value < 0)
            {
                throw new FormatException($"Invalid base32 char '{ch}'.");
            }

            bitBuffer = (bitBuffer << 5) | value;
            bitCount += 5;
            if (bitCount >= 8)
            {
                bitCount -= 8;
                output.Add((byte)((bitBuffer >> bitCount) & 0xFF));
            }
        }

        return [.. output];
    }
}
