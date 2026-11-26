namespace GranaPaCa.Modules.Keyring.Contracts;

/// <summary>
/// Envelope field encryption backed by AES-256-GCM and a master key outside the database (ADR-016).
/// </summary>
public interface IEnvelopeEncryptor
{
    Task<byte[]> EncryptAsync(
        Guid householdId,
        string purpose,
        ReadOnlyMemory<byte> plaintext,
        string table,
        string column,
        Guid rowId,
        CancellationToken cancellationToken = default);

    Task<byte[]> DecryptAsync(
        byte[] envelope,
        string table,
        string column,
        Guid rowId,
        CancellationToken cancellationToken = default);

    Task RotateDataKeyAsync(
        Guid householdId,
        string purpose,
        CancellationToken cancellationToken = default);

    Task RewrapAllDataKeysAsync(CancellationToken cancellationToken = default);

    Task DestroyHouseholdKeysAsync(Guid householdId, CancellationToken cancellationToken = default);
}
