using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using Dapper;
using GranaPaCa.Modules.Keyring.Contracts;
using Npgsql;

namespace GranaPaCa.Modules.Keyring;

internal sealed class EnvelopeEncryptor(
    NpgsqlDataSource dataSource,
    MasterKeyRing masterKeyRing) : IEnvelopeEncryptor
{
    private const byte FormatVersion = 0x01;
    private const int DekLengthBytes = 32;
    private const int DekIdLengthBytes = 16;
    private const int NonceLengthBytes = 12;
    private const int TagLengthBytes = 16;

    // Envelope layout: [version(1)][dekId(16)][nonce(12)][tag(16)][ciphertext(N)]
    private const int EnvelopeDekIdOffset = 1;
    private const int EnvelopeNonceOffset = EnvelopeDekIdOffset + DekIdLengthBytes; // 17
    private const int EnvelopeTagOffset = EnvelopeNonceOffset + NonceLengthBytes;   // 29
    private const int EnvelopeCiphertextOffset = EnvelopeTagOffset + TagLengthBytes; // 45

    // Wrapped DEK layout: [version(1)][nonce(12)][tag(16)][wrapped(32)]
    private const int WrapNonceOffset = 1;
    private const int WrapTagOffset = WrapNonceOffset + NonceLengthBytes;       // 13
    private const int WrapCiphertextOffset = WrapTagOffset + TagLengthBytes;    // 29
    private const int WrappedDekTotalLength = WrapCiphertextOffset + DekLengthBytes; // 61

    private readonly ConcurrentDictionary<(Guid HouseholdId, string Purpose), CachedDek> _activeDekByScope = new();
    private readonly ConcurrentDictionary<Guid, CachedDek> _dekById = new();

    public async Task<byte[]> EncryptAsync(
        Guid householdId,
        string purpose,
        ReadOnlyMemory<byte> plaintext,
        string table,
        string column,
        Guid rowId,
        CancellationToken cancellationToken = default)
    {
        ValidateScope(householdId, purpose);
        ValidateAadInputs(table, column, rowId);

        var dek = await GetOrCreateActiveDekAsync(householdId, purpose, cancellationToken);
        var aad = BuildDataAad(table, column, rowId);

        var envelope = new byte[EnvelopeCiphertextOffset + plaintext.Length];
        envelope[0] = FormatVersion;
        dek.Id.TryWriteBytes(envelope.AsSpan(EnvelopeDekIdOffset, DekIdLengthBytes));

        var nonce = envelope.AsSpan(EnvelopeNonceOffset, NonceLengthBytes);
        RandomNumberGenerator.Fill(nonce);

        var tag = envelope.AsSpan(EnvelopeTagOffset, TagLengthBytes);
        var ciphertext = envelope.AsSpan(EnvelopeCiphertextOffset, plaintext.Length);

        using var aes = new AesGcm(dek.Key, TagLengthBytes);
        aes.Encrypt(nonce, plaintext.Span, ciphertext, tag, aad);

        return envelope;
    }

    public async Task<byte[]> DecryptAsync(
        byte[] envelope,
        string table,
        string column,
        Guid rowId,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(envelope);
        ValidateAadInputs(table, column, rowId);

        if (envelope.Length < EnvelopeCiphertextOffset)
        {
            throw new CryptographicException("Encrypted envelope is truncated.");
        }

        if (envelope[0] != FormatVersion)
        {
            throw new CryptographicException($"Unsupported envelope format version '0x{envelope[0]:X2}'.");
        }

        var dekId = new Guid(envelope.AsSpan(EnvelopeDekIdOffset, DekIdLengthBytes));
        var dek = await GetDekByIdAsync(dekId, cancellationToken);

        var nonce = envelope.AsSpan(EnvelopeNonceOffset, NonceLengthBytes);
        var tag = envelope.AsSpan(EnvelopeTagOffset, TagLengthBytes);
        var ciphertext = envelope.AsSpan(EnvelopeCiphertextOffset);
        var plaintext = new byte[ciphertext.Length];
        var aad = BuildDataAad(table, column, rowId);

        using var aes = new AesGcm(dek.Key, TagLengthBytes);
        aes.Decrypt(nonce, ciphertext, tag, plaintext, aad);

        return plaintext;
    }

    public async Task RotateDataKeyAsync(
        Guid householdId,
        string purpose,
        CancellationToken cancellationToken = default)
    {
        ValidateScope(householdId, purpose);

        var newDekId = Guid.CreateVersion7();
        var rawDek = RandomNumberGenerator.GetBytes(DekLengthBytes);
        var masterKeyId = masterKeyRing.PrimaryKeyId;
        var wrappedKey = WrapDek(
            rawDek,
            masterKeyRing.GetKey(masterKeyId),
            newDekId,
            householdId,
            purpose);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            await connection.ExecuteAsync(new CommandDefinition(
                """
                UPDATE keyring.data_key
                SET retired_at = now()
                WHERE household_id = @HouseholdId
                  AND purpose = @Purpose
                  AND retired_at IS NULL
                """,
                new { HouseholdId = householdId, Purpose = purpose },
                transaction: transaction,
                cancellationToken: cancellationToken));

            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO keyring.data_key (id, household_id, purpose, master_key_id, wrapped_key)
                VALUES (@Id, @HouseholdId, @Purpose, @MasterKeyId, @WrappedKey)
                """,
                new
                {
                    Id = newDekId,
                    HouseholdId = householdId,
                    Purpose = purpose,
                    MasterKeyId = masterKeyId,
                    WrappedKey = wrappedKey,
                },
                transaction: transaction,
                cancellationToken: cancellationToken));

            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            CryptographicOperations.ZeroMemory(rawDek);
            throw;
        }

        var cached = new CachedDek(newDekId, householdId, rawDek);
        _dekById[newDekId] = cached;
        _activeDekByScope[(householdId, purpose)] = cached;
    }

    public async Task RewrapAllDataKeysAsync(CancellationToken cancellationToken = default)
    {
        var primaryKeyId = masterKeyRing.PrimaryKeyId;
        var primaryKey = masterKeyRing.GetKey(primaryKeyId);

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var rows = (await connection.QueryAsync<DataKeyRow>(new CommandDefinition(
            """
            SELECT id AS Id,
                   household_id AS HouseholdId,
                   purpose AS Purpose,
                   master_key_id AS MasterKeyId,
                   wrapped_key AS WrappedKey
            FROM keyring.data_key
            FOR UPDATE
            """,
            transaction: transaction,
            cancellationToken: cancellationToken))).ToList();

        foreach (var row in rows)
        {
            var rawDek = UnwrapDek(row);
            try
            {
                var rewrapped = WrapDek(rawDek, primaryKey, row.Id, row.HouseholdId, row.Purpose);
                await connection.ExecuteAsync(new CommandDefinition(
                    """
                    UPDATE keyring.data_key
                    SET master_key_id = @MasterKeyId,
                        wrapped_key = @WrappedKey
                    WHERE id = @Id
                    """,
                    new
                    {
                        Id = row.Id,
                        MasterKeyId = primaryKeyId,
                        WrappedKey = rewrapped,
                    },
                    transaction: transaction,
                    cancellationToken: cancellationToken));
            }
            finally
            {
                CryptographicOperations.ZeroMemory(rawDek);
            }
        }

        await transaction.CommitAsync(cancellationToken);

        _activeDekByScope.Clear();
        _dekById.Clear();
    }

    public async Task DestroyHouseholdKeysAsync(
        Guid householdId,
        CancellationToken cancellationToken = default)
    {
        if (householdId == Guid.Empty)
        {
            throw new ArgumentException("Household ID must not be empty.", nameof(householdId));
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM keyring.data_key WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            cancellationToken: cancellationToken));

        EvictHouseholdKeysFromCache(householdId);
    }

    public async Task DestroyHouseholdKeysAsync(
        Guid householdId,
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken = default)
    {
        if (householdId == Guid.Empty)
        {
            throw new ArgumentException("Household ID must not be empty.", nameof(householdId));
        }

        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);

        await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM keyring.data_key WHERE household_id = @HouseholdId",
            new { HouseholdId = householdId },
            transaction: transaction,
            cancellationToken: cancellationToken));
    }

    public void EvictHouseholdKeysFromCache(Guid householdId)
    {
        foreach (var entry in _activeDekByScope)
        {
            if (entry.Key.HouseholdId == householdId)
            {
                _activeDekByScope.TryRemove(entry.Key, out _);
            }
        }

        foreach (var entry in _dekById)
        {
            if (entry.Value.HouseholdId == householdId)
            {
                _dekById.TryRemove(entry.Key, out _);
            }
        }
    }

    private async Task<CachedDek> GetOrCreateActiveDekAsync(
        Guid householdId,
        string purpose,
        CancellationToken cancellationToken)
    {
        var scope = (householdId, purpose);
        if (_activeDekByScope.TryGetValue(scope, out var cached))
        {
            return cached;
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);

        var existing = await QueryActiveDekAsync(connection, householdId, purpose, cancellationToken);
        if (existing is not null)
        {
            return CacheRow(existing, cacheAsActive: true);
        }

        var dekId = Guid.CreateVersion7();
        var rawDek = RandomNumberGenerator.GetBytes(DekLengthBytes);
        var masterKeyId = masterKeyRing.PrimaryKeyId;
        var wrappedKey = WrapDek(rawDek, masterKeyRing.GetKey(masterKeyId), dekId, householdId, purpose);

        var inserted = await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO keyring.data_key (id, household_id, purpose, master_key_id, wrapped_key)
            VALUES (@Id, @HouseholdId, @Purpose, @MasterKeyId, @WrappedKey)
            ON CONFLICT (household_id, purpose) WHERE retired_at IS NULL DO NOTHING
            """,
            new
            {
                Id = dekId,
                HouseholdId = householdId,
                Purpose = purpose,
                MasterKeyId = masterKeyId,
                WrappedKey = wrappedKey,
            },
            cancellationToken: cancellationToken));

        if (inserted == 1)
        {
            var created = new CachedDek(dekId, householdId, rawDek);
            _dekById[dekId] = created;
            _activeDekByScope[scope] = created;
            return created;
        }

        CryptographicOperations.ZeroMemory(rawDek);

        var winner = await QueryActiveDekAsync(connection, householdId, purpose, cancellationToken)
            ?? throw new InvalidOperationException(
                $"Active data key for household '{householdId:D}' and purpose '{purpose}' could not be loaded after concurrent insert.");

        return CacheRow(winner, cacheAsActive: true);
    }

    private async Task<CachedDek> GetDekByIdAsync(Guid dekId, CancellationToken cancellationToken)
    {
        if (_dekById.TryGetValue(dekId, out var cached))
        {
            return cached;
        }

        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        var row = await connection.QuerySingleOrDefaultAsync<DataKeyRow>(new CommandDefinition(
            """
            SELECT id AS Id,
                   household_id AS HouseholdId,
                   purpose AS Purpose,
                   master_key_id AS MasterKeyId,
                   wrapped_key AS WrappedKey
            FROM keyring.data_key
            WHERE id = @Id
            """,
            new { Id = dekId },
            cancellationToken: cancellationToken));

        if (row is null)
        {
            throw new CryptographicException($"Data key '{dekId:D}' was not found.");
        }

        return CacheRow(row, cacheAsActive: false);
    }

    private static Task<DataKeyRow?> QueryActiveDekAsync(
        NpgsqlConnection connection,
        Guid householdId,
        string purpose,
        CancellationToken cancellationToken) =>
        connection.QuerySingleOrDefaultAsync<DataKeyRow>(new CommandDefinition(
            """
            SELECT id AS Id,
                   household_id AS HouseholdId,
                   purpose AS Purpose,
                   master_key_id AS MasterKeyId,
                   wrapped_key AS WrappedKey
            FROM keyring.data_key
            WHERE household_id = @HouseholdId
              AND purpose = @Purpose
              AND retired_at IS NULL
            """,
            new { HouseholdId = householdId, Purpose = purpose },
            cancellationToken: cancellationToken));

    private CachedDek CacheRow(DataKeyRow row, bool cacheAsActive)
    {
        var rawDek = UnwrapDek(row);
        var cached = new CachedDek(row.Id, row.HouseholdId, rawDek);
        _dekById[row.Id] = cached;
        if (cacheAsActive)
        {
            _activeDekByScope[(row.HouseholdId, row.Purpose)] = cached;
        }

        return cached;
    }

    private byte[] UnwrapDek(DataKeyRow row)
    {
        var wrapped = row.WrappedKey;
        if (wrapped.Length != WrappedDekTotalLength)
        {
            throw new CryptographicException($"Wrapped data key '{row.Id:D}' has invalid length.");
        }

        if (wrapped[0] != FormatVersion)
        {
            throw new CryptographicException(
                $"Wrapped data key '{row.Id:D}' has unsupported format version '0x{wrapped[0]:X2}'.");
        }

        var masterKey = masterKeyRing.GetKey(row.MasterKeyId);
        var aad = BuildWrapAad(row.Id, row.HouseholdId, row.Purpose);
        var nonce = wrapped.AsSpan(WrapNonceOffset, NonceLengthBytes);
        var tag = wrapped.AsSpan(WrapTagOffset, TagLengthBytes);
        var ciphertext = wrapped.AsSpan(WrapCiphertextOffset, DekLengthBytes);
        var plaintext = new byte[DekLengthBytes];

        using var aes = new AesGcm(masterKey, TagLengthBytes);
        aes.Decrypt(nonce, ciphertext, tag, plaintext, aad);

        return plaintext;
    }

    private static byte[] WrapDek(
        ReadOnlySpan<byte> rawDek,
        byte[] masterKey,
        Guid dekId,
        Guid householdId,
        string purpose)
    {
        var wrapped = new byte[WrappedDekTotalLength];
        wrapped[0] = FormatVersion;

        var nonce = wrapped.AsSpan(WrapNonceOffset, NonceLengthBytes);
        RandomNumberGenerator.Fill(nonce);

        var tag = wrapped.AsSpan(WrapTagOffset, TagLengthBytes);
        var ciphertext = wrapped.AsSpan(WrapCiphertextOffset, DekLengthBytes);
        var aad = BuildWrapAad(dekId, householdId, purpose);

        using var aes = new AesGcm(masterKey, TagLengthBytes);
        aes.Encrypt(nonce, rawDek, ciphertext, tag, aad);

        return wrapped;
    }

    private static byte[] BuildDataAad(string table, string column, Guid rowId) =>
        Encoding.UTF8.GetBytes($"{table}:{column}:{rowId:D}");

    private static byte[] BuildWrapAad(Guid dekId, Guid householdId, string purpose) =>
        Encoding.UTF8.GetBytes($"keyring.data_key:wrapped_key:{dekId:D}:{householdId:D}:{purpose}");

    private static void ValidateScope(Guid householdId, string purpose)
    {
        if (householdId == Guid.Empty)
        {
            throw new ArgumentException("Household ID must not be empty.", nameof(householdId));
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(purpose);
    }

    private static void ValidateAadInputs(string table, string column, Guid rowId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(table);
        ArgumentException.ThrowIfNullOrWhiteSpace(column);

        if (rowId == Guid.Empty)
        {
            throw new ArgumentException("Row ID must not be empty.", nameof(rowId));
        }
    }

    private sealed record CachedDek(Guid Id, Guid HouseholdId, byte[] Key);

    private sealed class DataKeyRow
    {
        public Guid Id { get; init; }
        public Guid HouseholdId { get; init; }
        public string Purpose { get; init; } = string.Empty;
        public string MasterKeyId { get; init; } = string.Empty;
        public byte[] WrappedKey { get; init; } = [];
    }
}
