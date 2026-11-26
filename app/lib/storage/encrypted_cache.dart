import 'dart:convert';
import 'dart:typed_data';

import '../api/api_models.dart';
import '../finance/model.dart';
import 'cache_storage.dart';
import 'pure_crypto.dart';

export 'pure_crypto.dart' show CacheIntegrityException;

/// Serializable bill summary stored inside the encrypted offline snapshot.
class CachedCardBill {
  const CachedCardBill({
    required this.accountId,
    required this.year,
    required this.month,
    required this.closingDate,
    required this.dueDate,
    required this.totalCents,
    required this.isOpen,
  });

  final String accountId;
  final int year;
  final int month;
  final DateTime closingDate;
  final DateTime dueDate;
  final int totalCents;
  final bool isOpen;

  factory CachedCardBill.fromJson(Map<String, dynamic> json) => CachedCardBill(
    accountId: (json['accountId'] ?? '').toString(),
    year: (json['year'] as num?)?.toInt() ?? 2026,
    month: (json['month'] as num?)?.toInt() ?? 1,
    closingDate:
        DateTime.tryParse((json['closingDate'] as String?) ?? '') ??
        DateTime(2026, 1, 28),
    dueDate:
        DateTime.tryParse((json['dueDate'] as String?) ?? '') ??
        DateTime(2026, 2, 10),
    totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
    isOpen: (json['isOpen'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'year': year,
    'month': month,
    'closingDate': closingDate.toIso8601String(),
    'dueDate': dueDate.toIso8601String(),
    'totalCents': totalCents,
    'isOpen': isOpen,
  };
}

/// Complete offline snapshot encrypted at rest (RF-21).
class CachedSnapshot {
  const CachedSnapshot({
    required this.serverUrl,
    required this.lastSyncedAt,
    this.syncCursor,
    required this.banks,
    required this.accounts,
    required this.transactions,
    this.bills = const [],
    this.connections = const [],
    this.rules = const [],
    this.adjustments = const [],
    this.alerts = const [],
    this.transactionUuidById = const {},
    this.pendingOutbox = const [],
  });

  final String serverUrl;
  final DateTime lastSyncedAt;
  final String? syncCursor;
  final List<Bank> banks;
  final List<Account> accounts;
  final List<Transaction> transactions;
  final List<CachedCardBill> bills;
  final List<BankConnectionInfo> connections;
  final List<UserRule> rules;
  final List<TxAdjustment> adjustments;
  final List<SyncAlertItem> alerts;
  final Map<int, String> transactionUuidById;
  final List<PendingOutboxMutation> pendingOutbox;

  Dataset toDataset() => Dataset(
    banks: banks,
    accounts: accounts,
    transactions: transactions,
    today: DateTime(lastSyncedAt.year, lastSyncedAt.month, lastSyncedAt.day),
  );

  factory CachedSnapshot.fromJson(Map<String, dynamic> json) {
    final rawUuidMap = json['transactionUuidById'];
    final txUuidMap = <int, String>{};
    if (rawUuidMap is Map<String, dynamic>) {
      for (final entry in rawUuidMap.entries) {
        final parsedKey = int.tryParse(entry.key);
        if (parsedKey != null && entry.value is String) {
          txUuidMap[parsedKey] = entry.value as String;
        }
      }
    }
    return CachedSnapshot(
      serverUrl: (json['serverUrl'] as String?) ?? '',
      lastSyncedAt:
          DateTime.tryParse((json['lastSyncedAt'] as String?) ?? '') ??
          DateTime.now(),
      syncCursor: json['syncCursor'] as String?,
      banks: ((json['banks'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(bankFromJson)
          .toList(growable: false),
      accounts: ((json['accounts'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(accountFromJson)
          .toList(growable: false),
      transactions: ((json['transactions'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(transactionFromJson)
          .toList(growable: false),
      bills: ((json['bills'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CachedCardBill.fromJson)
          .toList(growable: false),
      connections: ((json['connections'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BankConnectionInfo.fromJson)
          .toList(growable: false),
      rules: ((json['rules'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(userRuleFromJson)
          .toList(growable: false),
      adjustments: ((json['adjustments'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(adjustmentFromJson)
          .toList(growable: false),
      alerts: ((json['alerts'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SyncAlertItem.fromJson)
          .toList(growable: false),
      transactionUuidById: txUuidMap,
      pendingOutbox: ((json['pendingOutbox'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(outboxMutationFromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'lastSyncedAt': lastSyncedAt.toIso8601String(),
    'syncCursor': syncCursor,
    'banks': [for (final b in banks) bankToJson(b)],
    'accounts': [for (final a in accounts) accountToJson(a)],
    'transactions': [for (final t in transactions) transactionToJson(t)],
    'bills': [for (final b in bills) b.toJson()],
    'connections': [for (final c in connections) c.toJson()],
    'rules': [for (final r in rules) userRuleToJson(r)],
    'adjustments': [for (final a in adjustments) adjustmentToJson(a)],
    'alerts': [for (final a in alerts) a.toJson()],
    'transactionUuidById': {
      for (final e in transactionUuidById.entries) '${e.key}': e.value,
    },
    'pendingOutbox': [
      for (final m in pendingOutbox) outboxMutationToJson(m),
    ],
  };
}

/// Authenticated encrypted local cache store (RF-21).
///
/// Encrypts every snapshot with a fresh random 16-byte nonce using
/// [PureCrypto.seal] (HMAC-SHA256-CTR + Encrypt-then-MAC) and binds the
/// server URL as associated authenticated data so switching servers can never
/// reuse or leak a previous server's cached data (RF-01).
///
/// Key material is NEVER stored alongside `offline_snapshot.enc`: it lives in
/// an isolated [keyStorage] (separate directory with 0700/0600 permissions on
/// POSIX) and, whenever a local App Lock PIN is active, the 32-byte DEK is
/// wrapped with a PBKDF2-HMAC-SHA256 KEK derived from the PIN.
class EncryptedCacheStore {
  EncryptedCacheStore({
    CacheStorage? storage,
    CacheStorage? keyStorage,
    Uint8List? masterKey,
  }) : _storage = storage ?? createDefaultCacheStorage(),
       _keyStorage =
           keyStorage ??
           (storage == null
               ? createDefaultKeyStorage()
               : InMemoryCacheStorage()),
       _masterKey = masterKey == null ? null : Uint8List.fromList(masterKey);

  static const String snapshotKey = 'offline_snapshot.enc';
  static const String wrappedDekKey = 'wrapped_dek.enc';
  static const String deviceKeyName = 'device_cache.key';
  static const String _dekWrapAad = 'granapaca.cache.dek.v1';

  final CacheStorage _storage;
  final CacheStorage _keyStorage;
  Uint8List? _masterKey;

  /// Whether the DEK is currently held unlocked in memory.
  bool get hasUnlockedKeyInMemory => _masterKey != null;

  /// Whether the persisted DEK is wrapped with a PIN-derived KEK.
  Future<bool> hasPinWrappedKey() async {
    final envelope = await _keyStorage.readBytes(wrappedDekKey);
    return envelope != null && envelope.isNotEmpty;
  }

  /// Wraps the cache DEK using a fresh random salt + PBKDF2-HMAC-SHA256 KEK
  /// derived from [pin], removing any unwrapped device key from [keyStorage].
  Future<void> protectWithPin(String pin, {int iterations = 5000}) async {
    final dek = _masterKey ?? await _resolveOrCreateUnwrappedKey();
    final salt = PureCrypto.randomBytes(16);
    final kek = PureCrypto.pbkdf2Sha256(
      password: Uint8List.fromList(utf8.encode(pin)),
      salt: salt,
      iterations: iterations,
    );
    final wrapped = PureCrypto.seal(
      plaintext: dek,
      masterKey: kek,
      associatedData: Uint8List.fromList(utf8.encode(_dekWrapAad)),
    );
    final envelope = jsonEncode({
      'v': 1,
      'iterations': iterations,
      'salt': base64Encode(salt),
      'wrappedDek': base64Encode(wrapped),
    });
    await _keyStorage.writeBytes(
      wrappedDekKey,
      Uint8List.fromList(utf8.encode(envelope)),
    );
    await _keyStorage.delete(deviceKeyName);
    _masterKey = Uint8List.fromList(dek);
  }

  /// Unwraps the PIN-protected DEK into memory using [pin]. Returns `true`
  /// when unwrapped (or when no PIN-wrapped key exists), `false` on wrong PIN.
  Future<bool> unlockWithPin(String pin) async {
    final raw = await _keyStorage.readBytes(wrappedDekKey);
    if (raw == null || raw.isEmpty) return true;
    try {
      final decoded = jsonDecode(utf8.decode(raw));
      if (decoded is! Map<String, dynamic>) return false;
      final iterations = (decoded['iterations'] as num?)?.toInt() ?? 5000;
      final salt = base64Decode((decoded['salt'] as String?) ?? '');
      final wrapped = base64Decode((decoded['wrappedDek'] as String?) ?? '');
      final kek = PureCrypto.pbkdf2Sha256(
        password: Uint8List.fromList(utf8.encode(pin)),
        salt: Uint8List.fromList(salt),
        iterations: iterations,
      );
      final dek = PureCrypto.open(
        sealed: Uint8List.fromList(wrapped),
        masterKey: kek,
        associatedData: Uint8List.fromList(utf8.encode(_dekWrapAad)),
      );
      if (dek.length != 32) return false;
      _masterKey = dek;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes PIN wrapping and stores the DEK back in the isolated [keyStorage].
  Future<void> removePinProtection() async {
    final dek = _masterKey;
    if (dek != null) {
      await _keyStorage.writeBytes(deviceKeyName, dek);
    }
    await _keyStorage.delete(wrappedDekKey);
  }

  /// Evicts the unlocked DEK from RAM (called when locking the app).
  void lockInMemory() {
    _masterKey = null;
  }

  Future<Uint8List> _resolveOrCreateUnwrappedKey() async {
    final stored = await _keyStorage.readBytes(deviceKeyName);
    if (stored != null && stored.length == 32) {
      _masterKey = stored;
      return stored;
    }
    final generated = PureCrypto.randomBytes(32);
    await _keyStorage.writeBytes(deviceKeyName, generated);
    _masterKey = generated;
    return generated;
  }

  Future<Uint8List> _resolveMasterKey() async {
    final existing = _masterKey;
    if (existing != null) return existing;

    if (await hasPinWrappedKey()) {
      throw const CacheIntegrityException(
        'O cache local está protegido pelo PIN. Desbloqueie o app primeiro.',
      );
    }
    return _resolveOrCreateUnwrappedKey();
  }

  /// Encrypts and writes [snapshot] atomically to local cache storage.
  Future<void> saveSnapshot(CachedSnapshot snapshot) async {
    final key = await _resolveMasterKey();
    final plaintext = Uint8List.fromList(
      utf8.encode(jsonEncode(snapshot.toJson())),
    );
    final aad = Uint8List.fromList(utf8.encode(snapshot.serverUrl));
    final sealed = PureCrypto.seal(
      plaintext: plaintext,
      masterKey: key,
      associatedData: aad,
    );
    await _storage.writeBytes(snapshotKey, sealed);
  }

  /// Reads, authenticates, and decrypts the cached snapshot.
  ///
  /// Throws [CacheIntegrityException] if the ciphertext or MAC was tampered
  /// with, if the cache is locked behind a PIN, or if [expectedServerUrl] does
  /// not match the authenticated server URL used during encryption.
  Future<CachedSnapshot?> loadSnapshot({
    required String expectedServerUrl,
  }) async {
    final sealed = await _storage.readBytes(snapshotKey);
    if (sealed == null) return null;

    final key = await _resolveMasterKey();
    final aad = Uint8List.fromList(utf8.encode(expectedServerUrl));
    final plaintext = PureCrypto.open(
      sealed: sealed,
      masterKey: key,
      associatedData: aad,
    );
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map<String, dynamic>) {
      throw const CacheIntegrityException(
        'Estrutura do cache local inválida.',
      );
    }
    return CachedSnapshot.fromJson(decoded);
  }

  /// Returns raw persisted ciphertext bytes (useful for verification/audits).
  Future<Uint8List?> readRawCiphertext() => _storage.readBytes(snapshotKey);

  /// Wipes the encrypted snapshot (called on server switch or logout).
  Future<void> wipe() async {
    await _storage.delete(snapshotKey);
  }

  /// Wipes both the snapshot and all local encryption keys.
  Future<void> wipeAll() async {
    _masterKey = null;
    await _storage.deleteAll();
    await _keyStorage.deleteAll();
  }
}
