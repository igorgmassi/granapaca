using Dapper;
using GranaPaCa.Modules.Identity.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Identity;

internal sealed class SessionService(NpgsqlDataSource dataSource) : IAuthTokenValidator
{
    internal static readonly TimeSpan AccessTokenLifetime = TimeSpan.FromMinutes(15);
    internal static readonly TimeSpan RefreshTokenLifetime = TimeSpan.FromDays(30);

    public async Task<AuthenticatedSession?> ValidateAccessTokenAsync(
        string accessToken,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(accessToken))
        {
            return null;
        }

        var tokenHash = TokenCrypto.HashToken(accessToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<ValidatedSessionRow>(new CommandDefinition(
            """
            SELECT s.owner_id AS OwnerId,
                   s.household_id AS HouseholdId,
                   s.id AS SessionId,
                   o.email AS Email,
                   o.display_name AS DisplayName,
                   s.device_name AS DeviceName
            FROM identity.session s
            INNER JOIN identity.owner o ON o.id = s.owner_id
            WHERE s.access_token_hash = @AccessTokenHash
              AND s.revoked_at IS NULL
              AND s.expires_at > now()
            """,
            new { AccessTokenHash = tokenHash },
            cancellationToken: cancellationToken));

        return row is null
            ? null
            : new AuthenticatedSession(
                row.OwnerId,
                row.HouseholdId,
                row.SessionId,
                row.Email,
                row.DisplayName,
                row.DeviceName);
    }

    internal async Task<IssuedSession> CreateSessionAsync(
        OwnerSummary owner,
        string deviceName,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        return await CreateSessionAsync(connection, transaction: null, owner, deviceName, cancellationToken);
    }

    internal async Task<IssuedSession> CreateSessionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        OwnerSummary owner,
        string deviceName,
        CancellationToken cancellationToken)
    {
        var sessionId = Guid.CreateVersion7();
        var tokenFamilyId = Guid.CreateVersion7();
        var accessToken = TokenCrypto.GenerateOpaqueToken();
        var refreshToken = TokenCrypto.GenerateOpaqueToken();
        var nowUtc = DateTime.UtcNow;
        var accessExpiresAt = nowUtc.Add(AccessTokenLifetime);
        var refreshExpiresAt = nowUtc.Add(RefreshTokenLifetime);

        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO identity.session (
                id,
                owner_id,
                household_id,
                device_name,
                access_token_hash,
                refresh_token_hash,
                token_family_id,
                expires_at,
                refresh_expires_at)
            VALUES (
                @Id,
                @OwnerId,
                @HouseholdId,
                @DeviceName,
                @AccessTokenHash,
                @RefreshTokenHash,
                @TokenFamilyId,
                @ExpiresAt,
                @RefreshExpiresAt)
            """,
            new
            {
                Id = sessionId,
                OwnerId = owner.Id,
                HouseholdId = owner.HouseholdId,
                DeviceName = deviceName,
                AccessTokenHash = TokenCrypto.HashToken(accessToken),
                RefreshTokenHash = TokenCrypto.HashToken(refreshToken),
                TokenFamilyId = tokenFamilyId,
                ExpiresAt = accessExpiresAt,
                RefreshExpiresAt = refreshExpiresAt,
            },
            transaction: transaction,
            cancellationToken: cancellationToken));

        return new IssuedSession(
            sessionId,
            accessToken,
            refreshToken,
            new DateTimeOffset(accessExpiresAt, TimeSpan.Zero),
            owner);
    }

    internal async Task<IssuedSession?> RefreshAsync(
        string? refreshToken,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(refreshToken))
        {
            return null;
        }

        var refreshTokenHash = TokenCrypto.HashToken(refreshToken);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        if (await HandleReuseIfDetectedAsync(connection, transaction, refreshTokenHash, cancellationToken))
        {
            await transaction.CommitAsync(cancellationToken);
            return null;
        }

        var session = await connection.QuerySingleOrDefaultAsync<RefreshSessionRow>(new CommandDefinition(
            """
            SELECT s.id AS Id,
                   s.owner_id AS OwnerId,
                   s.household_id AS HouseholdId,
                   s.token_family_id AS TokenFamilyId,
                   s.refresh_expires_at AS RefreshExpiresAt,
                   s.revoked_at AS RevokedAt,
                   o.email AS Email,
                   o.display_name AS DisplayName
            FROM identity.session s
            INNER JOIN identity.owner o ON o.id = s.owner_id
            WHERE s.refresh_token_hash = @RefreshTokenHash
            FOR UPDATE OF s
            """,
            new { RefreshTokenHash = refreshTokenHash },
            transaction: transaction,
            cancellationToken: cancellationToken));

        if (session is null)
        {
            // Re-check in case a concurrent refresh rotated this token while we waited for the row lock.
            if (await HandleReuseIfDetectedAsync(connection, transaction, refreshTokenHash, cancellationToken))
            {
                await transaction.CommitAsync(cancellationToken);
            }

            return null;
        }

        var nowUtc = DateTime.UtcNow;
        if (session.RevokedAt is not null || DateTime.SpecifyKind(session.RefreshExpiresAt, DateTimeKind.Utc) <= nowUtc)
        {
            return null;
        }

        var newAccessToken = TokenCrypto.GenerateOpaqueToken();
        var newRefreshToken = TokenCrypto.GenerateOpaqueToken();
        var newAccessExpiresAt = nowUtc.Add(AccessTokenLifetime);
        var newRefreshExpiresAt = nowUtc.Add(RefreshTokenLifetime);

        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO identity.used_refresh_token (token_hash, session_id, token_family_id)
            VALUES (@TokenHash, @SessionId, @TokenFamilyId)
            """,
            new
            {
                TokenHash = refreshTokenHash,
                SessionId = session.Id,
                TokenFamilyId = session.TokenFamilyId,
            },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE identity.session
            SET access_token_hash = @NewAccessTokenHash,
                refresh_token_hash = @NewRefreshTokenHash,
                expires_at = @NewExpiresAt,
                refresh_expires_at = @NewRefreshExpiresAt
            WHERE id = @SessionId
            """,
            new
            {
                SessionId = session.Id,
                NewAccessTokenHash = TokenCrypto.HashToken(newAccessToken),
                NewRefreshTokenHash = TokenCrypto.HashToken(newRefreshToken),
                NewExpiresAt = newAccessExpiresAt,
                NewRefreshExpiresAt = newRefreshExpiresAt,
            },
            transaction: transaction,
            cancellationToken: cancellationToken));

        await transaction.CommitAsync(cancellationToken);

        return new IssuedSession(
            session.Id,
            newAccessToken,
            newRefreshToken,
            new DateTimeOffset(newAccessExpiresAt, TimeSpan.Zero),
            new OwnerSummary(session.OwnerId, session.HouseholdId, session.Email, session.DisplayName));
    }

    internal async Task<bool> RevokeSessionAsync(
        Guid ownerId,
        Guid sessionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var affected = await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE identity.session
            SET revoked_at = COALESCE(revoked_at, now())
            WHERE id = @SessionId
              AND owner_id = @OwnerId
            """,
            new { SessionId = sessionId, OwnerId = ownerId },
            cancellationToken: cancellationToken));

        return affected > 0;
    }

    internal async Task<IReadOnlyList<SessionListItem>> ListActiveSessionsAsync(
        Guid ownerId,
        Guid currentSessionId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<ActiveSessionRow>(new CommandDefinition(
            """
            SELECT id AS Id,
                   device_name AS DeviceName,
                   created_at AS CreatedAt,
                   expires_at AS ExpiresAt
            FROM identity.session
            WHERE owner_id = @OwnerId
              AND revoked_at IS NULL
              AND refresh_expires_at > now()
            ORDER BY created_at DESC
            """,
            new { OwnerId = ownerId },
            cancellationToken: cancellationToken));

        return rows
            .Select(row => new SessionListItem(
                row.Id,
                row.DeviceName,
                new DateTimeOffset(DateTime.SpecifyKind(row.CreatedAt, DateTimeKind.Utc)),
                new DateTimeOffset(DateTime.SpecifyKind(row.ExpiresAt, DateTimeKind.Utc)),
                row.Id == currentSessionId))
            .ToArray();
    }

    private static async Task<bool> HandleReuseIfDetectedAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string refreshTokenHash,
        CancellationToken cancellationToken)
    {
        var reusedFamilyId = await connection.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
            """
            SELECT token_family_id
            FROM identity.used_refresh_token
            WHERE token_hash = @TokenHash
            """,
            new { TokenHash = refreshTokenHash },
            transaction: transaction,
            cancellationToken: cancellationToken));

        if (reusedFamilyId is null)
        {
            return false;
        }

        await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE identity.session
            SET revoked_at = now()
            WHERE token_family_id = @TokenFamilyId
              AND revoked_at IS NULL
            """,
            new { TokenFamilyId = reusedFamilyId.Value },
            transaction: transaction,
            cancellationToken: cancellationToken));

        return true;
    }

    private sealed class ValidatedSessionRow
    {
        public Guid OwnerId { get; init; }
        public Guid HouseholdId { get; init; }
        public Guid SessionId { get; init; }
        public string Email { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
        public string DeviceName { get; init; } = string.Empty;
    }

    private sealed class RefreshSessionRow
    {
        public Guid Id { get; init; }
        public Guid OwnerId { get; init; }
        public Guid HouseholdId { get; init; }
        public Guid TokenFamilyId { get; init; }
        public DateTime RefreshExpiresAt { get; init; }
        public DateTime? RevokedAt { get; init; }
        public string Email { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
    }

    private sealed class ActiveSessionRow
    {
        public Guid Id { get; init; }
        public string DeviceName { get; init; } = string.Empty;
        public DateTime CreatedAt { get; init; }
        public DateTime ExpiresAt { get; init; }
    }
}

internal sealed record IssuedSession(
    Guid SessionId,
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    OwnerSummary Owner);
