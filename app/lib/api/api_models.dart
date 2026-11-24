import '../finance/model.dart';
import '../finance/taxonomy.dart';

/// User-facing API error with clear pt-BR message (never raw stack traces or
/// networking jargon).
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.isOffline = false,
    this.isUnauthorized = false,
    this.fullResyncRequired = false,
  });

  final String code;
  final String message;
  final int? statusCode;
  final bool isOffline;
  final bool isUnauthorized;
  final bool fullResyncRequired;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Response from `GET /api/v1/server-info` (RF-01).
class ServerInfo {
  const ServerInfo({
    required this.app,
    required this.version,
    required this.apiVersion,
    required this.ownerConfigured,
    required this.providerMode,
  });

  final String app;
  final String version;
  final int apiVersion;
  final bool ownerConfigured;
  final String providerMode;

  factory ServerInfo.fromJson(Map<String, dynamic> json) => ServerInfo(
    app: (json['app'] as String?) ?? '',
    version: (json['version'] as String?) ?? '',
    apiVersion: (json['apiVersion'] as num?)?.toInt() ?? -1,
    ownerConfigured: (json['ownerConfigured'] as bool?) ?? false,
    providerMode: (json['providerMode'] as String?) ?? 'synthetic',
  );

  Map<String, dynamic> toJson() => {
    'app': app,
    'version': version,
    'apiVersion': apiVersion,
    'ownerConfigured': ownerConfigured,
    'providerMode': providerMode,
  };
}

/// Summary of the authenticated instance owner.
class OwnerSummary {
  const OwnerSummary({
    required this.id,
    required this.householdId,
    required this.email,
    required this.displayName,
  });

  final String id;
  final String householdId;
  final String email;
  final String displayName;

  factory OwnerSummary.fromJson(Map<String, dynamic> json) => OwnerSummary(
    id: (json['id'] ?? '').toString(),
    householdId: (json['householdId'] ?? '').toString(),
    email: (json['email'] as String?) ?? '',
    displayName: (json['displayName'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'householdId': householdId,
    'email': email,
    'displayName': displayName,
  };
}

/// Result of `POST /api/v1/auth/setup` (RF-02).
class SetupOwnerResult {
  const SetupOwnerResult({
    required this.ownerId,
    required this.householdId,
    required this.email,
    required this.displayName,
  });

  final String ownerId;
  final String householdId;
  final String email;
  final String displayName;

  factory SetupOwnerResult.fromJson(Map<String, dynamic> json) =>
      SetupOwnerResult(
        ownerId: (json['ownerId'] ?? '').toString(),
        householdId: (json['householdId'] ?? '').toString(),
        email: (json['email'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
      );
}

/// Active bearer + rotating refresh token pair (ADR-019).
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.sessionId,
    required this.owner,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String sessionId;
  final OwnerSummary owner;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: (json['accessToken'] as String?) ?? '',
    refreshToken: (json['refreshToken'] as String?) ?? '',
    expiresAt:
        DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
        DateTime.now().add(const Duration(minutes: 15)),
    sessionId: (json['sessionId'] ?? '').toString(),
    owner: OwnerSummary.fromJson(
      (json['owner'] as Map<String, dynamic>?) ?? const {},
    ),
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'sessionId': sessionId,
    'owner': owner.toJson(),
  };
}

/// Outcome of `POST /api/v1/auth/login` (RF-03).
class LoginResult {
  const LoginResult._({
    required this.isTotpSetupRequired,
    this.pendingToken,
    this.tokens,
  });

  factory LoginResult.totpSetupRequired(String pendingToken) =>
      LoginResult._(isTotpSetupRequired: true, pendingToken: pendingToken);

  factory LoginResult.authenticated(AuthTokens tokens) =>
      LoginResult._(isTotpSetupRequired: false, tokens: tokens);

  final bool isTotpSetupRequired;
  final String? pendingToken;
  final AuthTokens? tokens;
}

/// Response from `POST /api/v1/auth/totp/setup` (RF-03).
class TotpSetupData {
  const TotpSetupData({required this.manualKey, required this.otpauthUri});

  final String manualKey;
  final String otpauthUri;

  factory TotpSetupData.fromJson(Map<String, dynamic> json) => TotpSetupData(
    manualKey: (json['manualKey'] as String?) ?? '',
    otpauthUri: (json['otpauthUri'] as String?) ?? '',
  );
}

/// Response from `POST /api/v1/auth/totp/confirm` (RF-03).
class TotpConfirmResult {
  const TotpConfirmResult({required this.tokens, required this.recoveryCodes});

  final AuthTokens tokens;
  final List<String> recoveryCodes;

  factory TotpConfirmResult.fromJson(Map<String, dynamic> json) =>
      TotpConfirmResult(
        tokens: AuthTokens.fromJson(json),
        recoveryCodes: ((json['recoveryCodes'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );
}

/// Active device session returned by `GET /api/v1/auth/sessions` (RF-03).
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.expiresAt,
    required this.isCurrent,
  });

  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isCurrent;

  factory ActiveSession.fromJson(Map<String, dynamic> json) => ActiveSession(
    id: (json['id'] ?? '').toString(),
    deviceName: (json['deviceName'] as String?) ?? 'Dispositivo',
    createdAt:
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.now(),
    expiresAt:
        DateTime.tryParse((json['expiresAt'] as String?) ?? '') ??
        DateTime.now(),
    isCurrent: (json['isCurrent'] as bool?) ?? false,
  );
}

/// Connection health states aligned with backend `banking.connection.status`
/// and RF-14.
enum BankConnectionStatus {
  upToDate('up_to_date', 'Em dia'),
  delayed('delayed', 'Atrasada'),
  error('error', 'Com erro'),
  expired('expired', 'Vencida');

  const BankConnectionStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BankConnectionStatus parse(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'up_to_date':
      case 'connected':
        return BankConnectionStatus.upToDate;
      case 'delayed':
        return BankConnectionStatus.delayed;
      case 'error':
        return BankConnectionStatus.error;
      case 'expired':
      case 'needs_reconnect':
        return BankConnectionStatus.expired;
      default:
        return BankConnectionStatus.upToDate;
    }
  }
}

/// Bank connection metadata returned by `GET /api/v1/connections` (RF-12..14).
class BankConnectionInfo {
  const BankConnectionInfo({
    required this.id,
    required this.provider,
    required this.externalItemId,
    required this.institutionName,
    required this.brandColor,
    required this.status,
    this.lastSyncedAt,
    this.consentExpiresAt,
    this.expiringSoon = false,
    this.lastErrorCode,
    this.consecutiveFailures = 0,
  });

  final String id;
  final String provider;
  final String externalItemId;
  final String institutionName;
  final String brandColor;
  final BankConnectionStatus status;
  final DateTime? lastSyncedAt;
  final DateTime? consentExpiresAt;
  final bool expiringSoon;
  final String? lastErrorCode;
  final int consecutiveFailures;

  int get colorValue => parseBrandColor(brandColor);

  /// Remaining whole days until consent expires, or null if unknown.
  int? daysUntilExpiry([DateTime? reference]) {
    final expires = consentExpiresAt;
    if (expires == null) return null;
    final now = reference ?? DateTime.now();
    return expires.difference(now).inDays;
  }

  /// True when authorization expires within 30 days or is already expired
  /// (RF-14).
  bool needsRenewalWarning([DateTime? reference]) {
    if (status == BankConnectionStatus.expired) return true;
    if (expiringSoon) return true;
    final days = daysUntilExpiry(reference);
    return days != null && days <= 30;
  }

  factory BankConnectionInfo.fromJson(Map<String, dynamic> json) =>
      BankConnectionInfo(
        id: (json['id'] ?? '').toString(),
        provider: (json['provider'] as String?) ?? 'pluggy',
        externalItemId: (json['externalItemId'] as String?) ?? '',
        institutionName:
            (json['institutionName'] as String?) ?? 'Instituição conectada',
        brandColor: (json['brandColor'] as String?) ?? '#A0521A',
        status: BankConnectionStatus.parse(json['status'] as String?),
        lastSyncedAt: json['lastSyncedAt'] is String
            ? DateTime.tryParse(json['lastSyncedAt'] as String)
            : null,
        consentExpiresAt: json['consentExpiresAt'] is String
            ? DateTime.tryParse(json['consentExpiresAt'] as String)
            : null,
        expiringSoon: (json['expiringSoon'] as bool?) ?? false,
        lastErrorCode: json['lastErrorCode'] as String?,
        consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider,
    'externalItemId': externalItemId,
    'institutionName': institutionName,
    'brandColor': brandColor,
    'status': status.apiValue,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'consentExpiresAt': consentExpiresAt?.toIso8601String(),
    'expiringSoon': expiringSoon,
    'lastErrorCode': lastErrorCode,
    'consecutiveFailures': consecutiveFailures,
  };
}

/// Response from `POST /api/v1/connections/sync` (RF-12, RF-13).
class SyncConnectionsResult {
  const SyncConnectionsResult({
    required this.connectionsProcessed,
    required this.accountsSynced,
    required this.transactionsInserted,
    required this.transactionsVersioned,
    required this.transactionsRemoved,
    required this.transfersLinked,
    required this.failedConnections,
    required this.message,
  });

  final int connectionsProcessed;
  final int accountsSynced;
  final int transactionsInserted;
  final int transactionsVersioned;
  final int transactionsRemoved;
  final int transfersLinked;
  final int failedConnections;
  final String message;

  bool get foundNoConnections =>
      connectionsProcessed == 0 && failedConnections == 0;

  factory SyncConnectionsResult.fromJson(Map<String, dynamic> json) =>
      SyncConnectionsResult(
        connectionsProcessed:
            (json['connectionsProcessed'] as num?)?.toInt() ?? 0,
        accountsSynced: (json['accountsSynced'] as num?)?.toInt() ?? 0,
        transactionsInserted:
            (json['transactionsInserted'] as num?)?.toInt() ?? 0,
        transactionsVersioned:
            (json['transactionsVersioned'] as num?)?.toInt() ?? 0,
        transactionsRemoved:
            (json['transactionsRemoved'] as num?)?.toInt() ?? 0,
        transfersLinked: (json['transfersLinked'] as num?)?.toInt() ?? 0,
        failedConnections: (json['failedConnections'] as num?)?.toInt() ?? 0,
        message: (json['message'] as String?) ?? 'Sincronização concluída.',
      );
}

/// Serializable alert entry used in sync payloads and encrypted offline cache.
class SyncAlertItem {
  const SyncAlertItem({
    required this.id,
    required this.title,
    required this.body,
    required this.dateLabel,
    required this.targetKey,
    this.isRead = false,
    this.isResolved = false,
  });

  final String id;
  final String title;
  final String body;
  final String dateLabel;
  final String targetKey;
  final bool isRead;
  final bool isResolved;

  factory SyncAlertItem.fromJson(Map<String, dynamic> json) {
    final rawDateLabel = (json['dateLabel'] as String?)?.trim() ?? '';
    final createdAt = DateTime.tryParse((json['createdAt'] as String?) ?? '');
    final resolvedDateLabel = rawDateLabel.isNotEmpty
        ? rawDateLabel
        : (createdAt != null ? formatSyncDayTime(createdAt) : '');
    return SyncAlertItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] as String?) ?? '',
      body: (json['message'] as String?) ?? (json['body'] as String?) ?? '',
      dateLabel: resolvedDateLabel,
      targetKey:
          (json['actionTarget'] as String?) ??
          (json['target'] as String?) ??
          'connections',
      isRead: (json['isRead'] as bool?) ?? false,
      isResolved:
          json['resolvedAt'] != null || (json['isResolved'] as bool?) == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'dateLabel': dateLabel,
    'target': targetKey,
    'isRead': isRead,
    'isResolved': isResolved,
  };
}

/// Synced credit card bill summary from `GET /api/v1/sync/changes`.
class SyncCardBillItem {
  const SyncCardBillItem({
    required this.id,
    required this.accountId,
    required this.year,
    required this.month,
    required this.closingDate,
    required this.dueDate,
    required this.totalCents,
    required this.isOpen,
  });

  final String id;
  final String accountId;
  final int year;
  final int month;
  final DateTime closingDate;
  final DateTime dueDate;
  final int totalCents;
  final bool isOpen;

  factory SyncCardBillItem.fromJson(Map<String, dynamic> json) {
    final period = DateTime.tryParse((json['periodMonth'] as String?) ?? '');
    final closing =
        DateTime.tryParse(
          (json['closingOn'] as String?) ??
              (json['closingDate'] as String?) ??
              '',
        ) ??
        DateTime(period?.year ?? 2026, period?.month ?? 1, 28);
    final due =
        DateTime.tryParse(
          (json['dueOn'] as String?) ?? (json['dueDate'] as String?) ?? '',
        ) ??
        DateTime(closing.year, closing.month + 1, 10);
    return SyncCardBillItem(
      id: (json['id'] ?? '').toString(),
      accountId: (json['accountId'] ?? '').toString(),
      year: (json['year'] as num?)?.toInt() ?? period?.year ?? closing.year,
      month: (json['month'] as num?)?.toInt() ?? period?.month ?? closing.month,
      closingDate: closing,
      dueDate: due,
      totalCents: (json['totalCents'] as num?)?.toInt() ?? 0,
      isOpen: (json['isOpen'] as bool?) ?? false,
    );
  }
}

/// Incremental delta payload from `GET /api/v1/sync/changes?cursor=...` (RF-21).
class SyncChangesResponse {
  const SyncChangesResponse({
    required this.nextCursor,
    required this.hasMore,
    required this.syncedAt,
    required this.banks,
    required this.accounts,
    required this.transactions,
    required this.removedTransactionIds,
    required this.connections,
    required this.rules,
    required this.alerts,
    this.isFullSync = false,
    this.fullResyncRequired = false,
    this.adjustments = const [],
    this.cardBills = const [],
    this.transactionUuidById = const {},
  });

  final String? nextCursor;
  final bool hasMore;
  final DateTime syncedAt;
  final bool isFullSync;
  final bool fullResyncRequired;
  final List<Bank> banks;
  final List<Account> accounts;
  final List<Transaction> transactions;
  final List<int> removedTransactionIds;
  final List<BankConnectionInfo> connections;
  final List<UserRule> rules;
  final List<TxAdjustment> adjustments;
  final List<SyncCardBillItem> cardBills;
  final List<SyncAlertItem> alerts;
  final Map<int, String> transactionUuidById;

  factory SyncChangesResponse.fromJson(Map<String, dynamic> json) {
    final syncedAt =
        DateTime.tryParse(
          (json['serverTime'] as String?) ??
              (json['syncedAt'] as String?) ??
              '',
        ) ??
        DateTime.now();

    final connections = ((json['connections'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BankConnectionInfo.fromJson)
        .toList(growable: false);

    final rawBanks = (json['banks'] as List<dynamic>?) ?? const [];
    final banks = rawBanks.isNotEmpty
        ? rawBanks
              .whereType<Map<String, dynamic>>()
              .map(bankFromJson)
              .toList(growable: false)
        : [
            for (final conn in connections) bankFromConnection(conn, syncedAt),
          ];

    final accounts = ((json['accounts'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(accountFromJson)
        .toList(growable: false);

    final rawTxs = ((json['transactions'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final txUuidMap = <int, String>{};
    final transactions = <Transaction>[];
    for (final raw in rawTxs) {
      final tx = transactionFromJson(raw);
      transactions.add(tx);
      final rawId = raw['id']?.toString();
      if (rawId != null && rawId.isNotEmpty) {
        txUuidMap[tx.id] = rawId;
      }
    }

    final removedIds =
        ((json['removedTransactionIds'] as List<dynamic>?) ?? const [])
            .where((e) => e != null && e.toString().trim().isNotEmpty)
            .map(stableTransactionId)
            .toList(growable: false);

    final rules = ((json['rules'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(userRuleFromJson)
        .toList(growable: false);

    final adjustments = ((json['adjustments'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(adjustmentFromJson)
        .toList(growable: false);

    final cardBills = ((json['cardBills'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SyncCardBillItem.fromJson)
        .toList(growable: false);

    final alerts = ((json['alerts'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SyncAlertItem.fromJson)
        .toList(growable: false);

    return SyncChangesResponse(
      nextCursor:
          (json['nextCursor'] as String?) ?? (json['cursor'] as String?),
      hasMore: (json['hasMore'] as bool?) ?? false,
      isFullSync: (json['isFullSync'] as bool?) ?? false,
      fullResyncRequired: (json['fullResyncRequired'] as bool?) ?? false,
      syncedAt: syncedAt,
      banks: banks,
      accounts: accounts,
      transactions: List.unmodifiable(transactions),
      removedTransactionIds: removedIds,
      connections: connections,
      rules: rules,
      adjustments: adjustments,
      cardBills: cardBills,
      alerts: alerts,
      transactionUuidById: Map.unmodifiable(txUuidMap),
    );
  }
}

/// Parses `#RRGGBB` or `0xFFRRGGBB` brand colors safely.
int parseBrandColor(String? raw, {int fallback = 0xFFA0521A}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final cleaned = raw.trim().replaceFirst('#', '').replaceFirst('0x', '');
  if (cleaned.length == 6) {
    return int.tryParse('FF$cleaned', radix: 16) ?? fallback;
  }
  if (cleaned.length == 8) {
    return int.tryParse(cleaned, radix: 16) ?? fallback;
  }
  return fallback;
}

/// Formats a sync timestamp as `DD/MM às HH:mm`.
String formatSyncDayTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm às $hh:$min';
}

/// Formats a full timestamp as `DD/MM/AAAA às HH:mm`.
String formatFullDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final dd = local.day.toString().padLeft(2, '0');
  final mm = local.month.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$dd/$mm/${local.year} às $hh:$min';
}

Bank bankFromConnection(BankConnectionInfo conn, [DateTime? reference]) {
  final days = conn.daysUntilExpiry(reference);
  final status = switch (conn.status) {
    BankConnectionStatus.expired ||
    BankConnectionStatus.error => ConnectionStatus.needsReconnect,
    BankConnectionStatus.delayed => ConnectionStatus.expiringSoon,
    BankConnectionStatus.upToDate =>
      conn.needsRenewalWarning(reference)
          ? ConnectionStatus.expiringSoon
          : ConnectionStatus.connected,
  };
  final syncLabel = conn.lastSyncedAt == null
      ? 'Aguardando primeira sincronização'
      : 'Sincronizado em ${formatSyncDayTime(conn.lastSyncedAt!)}';
  return Bank(
    conn.id,
    conn.institutionName,
    colorValue: conn.colorValue,
    lastSyncedLabel: syncLabel,
    connectionStatus: status,
    consentDaysRemaining: days,
  );
}

Bank bankFromJson(Map<String, dynamic> json) {
  final colorRaw = json['colorValue'];
  final colorValue = colorRaw is num
      ? colorRaw.toInt()
      : parseBrandColor(json['brandColor'] as String?);
  final statusName = (json['connectionStatus'] as String?) ??
      (json['status'] as String?) ??
      'connected';
  final connectionStatus = switch (statusName) {
    'expiringSoon' || 'delayed' => ConnectionStatus.expiringSoon,
    'needsReconnect' || 'error' || 'expired' => ConnectionStatus.needsReconnect,
    _ => ConnectionStatus.connected,
  };
  return Bank(
    (json['id'] ?? '').toString(),
    (json['name'] ?? json['institutionName'] ?? 'Banco').toString(),
    colorValue: colorValue,
    lastSyncedLabel:
        (json['lastSyncedLabel'] as String?) ?? 'Sincronizado recentemente',
    connectionStatus: connectionStatus,
    consentDaysRemaining: (json['consentDaysRemaining'] as num?)?.toInt(),
  );
}

Map<String, dynamic> bankToJson(Bank bank) => {
  'id': bank.id,
  'name': bank.name,
  'colorValue': bank.colorValue,
  'lastSyncedLabel': bank.lastSyncedLabel,
  'connectionStatus': bank.connectionStatus.name,
  'consentDaysRemaining': bank.consentDaysRemaining,
};

AccountKind parseAccountKind(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case 'savings':
      return AccountKind.savings;
    case 'credit_card':
    case 'creditcard':
      return AccountKind.creditCard;
    case 'cash':
    case 'wallet':
      return AccountKind.cash;
    default:
      return AccountKind.checking;
  }
}

PaymentMethod? parsePaymentMethod(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final normalized = raw.toLowerCase().trim();
  for (final p in PaymentMethod.values) {
    if (p.name.toLowerCase() == normalized) return p;
  }
  return null;
}

Account accountFromJson(Map<String, dynamic> json) => Account(
  id: (json['id'] ?? '').toString(),
  bankId: (json['bankId'] ?? json['connectionId'] ?? '').toString(),
  name: (json['name'] as String?) ?? 'Conta',
  kind: parseAccountKind(json['kind'] as String?),
  openingBalanceCents:
      (json['openingBalanceCents'] as num?)?.toInt() ??
      (json['balanceCents'] as num?)?.toInt() ??
      0,
  lastFourDigits: json['lastFourDigits'] as String?,
  closingDay: (json['closingDay'] as num?)?.toInt(),
  dueDay: (json['dueDay'] as num?)?.toInt(),
);

Map<String, dynamic> accountToJson(Account account) => {
  'id': account.id,
  'bankId': account.bankId,
  'name': account.name,
  'kind': account.kind.name,
  'openingBalanceCents': account.openingBalanceCents,
  'lastFourDigits': account.lastFourDigits,
  'closingDay': account.closingDay,
  'dueDay': account.dueDay,
};

TxKind parseTxKind(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case 'income':
      return TxKind.income;
    case 'own_transfer':
    case 'owntransfer':
      return TxKind.ownTransfer;
    case 'card_payment':
    case 'cardpayment':
    case 'bill_payment':
    case 'billpayment':
      return TxKind.billPayment;
    case 'refund':
      return TxKind.refund;
    case 'investment':
      return TxKind.investment;
    case 'redemption':
      return TxKind.redemption;
    case 'withdrawal':
    case 'cash_withdrawal':
    case 'cashwithdrawal':
      return TxKind.cashWithdrawal;
    default:
      return TxKind.expense;
  }
}

/// Converts [TxKind] to the canonical snake_case string accepted by the
/// backend API (`BankingHelpers.TransactionKinds`, ADR-014).
String txKindToApiString(TxKind kind) => switch (kind) {
  TxKind.expense => 'expense',
  TxKind.income => 'income',
  TxKind.ownTransfer => 'own_transfer',
  TxKind.billPayment => 'card_payment',
  TxKind.refund => 'refund',
  TxKind.investment => 'investment',
  TxKind.redemption => 'redemption',
  TxKind.cashWithdrawal => 'withdrawal',
};

SpendingCategory? parseSpendingCategory(String? raw) {
  if (raw == null || raw.trim().isEmpty || raw.toLowerCase() == 'uncategorized') {
    return null;
  }
  final normalized = raw.toLowerCase().trim();
  for (final c in SpendingCategory.values) {
    if (c.name.toLowerCase() == normalized) return c;
  }
  return null;
}

Essentiality? parseEssentiality(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final normalized = raw.toLowerCase().trim();
  for (final e in Essentiality.values) {
    if (e.name.toLowerCase() == normalized) return e;
  }
  return null;
}

/// Deterministically maps numeric or UUID transaction IDs into stable positive
/// 31-bit integer IDs so additions, adjustments, and removals stay aligned.
int stableTransactionId(dynamic rawId) {
  if (rawId is num) return rawId.toInt();
  final text = rawId?.toString() ?? '';
  final parsed = int.tryParse(text);
  if (parsed != null) return parsed;
  // Deterministic 31-bit FNV-1a hash for UUID transaction identifiers.
  var hash = 0x811C9DC5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7FFFFFFF;
  }
  return hash;
}

TxSplit txSplitFromJson(Map<String, dynamic> json) => TxSplit(
  id: (json['id'] ?? '').toString(),
  description: (json['description'] as String?) ?? '',
  amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
  category: parseSpendingCategory(json['category'] as String?),
  essentiality: parseEssentiality(json['essentiality'] as String?),
);

Map<String, dynamic> txSplitToJson(TxSplit split) => {
  'id': split.id,
  'description': split.description,
  'amountCents': split.amountCents,
  'category': split.category?.name,
  'essentiality': split.essentiality?.name,
};

Transaction transactionFromJson(Map<String, dynamic> json) {
  final rawDate = (json['date'] ?? json['occurredOn'] ?? '').toString();
  final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
  final rawTags = (json['tags'] as List<dynamic>?) ?? const [];
  final rawSplits = (json['splits'] as List<dynamic>?) ?? const [];
  return Transaction(
    id: stableTransactionId(json['id']),
    accountId: (json['accountId'] ?? '').toString(),
    date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
    description:
        (json['description'] ?? json['originalDescription'] ?? '').toString(),
    amountCents: (json['amountCents'] as num?)?.toInt() ?? 0,
    kind: parseTxKind(json['kind'] as String?),
    category: parseSpendingCategory(json['category'] as String?),
    essentiality: parseEssentiality(json['essentiality'] as String?),
    installment:
        (json['installment'] as num?)?.toInt() ??
        (json['installmentNumber'] as num?)?.toInt(),
    installmentCount:
        (json['installmentCount'] as num?)?.toInt() ??
        (json['installmentTotal'] as num?)?.toInt(),
    paymentMethod: parsePaymentMethod(json['paymentMethod'] as String?),
    tags: rawTags.map((e) => e.toString()).toList(growable: false),
    isAtypical: (json['isAtypical'] as bool?) ?? false,
    splits: rawSplits
        .whereType<Map<String, dynamic>>()
        .map(txSplitFromJson)
        .toList(growable: false),
    isCashEntry: (json['isCashEntry'] as bool?) ?? false,
    pendingSync: (json['pendingSync'] as bool?) ?? false,
  );
}

Map<String, dynamic> transactionToJson(Transaction tx) => {
  'id': tx.id,
  'accountId': tx.accountId,
  'date': tx.date.toIso8601String(),
  'description': tx.description,
  'amountCents': tx.amountCents,
  'kind': tx.kind.name,
  'category': tx.category?.name,
  'essentiality': tx.essentiality?.name,
  'installment': tx.installment,
  'installmentCount': tx.installmentCount,
  if (tx.paymentMethod != null) 'paymentMethod': tx.paymentMethod!.name,
  if (tx.tags.isNotEmpty) 'tags': tx.tags,
  if (tx.isAtypical) 'isAtypical': true,
  if (tx.splits.isNotEmpty)
    'splits': [for (final s in tx.splits) txSplitToJson(s)],
  if (tx.isCashEntry) 'isCashEntry': true,
  if (tx.pendingSync) 'pendingSync': true,
};

UserRule userRuleFromJson(Map<String, dynamic> json) {
  final layerRaw = (json['layer'] as String?)?.toLowerCase();
  final layer = switch (layerRaw) {
    'profile' => RuleLayer.profile,
    'system' => RuleLayer.system,
    _ => RuleLayer.user,
  };
  return UserRule(
    id: (json['id'] ?? '').toString(),
    merchantKey:
        (json['merchantKey'] ??
                json['matchMerchantNormalized'] ??
                json['matchPattern'] ??
                '')
            .toString(),
    name: (json['name'] as String?) ?? 'Regra',
    explanation: (json['explanation'] as String?) ?? '',
    category: parseSpendingCategory(json['category'] as String?),
    essentiality: parseEssentiality(json['essentiality'] as String?),
    kind: json['kind'] is String ? parseTxKind(json['kind'] as String) : null,
    isActive: (json['isActive'] as bool?) ?? true,
    layer: layer,
  );
}

Map<String, dynamic> userRuleToJson(UserRule rule) => {
  'id': rule.id,
  'merchantKey': rule.merchantKey,
  'name': rule.name,
  'explanation': rule.explanation,
  'category': rule.category?.name,
  'essentiality': rule.essentiality?.name,
  'kind': rule.kind?.name,
  'isActive': rule.isActive,
  'layer': rule.layer.name,
};

String? _normalizeAdjustmentValue(AdjustmentField field, String? raw) {
  if (raw == null) return null;
  if (field == AdjustmentField.kind) {
    return parseTxKind(raw).name;
  }
  return raw;
}

TxAdjustment adjustmentFromJson(Map<String, dynamic> json, {int? fallbackTxId}) {
  final fieldName =
      (json['fieldName'] as String?) ?? (json['field'] as String?) ?? 'category';
  final field = AdjustmentField.values.firstWhere(
    (f) => f.name == fieldName,
    orElse: () => AdjustmentField.category,
  );
  final rawTx = json['transactionId'] ?? json['txId'];
  final txId = rawTx != null ? stableTransactionId(rawTx) : (fallbackTxId ?? 0);
  return TxAdjustment(
    id: (json['id'] ?? '').toString(),
    txId: txId,
    field: field,
    oldValue: _normalizeAdjustmentValue(field, json['oldValue'] as String?),
    newValue: _normalizeAdjustmentValue(field, json['newValue'] as String?),
    reason: json['reason'] as String?,
    timestamp:
        DateTime.tryParse(
          (json['createdAt'] as String?) ??
              (json['timestamp'] as String?) ??
              '',
        ) ??
        DateTime.now(),
    undoesId: json['undoesId']?.toString(),
  );
}

Map<String, dynamic> adjustmentToJson(TxAdjustment adj) => {
  'id': adj.id,
  'txId': adj.txId,
  'field': adj.field.name,
  'oldValue': adj.oldValue,
  'newValue': adj.newValue,
  'reason': adj.reason,
  'timestamp': adj.timestamp.toIso8601String(),
  'undoesId': adj.undoesId,
};
