import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../api/granapaca_api_client.dart';
import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../security/app_lock.dart';
import '../storage/encrypted_cache.dart';
import 'demo_profiles.dart';
import 'preferences_store.dart';

enum AlertTarget { connections, bankAurora, spending }

enum AppMode { demo, server }

class AppAlert {
  const AppAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.dateLabel,
    required this.target,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final String dateLabel;
  final AlertTarget target;
  final bool isRead;

  AppAlert copyWith({bool? isRead}) => AppAlert(
    id: id,
    title: title,
    body: body,
    dateLabel: dateLabel,
    target: target,
    isRead: isRead ?? this.isRead,
  );

  SyncAlertItem toSyncItem() => SyncAlertItem(
    id: id,
    title: title,
    body: body,
    dateLabel: dateLabel,
    targetKey: target.name,
    isRead: isRead,
  );

  static AppAlert fromSyncItem(SyncAlertItem item) {
    final target = AlertTarget.values.firstWhere(
      (t) => t.name == item.targetKey,
      orElse: () => AlertTarget.connections,
    );
    return AppAlert(
      id: item.id,
      title: item.title,
      body: item.body,
      dateLabel: item.dateLabel,
      target: target,
      isRead: item.isRead,
    );
  }
}

/// Application state covering demo mode, self-hosted server authentication,
/// encrypted offline cache + cursor delta sync, app lock, bank connections,
/// and transaction classification / review queue.
class AppState extends ChangeNotifier {
  AppState({
    Dataset? dataset,
    PreferencesStore? preferencesStore,
    GranaPaCaApiClient? apiClient,
    EncryptedCacheStore? encryptedCache,
    AppLockController? appLock,
    this._simulateNoConnections = false,
    AppMode initialMode = AppMode.demo,
    String? initialServerUrl,
    List<BankConnectionInfo>? initialConnections,
    bool initialOffline = false,
    DateTime? initialLastSyncedAt,
  }) : _dataset =
           dataset ??
           (initialMode == AppMode.server
               ? Dataset(
                   banks: const [],
                   accounts: const [],
                   transactions: const [],
                   today: DateTime.now(),
                 )
               : demoDataset()),
       _preferences = preferencesStore ?? createDefaultPreferencesStore(),
       _apiClient = apiClient ?? GranaPaCaApiClient(),
       _encryptedCache = encryptedCache ?? EncryptedCacheStore(),
       _appLock = appLock ?? AppLockController(),
       _mode = initialMode,
       _isOffline = initialOffline,
       _lastSyncedAt = initialLastSyncedAt {
    _hideValues = _preferences.readHideValues();
    _themeMode = _preferences.readThemeMode();
    _serverUrl = initialServerUrl ?? _preferences.readServerUrl();
    if (_serverUrl != null) {
      final parsed = Uri.tryParse(_serverUrl!);
      if (parsed != null) {
        _apiClient.setBaseUrl(parsed);
      }
    }
    _apiClient.onTokensChanged = _handleTokensChanged;
    _appLock.onLockoutSessionCleared = _handleLockoutSessionCleared;
    _appLock.addListener(notifyListeners);

    if (initialConnections != null) {
      _serverConnections = List<BankConnectionInfo>.from(initialConnections);
    } else if (_mode == AppMode.demo) {
      _serverConnections = _demoConnectionsFromDataset(_dataset);
    } else {
      _serverConnections = [];
    }

    _selectedMonth = DateTime(_dataset.today.year, _dataset.today.month);
    _spendingMonth = _selectedMonth;
    final (from, to) = monthRange(_selectedMonth);
    _historyFilter = TxFilter(from: from, to: to);
    _alerts = _mode == AppMode.demo ? _defaultDemoAlerts() : const [];
    _recompute();
  }

  static const int historyPageSize = 25;

  /// Clear pt-BR warning when attempting to edit transactions while offline
  /// (RF-21).
  static const String offlineEditBlockedMessage =
      'Você está sem conexão. Corrigir transações exige conexão com o seu '
      'servidor.';

  Dataset _dataset;
  final PreferencesStore _preferences;
  final GranaPaCaApiClient _apiClient;
  final EncryptedCacheStore _encryptedCache;
  final AppLockController _appLock;

  AppMode _mode;
  String? _serverUrl;
  ServerInfo? _serverInfo;
  AuthTokens? _authTokens;
  List<ActiveSession> _activeSessions = const [];
  late List<BankConnectionInfo> _serverConnections;
  bool _isOffline;
  DateTime? _lastSyncedAt;
  String? _syncCursor;
  bool _isSyncing = false;
  String? _sessionClearedNotice;

  late bool _hideValues;
  late ThemeMode _themeMode;
  int _selectedTab = 0;
  late DateTime _selectedMonth;
  late TxFilter _historyFilter;
  int _historyVisibleCount = historyPageSize;

  late DateTime _spendingMonth;
  String? _spendingBankId;
  String? _spendingAccountId;

  ProfileAnswers _profileAnswers = const ProfileAnswers();
  final List<UserRule> _rules = [];
  final List<TxAdjustment> _adjustments = [];
  late List<AppAlert> _alerts;
  bool _simulateNoConnections;

  int _adjustmentSeq = 1;
  int _ruleSeq = 1;

  late List<EffectiveTransaction> _effectiveTransactions;
  late Dataset _effectiveDataset;

  @override
  void dispose() {
    _appLock.removeListener(notifyListeners);
    _appLock.dispose();
    super.dispose();
  }

  Dataset get originalDataset => _dataset;
  Dataset get effectiveDataset => _effectiveDataset;
  List<EffectiveTransaction> get effectiveTransactions =>
      _effectiveTransactions;
  GranaPaCaApiClient get apiClient => _apiClient;
  EncryptedCacheStore get encryptedCache => _encryptedCache;
  AppLockController get appLock => _appLock;

  AppMode get mode => _mode;
  bool get isDemoMode => _mode == AppMode.demo;
  bool get isServerMode => _mode == AppMode.server;
  String? get serverUrl => _serverUrl;
  ServerInfo? get serverInfo => _serverInfo;
  AuthTokens? get authTokens => _authTokens ?? _apiClient.tokens;
  OwnerSummary? get currentOwner => authTokens?.owner;
  bool get isAuthenticated => authTokens != null;
  List<ActiveSession> get activeSessions => List.unmodifiable(_activeSessions);
  List<BankConnectionInfo> get connections =>
      List.unmodifiable(_serverConnections);
  bool get isOffline => _isOffline;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get syncCursor => _syncCursor;
  bool get isSyncing => _isSyncing;
  String? get sessionClearedNotice => _sessionClearedNotice;

  /// Editing transactions is disabled in server mode while offline (RF-21).
  bool get canEditTransactions => !(isServerMode && _isOffline);

  bool get hideValues => _hideValues;
  ThemeMode get themeMode => _themeMode;
  int get selectedTab => _selectedTab;
  DateTime get selectedMonth => _selectedMonth;
  TxFilter get historyFilter => _historyFilter;
  int get historyVisibleCount => _historyVisibleCount;
  DateTime get spendingMonth => _spendingMonth;
  String? get spendingBankId => _spendingBankId;
  String? get spendingAccountId => _spendingAccountId;
  ProfileAnswers get profileAnswers => _profileAnswers;
  List<UserRule> get rules => List.unmodifiable(_rules);
  List<TxAdjustment> get adjustments => List.unmodifiable(_adjustments);
  List<AppAlert> get alerts => List.unmodifiable(_alerts);
  bool get simulateNoConnections => _simulateNoConnections;

  int get unreadAlertCount => _alerts.where((a) => !a.isRead).length;

  /// Uncategorized expenses grouped by normalized merchant name (RF-31).
  List<ReviewQueueGroup> get reviewQueueGroups => reviewQueue([
    for (final t in _effectiveTransactions) t.toTransaction(),
  ]);

  int get reviewQueueTransactionCount =>
      reviewQueueGroups.fold(0, (sum, g) => sum + g.count);

  /// Available months: fixed showcase months in demo mode, or dynamic months
  /// derived from synced transactions in server mode.
  List<DateTime> get availableMonths {
    if (isDemoMode) {
      return [
        DateTime(2026, 1),
        DateTime(2026, 2),
        DateTime(2026, 3),
        DateTime(2026, 4),
      ];
    }
    final months = <DateTime>{
      DateTime(_dataset.today.year, _dataset.today.month),
      for (final t in _dataset.transactions) DateTime(t.date.year, t.date.month),
    }.toList()..sort();
    return months;
  }

  static List<AppAlert> _defaultDemoAlerts() => const [
    AppAlert(
      id: 'alert-aurora-consent',
      title: 'Autorização do Banco Aurora vence em 15 dias',
      body:
          'Renove a permissão somente leitura pelo Meu Pluggy na sua instância '
          'para manter o extrato e as faturas atualizados.',
      dateLabel: '28/03/2026',
      target: AlertTarget.bankAurora,
    ),
    AppAlert(
      id: 'alert-card-bill',
      title: 'Fatura de março do Cartão Aurora fecha hoje',
      body:
          'A fatura aberta soma 9 compras, incluindo a parcela 5 de 10 de '
          'Notebook Loja Byte.',
      dateLabel: '28/03/2026',
      target: AlertTarget.bankAurora,
    ),
  ];

  static List<BankConnectionInfo> _demoConnectionsFromDataset(Dataset data) {
    final today = data.today;
    return [
      for (final b in data.banks)
        BankConnectionInfo(
          id: b.id,
          provider: 'demo',
          externalItemId: 'demo-${b.id}',
          institutionName: b.name,
          brandColor:
              '#${(b.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
          status: switch (b.connectionStatus) {
            ConnectionStatus.connected => BankConnectionStatus.upToDate,
            ConnectionStatus.expiringSoon => BankConnectionStatus.upToDate,
            ConnectionStatus.needsReconnect => BankConnectionStatus.expired,
          },
          lastSyncedAt: DateTime(today.year, today.month, today.day, 8, 15),
          consentExpiresAt: b.consentDaysRemaining == null
              ? null
              : today.add(Duration(days: b.consentDaysRemaining!)),
          expiringSoon:
              b.consentDaysRemaining != null && b.consentDaysRemaining! <= 30,
        ),
    ];
  }

  void _handleTokensChanged(AuthTokens? tokens) {
    _authTokens = tokens;
    notifyListeners();
  }

  void _handleLockoutSessionCleared() {
    _authTokens = null;
    _apiClient.setTokens(null);
    _activeSessions = const [];
    _sessionClearedNotice =
        'Limite de 5 tentativas incorretas atingido. Por segurança, sua sessão '
        'foi encerrada e você precisa entrar novamente.';
    notifyListeners();
  }

  void clearSessionClearedNotice() {
    if (_sessionClearedNotice == null) return;
    _sessionClearedNotice = null;
    notifyListeners();
  }

  /// RF-01: validates [rawUrl] via `/api/v1/server-info` and persists it ONLY
  /// after verification succeeds. When changing from a previously configured
  /// server URL, ends the active session and wipes the encrypted local cache.
  Future<ServerInfo> validateAndConnectServer(String rawUrl) async {
    final normalized = GranaPaCaApiClient.normalizeServerUrl(rawUrl);
    final info = await _apiClient.fetchServerInfo(normalized);
    final normalizedString = normalized.toString();

    final isSwitchingServer =
        _serverUrl != null && _serverUrl != normalizedString;
    final leavingDemo = _mode == AppMode.demo;
    if (isSwitchingServer) {
      await _apiClient.logout();
      await _encryptedCache.wipe();
      _authTokens = null;
      _activeSessions = const [];
    }
    if (isSwitchingServer || leavingDemo) {
      _syncCursor = null;
      _lastSyncedAt = null;
      _serverConnections = [];
      _rules.clear();
      _adjustments.clear();
      _alerts = const [];
      _dataset = Dataset(
        banks: const [],
        accounts: const [],
        transactions: const [],
        today: DateTime.now(),
      );
      _recompute();
    }

    _serverUrl = normalizedString;
    _serverInfo = info;
    _mode = AppMode.server;
    _isOffline = false;
    _apiClient.setBaseUrl(normalized);
    await _preferences.writeServerUrl(normalizedString);
    notifyListeners();
    return info;
  }

  /// Switches back into Demo Mode with deterministic fictitious data (RF-63).
  void enterDemoMode() {
    _mode = AppMode.demo;
    _isOffline = false;
    _dataset = demoDataset();
    _serverConnections = _demoConnectionsFromDataset(_dataset);
    _alerts = _defaultDemoAlerts();
    _rules.clear();
    _adjustments.clear();
    _selectedMonth = DateTime(_dataset.today.year, _dataset.today.month);
    _spendingMonth = _selectedMonth;
    final (from, to) = monthRange(_selectedMonth);
    _historyFilter = TxFilter(from: from, to: to);
    _recompute();
    notifyListeners();
  }

  /// RF-02: creates the single owner account on a newly validated instance.
  Future<SetupOwnerResult> setupOwner({
    required String email,
    required String displayName,
    required String password,
    String? householdName,
  }) async {
    final result = await _apiClient.setupOwner(
      email: email,
      displayName: displayName,
      password: password,
      householdName: householdName,
    );
    if (_serverInfo != null) {
      _serverInfo = ServerInfo(
        app: _serverInfo!.app,
        version: _serverInfo!.version,
        apiVersion: _serverInfo!.apiVersion,
        ownerConfigured: true,
        providerMode: _serverInfo!.providerMode,
      );
    }
    notifyListeners();
    return result;
  }

  /// RF-03: logs in against the configured server.
  Future<LoginResult> login({
    required String email,
    required String password,
    String? totpCode,
    String? recoveryCode,
    String? deviceName,
  }) async {
    _sessionClearedNotice = null;
    final result = await _apiClient.login(
      email: email,
      password: password,
      totpCode: totpCode,
      recoveryCode: recoveryCode,
      deviceName: deviceName,
    );
    if (!result.isTotpSetupRequired && result.tokens != null) {
      _authTokens = result.tokens;
      _mode = AppMode.server;
      _isOffline = false;
      notifyListeners();
    }
    return result;
  }

  Future<TotpSetupData> beginTotpSetup(String pendingToken) =>
      _apiClient.beginTotpSetup(pendingToken);

  Future<TotpConfirmResult> confirmTotp(
    String pendingToken,
    String code,
  ) async {
    final result = await _apiClient.confirmTotp(pendingToken, code);
    _authTokens = result.tokens;
    _mode = AppMode.server;
    _isOffline = false;
    notifyListeners();
    return result;
  }

  /// RF-03: loads active sessions for Settings.
  Future<List<ActiveSession>> loadActiveSessions() async {
    final sessions = await _apiClient.listSessions();
    _activeSessions = sessions;
    notifyListeners();
    return sessions;
  }

  /// RF-03: revokes one active device session.
  Future<void> revokeActiveSession(String sessionId) async {
    await _apiClient.revokeSession(sessionId);
    _activeSessions = _activeSessions
        .where((s) => s.id != sessionId)
        .toList(growable: false);
    notifyListeners();
  }

  /// RF-03: signs out of the current session and wipes local tokens.
  Future<void> logout() async {
    await _apiClient.logout();
    _authTokens = null;
    _activeSessions = const [];
    notifyListeners();
  }

  /// RF-12: registers a Pluggy item ID and triggers an immediate sync.
  Future<SyncConnectionsResult> connectPluggyAndSync({
    String? externalItemId,
    String? institutionName,
  }) async {
    if (externalItemId != null && externalItemId.trim().isNotEmpty) {
      await _apiClient.registerPluggyConnection(
        externalItemId.trim(),
        institutionName: institutionName,
      );
    }
    final result = await _apiClient.syncConnections();
    await refreshConnections();
    return result;
  }

  /// RF-14: refreshes the list of bank connections from the server.
  Future<List<BankConnectionInfo>> refreshConnections() async {
    if (isDemoMode) return connections;
    try {
      final items = await _apiClient.fetchConnections();
      _serverConnections = List<BankConnectionInfo>.from(items);
      _isOffline = false;
      notifyListeners();
      return items;
    } on ApiException catch (error) {
      if (error.isOffline) {
        _isOffline = true;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// RF-13 & RF-21: pulls incremental changes using the saved cursor, saves
  /// the updated encrypted offline snapshot, or gracefully falls back to the
  /// encrypted cache when the server is unreachable.
  Future<bool> syncFromServer({bool triggerBankSync = false}) async {
    if (isDemoMode) return false;
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      if (triggerBankSync) {
        await _apiClient.syncConnections();
      }
      final delta = await _apiClient.fetchSyncChanges(cursor: _syncCursor);
      _applySyncDelta(delta);
      _isOffline = false;
      await _persistEncryptedCache();
      return true;
    } on ApiException catch (error) {
      if (error.isOffline) {
        _isOffline = true;
        await restoreFromEncryptedCache();
        return false;
      }
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// RF-21: loads the last synced encrypted snapshot for the configured server.
  Future<bool> restoreFromEncryptedCache({bool markOffline = true}) async {
    final url = _serverUrl;
    if (url == null || url.isEmpty) return false;
    try {
      final snapshot = await _encryptedCache.loadSnapshot(
        expectedServerUrl: url,
      );
      if (snapshot == null) return false;

      _mode = AppMode.server;
      _dataset = snapshot.toDataset();
      _lastSyncedAt = snapshot.lastSyncedAt;
      _syncCursor = snapshot.syncCursor;
      _serverConnections = List<BankConnectionInfo>.from(snapshot.connections);
      _rules
        ..clear()
        ..addAll(snapshot.rules);
      _adjustments
        ..clear()
        ..addAll(snapshot.adjustments);
      if (snapshot.alerts.isNotEmpty) {
        _alerts = snapshot.alerts
            .map(AppAlert.fromSyncItem)
            .toList(growable: false);
      }
      if (markOffline) {
        _isOffline = true;
      }
      _selectedMonth = DateTime(_dataset.today.year, _dataset.today.month);
      _spendingMonth = _selectedMonth;
      final (from, to) = monthRange(_selectedMonth);
      _historyFilter = TxFilter(from: from, to: to);
      _recompute();
      notifyListeners();
      return true;
    } on CacheIntegrityException {
      await _encryptedCache.wipe();
      return false;
    }
  }

  void _applySyncDelta(SyncChangesResponse delta) {
    final mergedBanks = <String, Bank>{
      for (final b in _dataset.banks) b.id: b,
      for (final b in delta.banks) b.id: b,
    };
    final mergedAccounts = <String, Account>{
      for (final a in _dataset.accounts) a.id: a,
      for (final a in delta.accounts) a.id: a,
    };
    final mergedTxs = <int, Transaction>{
      for (final t in _dataset.transactions) t.id: t,
      for (final t in delta.transactions) t.id: t,
    };
    for (final removedId in delta.removedTransactionIds) {
      mergedTxs.remove(removedId);
    }

    if (delta.connections.isNotEmpty) {
      final mergedConns = <String, BankConnectionInfo>{
        for (final c in _serverConnections) c.id: c,
        for (final c in delta.connections) c.id: c,
      };
      _serverConnections = mergedConns.values.toList();
    }

    if (delta.rules.isNotEmpty) {
      final mergedRules = <String, UserRule>{
        for (final r in _rules) r.id: r,
        for (final r in delta.rules) r.id: r,
      };
      _rules
        ..clear()
        ..addAll(mergedRules.values);
    }

    if (delta.alerts.isNotEmpty) {
      _alerts = delta.alerts
          .map(AppAlert.fromSyncItem)
          .toList(growable: false);
    }

    _lastSyncedAt = delta.syncedAt;
    if (delta.nextCursor != null) {
      _syncCursor = delta.nextCursor;
    }

    final today = DateTime(
      delta.syncedAt.year,
      delta.syncedAt.month,
      delta.syncedAt.day,
    );
    _dataset = Dataset(
      banks: mergedBanks.values.toList(growable: false),
      accounts: mergedAccounts.values.toList(growable: false),
      transactions: mergedTxs.values.toList(growable: false),
      today: today,
    );

    if (_dataset.transactions.isNotEmpty) {
      final latestDate = _dataset.transactions.first.date;
      _selectedMonth = DateTime(latestDate.year, latestDate.month);
      _spendingMonth = _selectedMonth;
      final (from, to) = monthRange(_selectedMonth);
      _historyFilter = TxFilter(from: from, to: to);
    }
    _recompute();
  }

  Future<void> _persistEncryptedCache() async {
    final url = _serverUrl;
    if (url == null || url.isEmpty) return;

    final derivedBills = <CachedCardBill>[];
    for (final acct in _dataset.accounts) {
      if (acct.kind == AccountKind.creditCard) {
        for (final bill in cardBills(_dataset, acct.id)) {
          derivedBills.add(
            CachedCardBill(
              accountId: bill.accountId,
              year: bill.year,
              month: bill.month,
              closingDate: bill.closingDate,
              dueDate: bill.dueDate,
              totalCents: bill.totalCents,
              isOpen: bill.isOpen,
            ),
          );
        }
      }
    }

    final snapshot = CachedSnapshot(
      serverUrl: url,
      lastSyncedAt: _lastSyncedAt ?? DateTime.now(),
      syncCursor: _syncCursor,
      banks: _dataset.banks,
      accounts: _dataset.accounts,
      transactions: _dataset.transactions,
      bills: derivedBills,
      connections: _serverConnections,
      rules: _rules,
      adjustments: _adjustments,
      alerts: [for (final a in _alerts) a.toSyncItem()],
    );
    await _encryptedCache.saveSnapshot(snapshot);
  }

  void _recompute() {
    _effectiveTransactions = List.unmodifiable(
      resolveEffectiveTransactions(
        originals: _dataset.transactions,
        rules: _rules,
        adjustments: _adjustments,
      ),
    );
    _effectiveDataset = Dataset(
      banks: _dataset.banks,
      accounts: _dataset.accounts,
      transactions: [for (final t in _effectiveTransactions) t.toTransaction()],
      today: _dataset.today,
    );
  }

  EffectiveTransaction effectiveById(int txId) =>
      _effectiveTransactions.firstWhere((t) => t.id == txId);

  List<TxAdjustment> adjustmentsFor(int txId) => _adjustments
      .where((a) => a.txId == txId)
      .toList(growable: false)
      .reversed
      .toList(growable: false);

  Set<String> get undoneIds => undoneAdjustmentIds(_adjustments);

  /// Counts other transactions matching the same normalized original merchant
  /// that do not already have manual adjustments on the target fields.
  int similarTransactionsCount(
    int txId, {
    bool checkCategory = false,
    bool checkEssentiality = false,
    bool checkKind = false,
  }) {
    final target = effectiveById(txId);
    final key = merchantKeyFor(target.original.description);
    var count = 0;
    for (final other in _effectiveTransactions) {
      if (other.id == txId) continue;
      if (merchantKeyFor(other.original.description) != key) continue;
      final canAffectCategory =
          checkCategory &&
          !other.adjustedFields.contains(AdjustmentField.category);
      final canAffectEssentiality =
          checkEssentiality &&
          !other.adjustedFields.contains(AdjustmentField.essentiality);
      final canAffectKind =
          checkKind && !other.adjustedFields.contains(AdjustmentField.kind);
      if (canAffectCategory ||
          canAffectEssentiality ||
          canAffectKind ||
          (!checkCategory && !checkEssentiality && !checkKind)) {
        count++;
      }
    }
    return count;
  }

  int ruleMatchCount(UserRule rule) {
    final ruleKey = merchantKeyFor(rule.merchantKey);
    if (ruleKey.isEmpty) return 0;
    return _dataset.transactions
        .where((t) => merchantKeyFor(t.description).contains(ruleKey))
        .length;
  }

  Future<void> setHideValues(bool value) async {
    if (_hideValues == value) return;
    _hideValues = value;
    notifyListeners();
    await _preferences.writeHideValues(value);
  }

  Future<void> toggleHideValues() => setHideValues(!_hideValues);

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _preferences.writeThemeMode(mode);
  }

  void selectTab(int index) {
    if (_selectedTab == index) return;
    _selectedTab = index;
    notifyListeners();
  }

  void selectMonth(DateTime month) {
    final normalized = DateTime(month.year, month.month);
    if (_selectedMonth == normalized) return;
    _selectedMonth = normalized;
    notifyListeners();
  }

  void updateHistoryFilter(TxFilter filter) {
    _historyFilter = filter;
    _historyVisibleCount = historyPageSize;
    notifyListeners();
  }

  void clearHistoryFilters() {
    _historyFilter = const TxFilter();
    _historyVisibleCount = historyPageSize;
    notifyListeners();
  }

  void openHistoryWithFilter(TxFilter filter) {
    _historyFilter = filter;
    _historyVisibleCount = historyPageSize;
    _selectedTab = 1;
    notifyListeners();
  }

  void loadMoreHistory() {
    _historyVisibleCount += historyPageSize;
    notifyListeners();
  }

  void setSpendingFilters({
    DateTime? month,
    String? bankId,
    bool clearBank = false,
    String? accountId,
    bool clearAccount = false,
  }) {
    if (month != null) {
      _spendingMonth = DateTime(month.year, month.month);
    }
    if (clearBank) {
      _spendingBankId = null;
    } else if (bankId != null) {
      _spendingBankId = bankId;
    }
    if (clearAccount) {
      _spendingAccountId = null;
    } else if (accountId != null) {
      _spendingAccountId = accountId;
    }
    // Keep account selection consistent with bank selection.
    if (_spendingAccountId != null && _spendingBankId != null) {
      final acct = _dataset.account(_spendingAccountId!);
      if (acct.bankId != _spendingBankId) {
        _spendingAccountId = null;
      }
    }
    notifyListeners();
  }

  /// Appends immutable manual adjustments for only the fields that actually
  /// changed, keeping category and essentiality strictly independent (RF-24).
  /// Refuses mutations cleanly when in offline server mode (RF-21).
  List<TxAdjustment> adjustTransaction({
    required int txId,
    SpendingCategory? category,
    bool changeCategory = false,
    Essentiality? essentiality,
    bool changeEssentiality = false,
    TxKind? kind,
    bool changeKind = false,
    String? description,
    bool changeDescription = false,
    String? reason,
  }) {
    if (!canEditTransactions) {
      return const [];
    }
    final current = effectiveById(txId);
    final now = DateTime.now();
    final trimmedReason = (reason == null || reason.trim().isEmpty)
        ? null
        : reason.trim();
    final created = <TxAdjustment>[];

    void addField(AdjustmentField field, String? oldVal, String? newVal) {
      if (oldVal == newVal) return;
      final adj = TxAdjustment(
        id: 'adj-${_adjustmentSeq++}',
        txId: txId,
        field: field,
        oldValue: oldVal,
        newValue: newVal,
        reason: trimmedReason,
        timestamp: now,
      );
      _adjustments.add(adj);
      created.add(adj);
    }

    if (changeDescription && description != null) {
      final cleaned = description.trim();
      if (cleaned.isNotEmpty) {
        addField(AdjustmentField.description, current.description, cleaned);
      }
    }
    if (changeKind && kind != null) {
      addField(AdjustmentField.kind, current.kind.name, kind.name);
    }
    if (changeCategory) {
      addField(
        AdjustmentField.category,
        current.category?.name,
        category?.name,
      );
    }
    if (changeEssentiality) {
      addField(
        AdjustmentField.essentiality,
        current.essentiality?.name,
        essentiality?.name,
      );
    }

    if (created.isNotEmpty) {
      _recompute();
      notifyListeners();
    }
    return created;
  }

  /// Appends an undo record pointing to [adjustmentId] (ADR-012, RF-25).
  void undoAdjustment(String adjustmentId) {
    if (!canEditTransactions) return;
    final index = _adjustments.indexWhere((a) => a.id == adjustmentId);
    if (index == -1) return;
    final target = _adjustments[index];
    if (target.isUndo || undoneIds.contains(target.id)) return;

    _adjustments.add(
      TxAdjustment(
        id: 'adj-${_adjustmentSeq++}',
        txId: target.txId,
        field: target.field,
        oldValue: target.newValue,
        newValue: target.oldValue,
        reason: 'Ajuste desfeito',
        timestamp: DateTime.now(),
        undoesId: target.id,
      ),
    );
    _recompute();
    notifyListeners();
  }

  /// Creates a user rule from a transaction correction (RF-26).
  UserRule? createUserRuleFromTransaction({
    required int txId,
    SpendingCategory? category,
    Essentiality? essentiality,
    TxKind? kind,
  }) {
    if (!canEditTransactions) return null;
    final tx = effectiveById(txId);
    final key = merchantKeyFor(tx.original.description);
    final parts = <String>[
      if (category != null) 'categoria ${category.label}',
      if (essentiality != null) 'essencialidade ${essentiality.label}',
      if (kind != null) 'tipo ${kind.label}',
    ];
    final rule = UserRule(
      id: 'user-rule-${_ruleSeq++}',
      merchantKey: key,
      name: tx.original.description,
      explanation:
          'Regra criada por você para aplicar ${parts.join(' e ')} em '
          'transações de "${tx.original.description}".',
      category: category,
      essentiality: essentiality,
      kind: kind,
      isActive: true,
      layer: RuleLayer.user,
    );
    _rules.add(rule);
    _recompute();
    notifyListeners();
    return rule;
  }

  void toggleRuleActive(String ruleId, bool active) {
    if (!canEditTransactions) return;
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return;
    _rules[index] = _rules[index].copyWith(isActive: active);
    _recompute();
    notifyListeners();
  }

  void deleteRule(String ruleId) {
    if (!canEditTransactions) return;
    final before = _rules.length;
    _rules.removeWhere((r) => r.id == ruleId);
    if (_rules.length != before) {
      _recompute();
      notifyListeners();
    }
  }

  /// Replaces active profile rules from the guide without touching manual
  /// adjustments or user-created rules (RF-08).
  void applyProfileRules(
    ProfileAnswers answers,
    List<UserRule> selectedProfileRules,
  ) {
    if (!canEditTransactions) return;
    _profileAnswers = answers;
    _rules.removeWhere((r) => r.layer == RuleLayer.profile);
    _rules.addAll(
      selectedProfileRules.map(
        (r) => r.copyWith(layer: RuleLayer.profile, isActive: true),
      ),
    );
    _recompute();
    notifyListeners();
  }

  void markAlertRead(String alertId) {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index == -1 || _alerts[index].isRead) return;
    _alerts = [
      for (var i = 0; i < _alerts.length; i++)
        i == index ? _alerts[i].copyWith(isRead: true) : _alerts[i],
    ];
    notifyListeners();
  }

  void setSimulateNoConnections(bool value) {
    if (_simulateNoConnections == value) return;
    _simulateNoConnections = value;
    notifyListeners();
  }
}

/// InheritedNotifier scope exposing [AppState] throughout the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.notifier!;
  }
}
