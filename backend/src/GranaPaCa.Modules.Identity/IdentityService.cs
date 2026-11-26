using System.Net.Mail;
using System.Security.Cryptography;
using Dapper;
using GranaPaCa.Modules.Identity.Contracts;
using GranaPaCa.Modules.Keyring.Contracts;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Npgsql;

namespace GranaPaCa.Modules.Identity;

internal sealed class IdentityService(
    NpgsqlDataSource dataSource,
    IEnvelopeEncryptor envelopeEncryptor,
    SessionService sessionService,
    IConfiguration configuration) : IIdentityPurgeService
{
    private const string AppName = "GranaPaCa";
    private const string AppVersion = "0.2.0";
    private const int CurrentApiVersion = 1;
    private const string DefaultTimezone = "America/Sao_Paulo";
    private const string DefaultDeviceName = "Dispositivo desconhecido";
    private const string TotpPurpose = "identity.totp";
    private const string OwnerTable = "identity.owner";
    private const string TotpSecretColumn = "totp_secret_enc";
    private const long SetupAdvisoryLockKey = 7284910321L;
    private const int MaxFailedAttemptsWindow = 5;
    private const int RateLimitWindowMinutes = 15;
    private const int RecoveryCodeCount = 8;

    private static readonly TimeSpan PendingTotpLifetime = TimeSpan.FromMinutes(15);

    private static readonly ErrorResponse InvalidCredentialsError = new(
        "invalid_credentials",
        "E-mail, senha ou código inválidos.");

    private static readonly ErrorResponse RateLimitedError = new(
        "rate_limited",
        "Muitas tentativas de acesso. Tente novamente em alguns minutos.");

    internal async Task<ServerInfoResponse> GetServerInfoAsync(CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var ownerConfigured = await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
            "SELECT EXISTS (SELECT 1 FROM identity.owner)",
            cancellationToken: cancellationToken));

        return new ServerInfoResponse(
            AppName,
            AppVersion,
            CurrentApiVersion,
            ownerConfigured,
            ResolveProviderMode());
    }

    internal async Task<IResult> SetupOwnerAsync(
        SetupRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null)
        {
            return Results.BadRequest(new ErrorResponse("invalid_request", "Corpo da requisição inválido."));
        }

        var email = NormalizeEmail(request.Email);
        if (!IsValidEmail(email))
        {
            return Results.BadRequest(new ErrorResponse("invalid_email", "Informe um endereço de e-mail válido."));
        }

        var displayName = request.DisplayName?.Trim();
        if (string.IsNullOrEmpty(displayName) || displayName.Length > 120)
        {
            return Results.BadRequest(new ErrorResponse("invalid_display_name", "Informe um nome de exibição válido."));
        }

        var (isStrong, passwordReason) = PasswordPolicy.Validate(request.Password);
        if (!isStrong)
        {
            return Results.BadRequest(new ErrorResponse("weak_password", passwordReason!));
        }

        var householdName = string.IsNullOrWhiteSpace(request.HouseholdName)
            ? $"Casa de {displayName}"
            : request.HouseholdName.Trim();
        if (householdName.Length > 120)
        {
            householdName = householdName[..120];
        }

        var timezone = string.IsNullOrWhiteSpace(request.Timezone)
            ? DefaultTimezone
            : request.Timezone.Trim();
        if (!TimeZoneInfo.TryFindSystemTimeZoneById(timezone, out _))
        {
            return Results.BadRequest(new ErrorResponse("invalid_timezone", "Fuso horário inválido."));
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var alreadyConfigured = await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
            "SELECT EXISTS (SELECT 1 FROM identity.owner)",
            cancellationToken: cancellationToken));
        if (alreadyConfigured)
        {
            return Results.Conflict(new ErrorResponse(
                "owner_already_configured",
                "Esta instância já possui um proprietário configurado."));
        }

        var passwordHash = PasswordHasher.Hash(request.Password!);

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await connection.ExecuteAsync(new CommandDefinition(
            "SELECT pg_advisory_xact_lock(@LockKey)",
            new { LockKey = SetupAdvisoryLockKey },
            transaction: transaction,
            cancellationToken: cancellationToken));

        alreadyConfigured = await connection.ExecuteScalarAsync<bool>(new CommandDefinition(
            "SELECT EXISTS (SELECT 1 FROM identity.owner)",
            transaction: transaction,
            cancellationToken: cancellationToken));
        if (alreadyConfigured)
        {
            return Results.Conflict(new ErrorResponse(
                "owner_already_configured",
                "Esta instância já possui um proprietário configurado."));
        }

        var householdId = Guid.CreateVersion7();
        var ownerId = Guid.CreateVersion7();

        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO identity.household (id, name, timezone)
            VALUES (@Id, @Name, @Timezone)
            """,
            new { Id = householdId, Name = householdName, Timezone = timezone },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO identity.owner (id, household_id, email, display_name, password_hash, totp_enabled)
            VALUES (@Id, @HouseholdId, @Email, @DisplayName, @PasswordHash, false)
            """,
            new
            {
                Id = ownerId,
                HouseholdId = householdId,
                Email = email,
                DisplayName = displayName,
                PasswordHash = passwordHash,
            },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await transaction.CommitAsync(cancellationToken);

        return Results.Created(
            "/api/v1/server-info",
            new SetupResponse(ownerId, householdId, email, displayName));
    }

    internal async Task<IResult> LoginAsync(
        LoginRequest? request,
        string clientIp,
        CancellationToken cancellationToken)
    {
        var email = NormalizeEmail(request?.Email);
        var clientKey = BuildClientKey(clientIp, email);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        if (await IsRateLimitedAsync(connection, clientKey, cancellationToken))
        {
            return TooManyRequestsResult();
        }

        if (request is null || string.IsNullOrEmpty(email) || string.IsNullOrEmpty(request.Password))
        {
            PasswordHasher.VerifyDummy(request?.Password);
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return UnauthorizedCredentialsResult();
        }

        var owner = await connection.QuerySingleOrDefaultAsync<OwnerRow>(new CommandDefinition(
            """
            SELECT id AS Id,
                   household_id AS HouseholdId,
                   email AS Email,
                   display_name AS DisplayName,
                   password_hash AS PasswordHash,
                   totp_secret_enc AS TotpSecretEnc,
                   totp_enabled AS TotpEnabled
            FROM identity.owner
            WHERE email = @Email
            """,
            new { Email = email },
            cancellationToken: cancellationToken));

        if (owner is null)
        {
            PasswordHasher.VerifyDummy(request.Password);
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return UnauthorizedCredentialsResult();
        }

        if (!PasswordHasher.Verify(request.Password, owner.PasswordHash))
        {
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return UnauthorizedCredentialsResult();
        }

        var deviceName = NormalizeDeviceName(request.DeviceName);

        if (!owner.TotpEnabled)
        {
            var pendingToken = TokenCrypto.GenerateOpaqueToken();
            var pendingId = Guid.CreateVersion7();
            var expiresAt = DateTime.UtcNow.Add(PendingTotpLifetime);

            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO identity.pending_totp_session (id, owner_id, token_hash, device_name, expires_at)
                VALUES (@Id, @OwnerId, @TokenHash, @DeviceName, @ExpiresAt)
                """,
                new
                {
                    Id = pendingId,
                    OwnerId = owner.Id,
                    TokenHash = TokenCrypto.HashToken(pendingToken),
                    DeviceName = deviceName,
                    ExpiresAt = expiresAt,
                },
                cancellationToken: cancellationToken));

            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: true, cancellationToken);

            return Results.Ok(new PendingTotpLoginResponse("totp_setup_required", pendingToken));
        }

        var secondFactorValid = await VerifySecondFactorAsync(
            connection,
            owner,
            request.TotpCode,
            request.RecoveryCode,
            cancellationToken);

        if (!secondFactorValid)
        {
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return UnauthorizedCredentialsResult();
        }

        var ownerSummary = new OwnerSummary(owner.Id, owner.HouseholdId, owner.Email, owner.DisplayName);
        var issued = await sessionService.CreateSessionAsync(
            connection,
            transaction: null,
            ownerSummary,
            deviceName,
            cancellationToken);

        await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: true, cancellationToken);

        return Results.Ok(new AuthenticatedLoginResponse(
            "authenticated",
            issued.AccessToken,
            issued.RefreshToken,
            issued.ExpiresAt,
            issued.SessionId,
            issued.Owner));
    }

    internal async Task<IResult> BeginTotpSetupAsync(
        TotpSetupRequest? request,
        CancellationToken cancellationToken)
    {
        if (request is null || string.IsNullOrWhiteSpace(request.PendingToken))
        {
            return UnauthorizedCredentialsResult();
        }

        var tokenHash = TokenCrypto.HashToken(request.PendingToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var pending = await QueryPendingSessionAsync(connection, tokenHash, cancellationToken);
        if (pending is null || pending.TotpEnabled)
        {
            return UnauthorizedCredentialsResult();
        }

        var secret = TotpService.GenerateSecret();
        try
        {
            var manualKey = TotpService.EncodeBase32(secret);
            var otpauthUri = TotpService.BuildOtpAuthUri(pending.Email, manualKey);
            var encryptedSecret = await envelopeEncryptor.EncryptAsync(
                pending.HouseholdId,
                TotpPurpose,
                secret,
                OwnerTable,
                TotpSecretColumn,
                pending.OwnerId,
                cancellationToken);

            var updated = await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE identity.owner
                SET totp_secret_enc = @EncryptedSecret
                WHERE id = @OwnerId
                  AND totp_enabled = false
                """,
                new { OwnerId = pending.OwnerId, EncryptedSecret = encryptedSecret },
                cancellationToken: cancellationToken));

            if (updated == 0)
            {
                return UnauthorizedCredentialsResult();
            }

            return Results.Ok(new TotpSetupResponse(manualKey, otpauthUri));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
        }
    }

    internal async Task<IResult> ConfirmTotpAsync(
        TotpConfirmRequest? request,
        string clientIp,
        CancellationToken cancellationToken)
    {
        if (request is null ||
            string.IsNullOrWhiteSpace(request.PendingToken) ||
            string.IsNullOrWhiteSpace(request.TotpCode))
        {
            return UnauthorizedCredentialsResult();
        }

        var tokenHash = TokenCrypto.HashToken(request.PendingToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var pending = await QueryPendingSessionAsync(connection, tokenHash, cancellationToken);
        if (pending is null || pending.TotpEnabled || pending.TotpSecretEnc is null)
        {
            return UnauthorizedCredentialsResult();
        }

        var clientKey = BuildClientKey(clientIp, pending.Email);
        if (await IsRateLimitedAsync(connection, clientKey, cancellationToken))
        {
            return TooManyRequestsResult();
        }

        bool validCode;
        var decryptedSecret = await envelopeEncryptor.DecryptAsync(
            pending.TotpSecretEnc,
            OwnerTable,
            TotpSecretColumn,
            pending.OwnerId,
            cancellationToken);
        try
        {
            validCode = TotpService.VerifyCode(decryptedSecret, request.TotpCode);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(decryptedSecret);
        }

        if (!validCode)
        {
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return UnauthorizedCredentialsResult();
        }

        var recoveryCodes = TokenCrypto.GenerateRecoveryCodes(RecoveryCodeCount);

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var enabled = await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE identity.owner
            SET totp_enabled = true
            WHERE id = @OwnerId
              AND totp_enabled = false
            """,
            new { OwnerId = pending.OwnerId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        if (enabled == 0)
        {
            return UnauthorizedCredentialsResult();
        }

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM identity.recovery_code WHERE owner_id = @OwnerId",
            new { OwnerId = pending.OwnerId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        foreach (var code in recoveryCodes)
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO identity.recovery_code (id, owner_id, code_hash)
                VALUES (@Id, @OwnerId, @CodeHash)
                """,
                new
                {
                    Id = Guid.CreateVersion7(),
                    OwnerId = pending.OwnerId,
                    CodeHash = TokenCrypto.HashRecoveryCode(code),
                },
                transaction: transaction,
                cancellationToken: cancellationToken));
        }

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM identity.pending_totp_session WHERE owner_id = @OwnerId",
            new { OwnerId = pending.OwnerId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        var ownerSummary = new OwnerSummary(pending.OwnerId, pending.HouseholdId, pending.Email, pending.DisplayName);
        var issued = await sessionService.CreateSessionAsync(
            connection,
            transaction,
            ownerSummary,
            pending.DeviceName,
            cancellationToken);

        await RecordAuthAttemptAsync(connection, transaction, clientKey, succeeded: true, cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        return Results.Ok(new TotpConfirmResponse(
            "authenticated",
            issued.AccessToken,
            issued.RefreshToken,
            issued.ExpiresAt,
            issued.SessionId,
            issued.Owner,
            recoveryCodes));
    }

    internal async Task<IResult> RefreshAsync(
        RefreshRequest? request,
        CancellationToken cancellationToken)
    {
        var issued = await sessionService.RefreshAsync(request?.RefreshToken, cancellationToken);
        if (issued is null)
        {
            return Results.Json(
                new ErrorResponse("invalid_refresh_token", "Token de atualização inválido ou revogado."),
                statusCode: StatusCodes.Status401Unauthorized);
        }

        return Results.Ok(new AuthenticatedLoginResponse(
            "authenticated",
            issued.AccessToken,
            issued.RefreshToken,
            issued.ExpiresAt,
            issued.SessionId,
            issued.Owner));
    }

    public async Task<OwnerCredentialVerificationStatus> VerifyOwnerCredentialsAsync(
        Guid ownerId,
        Guid householdId,
        string password,
        string totpCode,
        string clientIp,
        CancellationToken cancellationToken = default)
    {
        if (ownerId == Guid.Empty || householdId == Guid.Empty)
        {
            PasswordHasher.VerifyDummy(password);
            return OwnerCredentialVerificationStatus.InvalidCredentials;
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var owner = await connection.QuerySingleOrDefaultAsync<OwnerRow>(new CommandDefinition(
            """
            SELECT id AS Id,
                   household_id AS HouseholdId,
                   email AS Email,
                   display_name AS DisplayName,
                   password_hash AS PasswordHash,
                   totp_secret_enc AS TotpSecretEnc,
                   totp_enabled AS TotpEnabled
            FROM identity.owner
            WHERE id = @OwnerId
              AND household_id = @HouseholdId
            """,
            new { OwnerId = ownerId, HouseholdId = householdId },
            cancellationToken: cancellationToken));

        var normalizedClientIp = string.IsNullOrWhiteSpace(clientIp) ? "local" : clientIp.Trim();
        var clientKey = owner is not null
            ? BuildClientKey(normalizedClientIp, owner.Email)
            : BuildClientKey(normalizedClientIp, ownerId.ToString("D"));

        if (await IsRateLimitedAsync(connection, clientKey, cancellationToken))
        {
            return OwnerCredentialVerificationStatus.RateLimited;
        }

        if (owner is null || string.IsNullOrEmpty(password) || string.IsNullOrWhiteSpace(totpCode))
        {
            PasswordHasher.VerifyDummy(password);
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return OwnerCredentialVerificationStatus.InvalidCredentials;
        }

        if (!PasswordHasher.Verify(password, owner.PasswordHash))
        {
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return OwnerCredentialVerificationStatus.InvalidCredentials;
        }

        if (!owner.TotpEnabled || owner.TotpSecretEnc is null)
        {
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return OwnerCredentialVerificationStatus.InvalidCredentials;
        }

        bool validCode;
        var decryptedSecret = await envelopeEncryptor.DecryptAsync(
            owner.TotpSecretEnc,
            OwnerTable,
            TotpSecretColumn,
            owner.Id,
            cancellationToken);
        try
        {
            validCode = TotpService.VerifyCode(decryptedSecret, totpCode);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(decryptedSecret);
        }

        if (!validCode)
        {
            await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: false, cancellationToken);
            return OwnerCredentialVerificationStatus.InvalidCredentials;
        }

        await RecordAuthAttemptAsync(connection, transaction: null, clientKey, succeeded: true, cancellationToken);
        return OwnerCredentialVerificationStatus.Valid;
    }

    public async Task PurgeHouseholdAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        // Remove auth attempt entries linked to purged household owners before cascading household delete.
        await connection.ExecuteAsync(new CommandDefinition(
            """
            DELETE FROM identity.auth_attempt a
            USING identity.owner o
            WHERE o.household_id = @HouseholdId
              AND right(a.client_key, length(o.email) + 1) = ':' || o.email
            """,
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM identity.household WHERE id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));
    }

    private async Task<bool> VerifySecondFactorAsync(
        NpgsqlConnection connection,
        OwnerRow owner,
        string? totpCode,
        string? recoveryCode,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(totpCode))
        {
            if (owner.TotpSecretEnc is null)
            {
                return false;
            }

            var decryptedSecret = await envelopeEncryptor.DecryptAsync(
                owner.TotpSecretEnc,
                OwnerTable,
                TotpSecretColumn,
                owner.Id,
                cancellationToken);
            try
            {
                return TotpService.VerifyCode(decryptedSecret, totpCode);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(decryptedSecret);
            }
        }

        if (!string.IsNullOrWhiteSpace(recoveryCode))
        {
            var normalized = TokenCrypto.NormalizeRecoveryCode(recoveryCode);
            if (string.IsNullOrEmpty(normalized))
            {
                return false;
            }

            var codeHash = TokenCrypto.HashToken(normalized);
            var consumedId = await connection.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
                """
                UPDATE identity.recovery_code
                SET used_at = now()
                WHERE id = (
                    SELECT id
                    FROM identity.recovery_code
                    WHERE owner_id = @OwnerId
                      AND code_hash = @CodeHash
                      AND used_at IS NULL
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED
                )
                RETURNING id
                """,
                new { OwnerId = owner.Id, CodeHash = codeHash },
                cancellationToken: cancellationToken));

            return consumedId is not null;
        }

        return false;
    }

    private static Task<PendingSessionRow?> QueryPendingSessionAsync(
        NpgsqlConnection connection,
        string tokenHash,
        CancellationToken cancellationToken) =>
        connection.QuerySingleOrDefaultAsync<PendingSessionRow>(new CommandDefinition(
            """
            SELECT p.id AS PendingSessionId,
                   p.owner_id AS OwnerId,
                   p.device_name AS DeviceName,
                   o.household_id AS HouseholdId,
                   o.email AS Email,
                   o.display_name AS DisplayName,
                   o.totp_secret_enc AS TotpSecretEnc,
                   o.totp_enabled AS TotpEnabled
            FROM identity.pending_totp_session p
            INNER JOIN identity.owner o ON o.id = p.owner_id
            WHERE p.token_hash = @TokenHash
              AND p.expires_at > now()
            """,
            new { TokenHash = tokenHash },
            cancellationToken: cancellationToken));

    private static async Task<bool> IsRateLimitedAsync(
        NpgsqlConnection connection,
        string clientKey,
        CancellationToken cancellationToken)
    {
        var windowStart = DateTime.UtcNow.AddMinutes(-RateLimitWindowMinutes);
        var failedCount = await connection.ExecuteScalarAsync<int>(new CommandDefinition(
            """
            SELECT COUNT(*)
            FROM identity.auth_attempt
            WHERE client_key = @ClientKey
              AND succeeded = false
              AND attempted_at >= @WindowStart
            """,
            new { ClientKey = clientKey, WindowStart = windowStart },
            cancellationToken: cancellationToken));

        return failedCount >= MaxFailedAttemptsWindow;
    }

    private static Task RecordAuthAttemptAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        string clientKey,
        bool succeeded,
        CancellationToken cancellationToken) =>
        connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO identity.auth_attempt (id, client_key, succeeded)
            VALUES (@Id, @ClientKey, @Succeeded)
            """,
            new
            {
                Id = Guid.CreateVersion7(),
                ClientKey = clientKey,
                Succeeded = succeeded,
            },
            transaction: transaction,
            cancellationToken: cancellationToken));

    private string ResolveProviderMode()
    {
        var explicitMode = configuration["Banking:ProviderMode"]?.Trim().ToLowerInvariant();
        if (explicitMode is "pluggy" or "synthetic")
        {
            return explicitMode;
        }

        var clientId = configuration["PLUGGY_CLIENT_ID"] ?? configuration["Pluggy:ClientId"];
        var clientSecret = configuration["PLUGGY_CLIENT_SECRET"] ?? configuration["Pluggy:ClientSecret"];

        return !string.IsNullOrWhiteSpace(clientId) && !string.IsNullOrWhiteSpace(clientSecret)
            ? "pluggy"
            : "synthetic";
    }

    private static IResult UnauthorizedCredentialsResult() =>
        Results.Json(InvalidCredentialsError, statusCode: StatusCodes.Status401Unauthorized);

    private static IResult TooManyRequestsResult() =>
        Results.Json(RateLimitedError, statusCode: StatusCodes.Status429TooManyRequests);

    private static string BuildClientKey(string clientIp, string normalizedEmail) =>
        $"{clientIp}:{normalizedEmail}";

    private static string NormalizeEmail(string? email) =>
        string.IsNullOrWhiteSpace(email) ? string.Empty : email.Trim().ToLowerInvariant();

    private static bool IsValidEmail(string normalizedEmail)
    {
        if (string.IsNullOrEmpty(normalizedEmail) || normalizedEmail.Length > 254)
        {
            return false;
        }

        foreach (var ch in normalizedEmail)
        {
            if (char.IsWhiteSpace(ch))
            {
                return false;
            }
        }

        if (!MailAddress.TryCreate(normalizedEmail, out var address))
        {
            return false;
        }

        return string.Equals(address.Address, normalizedEmail, StringComparison.Ordinal)
            && address.Host.Contains('.')
            && !address.Host.StartsWith('.')
            && !address.Host.EndsWith('.');
    }

    private static string NormalizeDeviceName(string? deviceName)
    {
        if (string.IsNullOrWhiteSpace(deviceName))
        {
            return DefaultDeviceName;
        }

        var trimmed = deviceName.Trim();
        return trimmed.Length <= 120 ? trimmed : trimmed[..120];
    }

    private sealed class OwnerRow
    {
        public Guid Id { get; init; }
        public Guid HouseholdId { get; init; }
        public string Email { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
        public string PasswordHash { get; init; } = string.Empty;
        public byte[]? TotpSecretEnc { get; init; }
        public bool TotpEnabled { get; init; }
    }

    private sealed class PendingSessionRow
    {
        public Guid PendingSessionId { get; init; }
        public Guid OwnerId { get; init; }
        public string DeviceName { get; init; } = string.Empty;
        public Guid HouseholdId { get; init; }
        public string Email { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
        public byte[]? TotpSecretEnc { get; init; }
        public bool TotpEnabled { get; init; }
    }
}
