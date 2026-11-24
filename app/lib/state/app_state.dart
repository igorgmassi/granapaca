import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../api/granapaca_api_client.dart';
import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/planning_queries.dart';
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
    final normalizedTarget = item.targetKey.toLowerCase().trim();
    final target = switch (normalizedTarget) {
      'spending' || '/spending' || 'gastos' => AlertTarget.spending,
      'bankaurora' => AlertTarget.bankAurora,
      _ when normalizedTarget.startsWith('/banks/') => AlertTarget.bankAurora,
      _ => AlertTarget.connections,
    };
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
/// encrypted offline cache + cursor delta sync, cash offline outbox, app lock,
/// bank connections, transaction classification / splits / bulk edits,
/// planning (budgets, goals, alert rules), receipts consent, and Paçoca chat.
class AppState extends ChangeNotifier {
  AppState({
    Dataset? dataset,
    PreferencesStore? preferencesStore,
    GranaPaCaApiClient? apiClient,
    EncryptedCacheStore? encryptedCache,
    AppLockController? appLock,
    this._simulateNoConnections = false,
    AppMode? initialMode,
    String? initialServerUrl,
    List<BankConnectionInfo>? initialConnections,
    bool initialOffline = false,
    DateTime? initialLastSyncedAt,
  }) : _preferences = preferencesStore ?? createDefaultPreferencesStore(),
       _apiClient = apiClient ?? GranaPaCaApiClient(),
       _encryptedCache = encryptedCache ?? EncryptedCacheStore(),
       _appLock = appLock ?? AppLockController(),
       _isOffline = initialOffline,
       _lastSyncedAt = initialLastSyncedAt {
    _hideValues = _preferences.readHideValues();
    _themeMode = _preferences.readThemeMode();
    _serverUrl = initialServerUrl ?? _preferences.readServerUrl();
    _mode =
        initialMode ??
        ((_serverUrl != null && _serverUrl!.trim().isNotEmpty)
            ? AppMode.server
            : AppMode.demo);
    _dataset =
        dataset ??
        (_mode == AppMode.server
            ? Dataset(
                banks: const [],
                accounts: const [],
                transactions: const [],
                today: DateTime.now(),
              )
            : demoDataset());
    if (_serverUrl != null) {
      final parsed = Uri.tryParse(_serverUrl!);
      if (parsed != null) {
        _apiClient.setBaseUrl(parsed);
      }
    }
    _appLock.attachPreferencesStore(_preferences);
    _apiClient.onTokensChanged = _handleTokensChanged;
    _appLock.onLockoutSessionCleared = _handleLockoutSessionCleared;
    _appLock.onPinConfigured = _handlePinConfigured;
    _appLock.onPinUnlocked = _handlePinUnlocked;
    _appLock.onBiometricUnlocked = _handleBiometricUnlocked;
    _appLock.onLockDisabled = _handleLockDisabled;
    _appLock.onLocked = _handleAppLocked;
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

    if (_mode == AppMode.demo) {
      _seedDemoPlanningAndAssistant();
    } else {
      _seedAssistantWelcome();
    }
    _recompute();
  }

  static const int historyPageSize = 25;
  static const String cashBankId = 'cash-wallet-bank';
  static const String cashAccountId = 'cash-wallet';

  /// Clear pt-BR warning when attempting to edit bank transactions while
  /// offline (RF-21).
  static const String offlineEditBlockedMessage =
      'Você está sem conexão. Corrigir transações exige conexão com o seu '
      'servidor.';

  late Dataset _dataset;
  final PreferencesStore _preferences;
  final GranaPaCaApiClient _apiClient;
  final EncryptedCacheStore _encryptedCache;
  final AppLockController _appLock;

  late AppMode _mode;
  String? _serverUrl;
  ServerInfo? _serverInfo;
  AuthTokens? _authTokens;
  List<ActiveSession> _activeSessions = const [];
  late List<BankConnectionInfo> _serverConnections;
  bool _isOffline;
  DateTime? _lastSyncedAt;
  String? _syncCursor;
  bool _isSyncing = false;
  bool _isRestoringOfflineCache = false;
  String? _sessionClearedNotice;
  String? _lastMutationError;
  final Map<int, String> _txIdToUuid = {};
  List<SyncCardBillItem> _syncedCardBills = const [];
  Future<void> _mutationChain = Future<void>.value();

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
  final Map<int, List<TxSplit>> _splitsByTxId = {};
  final List<PendingOutboxMutation> _outbox = [];
  late List<AppAlert> _alerts;
  bool _simulateNoConnections;

  // Planning state
  final List<Budget> _budgets = [];
  final List<Goal> _goals = [];
  final List<SpendingAlertRule> _spendingAlertRules = [];

  // Assistant ("Paçoca") state
  final List<AssistantMessage> _assistantMessages = [];
  AiProviderConfig _aiProviderConfig = const AiProviderConfig();
  final List<AssistantSuggestion> _assistantSuggestions = [];
  bool _isAssistantLoading = false;

  // Receipts consent state
  bool _receiptConsentAccepted = false;

  int _adjustmentSeq = 1;
  int _ruleSeq = 1;
  int _localTxSeq = 100000;
  int _outboxSeq = 1;
  int _planningSeq = 1;
  int _assistantSeq = 1;

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
  bool get isRestoringOfflineCache => _isRestoringOfflineCache;
  String? get sessionClearedNotice => _sessionClearedNotice;
  String? get lastMutationError => _lastMutationError;
  List<SyncCardBillItem> get syncedCardBills =>
      List.unmodifiable(_syncedCardBills);

  /// Waits for all queued server-mode mutations (adjustments/rules) to finish.
  Future<void> flushPendingMutations() => _mutationChain;

  /// Cold-start initialization: initializes app lock hardware checks and
  /// restores the encrypted offline cache for a previously configured server
  /// profile when unlocked (RF-04, RF-21).
  Future<void> initialize() async {
    await _appLock.initialize();
    if (_mode == AppMode.server &&
        !isAuthenticated &&
        !_isOffline &&
        !_appLock.isLocked &&
        _preferences.readHasActiveServerProfile()) {
      await restoreFromEncryptedCache(markOffline: true);
    }
  }

  /// Editing bank transactions is disabled in server mode while offline (RF-21).
  /// Physical cash entries remain available offline via the outbox (RF-44).
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

  List<PendingOutboxMutation> get pendingOutbox => List.unmodifiable(_outbox);
  int get pendingOutboxCount => _outbox.length;

  List<Budget> get budgets => List.unmodifiable(_budgets);
  List<Goal> get goals => List.unmodifiable(_goals);
  List<SpendingAlertRule> get spendingAlertRules =>
      List.unmodifiable(_spendingAlertRules);

  List<AssistantMessage> get assistantMessages =>
      List.unmodifiable(_assistantMessages);
  AiProviderConfig get aiProviderConfig => _aiProviderConfig;
  List<AssistantSuggestion> get assistantSuggestions =>
      List.unmodifiable(_assistantSuggestions);
  List<AssistantSuggestion> get pendingAssistantSuggestions =>
      _assistantSuggestions.where((s) => !s.resolved).toList(growable: false);
  bool get isAssistantLoading => _isAssistantLoading;

  bool get receiptConsentAccepted => _receiptConsentAccepted;

  int get unreadAlertCount => _alerts.where((a) => !a.isRead).length;

  /// Sorted unique tags present across all effective transactions (RF-23).
  List<String> get allTags {
    final map = <String, String>{};
    for (final tx in _effectiveTransactions) {
      for (final tag in tx.tags) {
        final key = normalizeText(tag);
        map.putIfAbsent(key, () => tag);
      }
    }
    final list = map.values.toList()..sort();
    return List.unmodifiable(list);
  }

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

  void _seedDemoPlanningAndAssistant() {
    _budgets
      ..clear()
      ..addAll(const [
        Budget(
          id: 'budget-demo-food',
          category: SpendingCategory.food,
          limitCents: 120000,
          alertThreshold: 0.8,
        ),
        Budget(
          id: 'budget-demo-housing',
          category: SpendingCategory.housing,
          limitCents: 200000,
          alertThreshold: 0.85,
        ),
        Budget(
          id: 'budget-demo-transport',
          category: SpendingCategory.transport,
          limitCents: 35000,
          alertThreshold: 0.8,
        ),
      ]);

    _goals
      ..clear()
      ..addAll([
        Goal(
          id: 'goal-demo-emergency',
          name: 'Reserva de emergência',
          targetCents: 1800000,
          currentCents: 1500000,
          targetDate: DateTime(2026, 12, 31),
        ),
        Goal(
          id: 'goal-demo-trip',
          name: 'Viagem em família',
          targetCents: 600000,
          currentCents: 240000,
          targetDate: DateTime(2027, 7, 1),
        ),
      ]);

    // Seed one calm rule that is NOT exceeded in March so default unread alerts
    // remain strictly 2 on startup.
    _spendingAlertRules
      ..clear()
      ..add(
        const SpendingAlertRule(
          id: 'alert-rule-demo-leisure',
          rawExpression: 'me avise quando lazer passar de R\$ 300',
          label: 'Lazer > R\$ 300,00',
          thresholdCents: 30000,
          category: SpendingCategory.leisure,
        ),
      );

    _assistantSuggestions
      ..clear()
      ..addAll(const [
        AssistantSuggestion(
          id: 'sugg-demo-1',
          merchantKey: 'loja tudo pra casa',
          merchantDisplay: 'Loja Tudo pra Casa',
          suggestedCategory: SpendingCategory.housing,
          suggestedEssentiality: Essentiality.important,
          confidence: 0.64,
          explanation:
              'Aparece mensalmente com itens domésticos. Confirme se deseja '
              'criar uma regra para classificar como Moradia · Importante.',
        ),
        AssistantSuggestion(
          id: 'sugg-demo-2',
          merchantKey: 'corrida de app',
          merchantDisplay: 'Corrida de app',
          suggestedCategory: SpendingCategory.transport,
          suggestedEssentiality: Essentiality.flexible,
          confidence: 0.58,
          explanation:
              'Classificação sugerida com confiança média (58%). Nenhuma regra '
              'é criada automaticamente sem sua confirmação.',
        ),
      ]);

    _seedAssistantWelcome();
  }

  void _seedAssistantWelcome() {
    _assistantMessages
      ..clear()
      ..add(
        AssistantMessage(
          id: 'pacoca-welcome',
          isUser: false,
          text:
              'Olá! Eu sou a Paçoca, sua assistente financeira somente leitura. '
              'Pergunte sobre sobra do mês, categorias, 50/30/20, projeção ou '
              'assinaturas — sempre respondo citando o período e os valores exatos.',
          timestamp: _dataset.today,
          periodLabel: formatMonthYear(_selectedMonth),
        ),
      );
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

  void _clearServerSessionData() {
    _authTokens = null;
    _apiClient.setTokens(null);
    _activeSessions = const [];
    _isOffline = false;
    _syncCursor = null;
    _lastSyncedAt = null;
    _serverConnections = [];
    _syncedCardBills = const [];
    _rules.clear();
    _adjustments.clear();
    _txIdToUuid.clear();
    _splitsByTxId.clear();
    _outbox.clear();
    _budgets.clear();
    _goals.clear();
    _spendingAlertRules.clear();
    _assistantSuggestions.clear();
    _alerts = const [];
    _dataset = Dataset(
      banks: const [],
      accounts: const [],
      transactions: const [],
      today: DateTime.now(),
    );
    _recompute();
  }

  void _handleLockoutSessionCleared() {
    _clearServerSessionData();
    if (_serverUrl != null && _serverUrl!.trim().isNotEmpty) {
      _mode = AppMode.server;
    }
    _sessionClearedNotice =
        'Limite de 5 tentativas incorretas atingido. Por segurança, sua sessão '
        'e o cache offline foram encerrados e você precisa entrar novamente.';
    unawaited(_encryptedCache.wipeAll());
    unawaited(_preferences.writeHasActiveServerProfile(false));
    notifyListeners();
  }

  void _handlePinConfigured(String pin) {
    unawaited(
      _encryptedCache.protectWithPin(pin, iterations: _appLock.hashIterations),
    );
  }

  void _handlePinUnlocked(String pin) {
    final shouldRestore =
        _mode == AppMode.server &&
        !isAuthenticated &&
        !_isOffline &&
        _preferences.readHasActiveServerProfile();
    if (shouldRestore) {
      _isRestoringOfflineCache = true;
    }
    unawaited(_completePinUnlock(pin, shouldRestore: shouldRestore));
  }

  Future<void> _completePinUnlock(
    String pin, {
    required bool shouldRestore,
  }) async {
    try {
      await _encryptedCache.unlockWithPin(pin);
      if (shouldRestore && !isAuthenticated && !_isOffline) {
        await restoreFromEncryptedCache(markOffline: true);
      }
    } finally {
      if (_isRestoringOfflineCache) {
        _isRestoringOfflineCache = false;
        notifyListeners();
      }
    }
  }

  void _handleBiometricUnlocked() {
    if (_mode == AppMode.server &&
        !isAuthenticated &&
        !_isOffline &&
        _preferences.readHasActiveServerProfile()) {
      _isRestoringOfflineCache = true;
      unawaited(_completeBiometricRestore());
    }
  }

  Future<void> _completeBiometricRestore() async {
    try {
      await restoreFromEncryptedCache(markOffline: true);
    } finally {
      if (_isRestoringOfflineCache) {
        _isRestoringOfflineCache = false;
        notifyListeners();
      }
    }
  }

  void _handleLockDisabled() {
    unawaited(_encryptedCache.removePinProtection());
  }

  void _handleAppLocked() {
    if (!_appLock.biometricEnabled) {
      _encryptedCache.lockInMemory();
    }
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
      _syncedCardBills = const [];
      _rules.clear();
      _adjustments.clear();
      _txIdToUuid.clear();
      _splitsByTxId.clear();
      _outbox.clear();
      _budgets.clear();
      _goals.clear();
      _spendingAlertRules.clear();
      _assistantSuggestions.clear();
      _alerts = const [];
      _dataset = Dataset(
        banks: const [],
        accounts: const [],
        transactions: const [],
        today: DateTime.now(),
      );
      _seedAssistantWelcome();
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
    _syncedCardBills = const [];
    _alerts = _defaultDemoAlerts();
    _rules.clear();
    _adjustments.clear();
    _txIdToUuid.clear();
    _splitsByTxId.clear();
    _outbox.clear();
    _selectedMonth = DateTime(_dataset.today.year, _dataset.today.month);
    _spendingMonth = _selectedMonth;
    final (from, to) = monthRange(_selectedMonth);
    _historyFilter = TxFilter(from: from, to: to);
    unawaited(_preferences.writeHasActiveServerProfile(false));
    _seedDemoPlanningAndAssistant();
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
      await _preferences.writeHasActiveServerProfile(true);
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
    await _preferences.writeHasActiveServerProfile(true);
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

  /// RF-03: signs out of the current session, clears in-memory financial data,
  /// and wipes the encrypted offline cache.
  Future<void> logout() async {
    await _apiClient.logout();
    _clearServerSessionData();
    await _encryptedCache.wipeAll();
    await _preferences.writeHasActiveServerProfile(false);
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

  /// RF-44: replays pending offline cash-entry mutations to the server.
  Future<int> flushPendingOutbox() async {
    if (isDemoMode || _outbox.isEmpty || !isAuthenticated) return 0;
    var flushed = 0;
    final remaining = <PendingOutboxMutation>[];
    final flushedLocalIds = <int>{};

    for (final mutation in _outbox) {
      if (mutation.type == OutboxMutationType.cashEntry) {
        try {
          final p = mutation.payload;
          await _apiClient.createCashTransaction(
            date: DateTime.parse(p['date'] as String),
            description: p['description'] as String,
            amountCents: (p['amountCents'] as num).toInt(),
            category: parseSpendingCategory(p['category'] as String?),
            essentiality: parseEssentiality(p['essentiality'] as String?),
            tags: ((p['tags'] as List<dynamic>?) ?? const [])
                .map((e) => e.toString())
                .toList(growable: false),
          );
          flushed++;
          flushedLocalIds.add(mutation.localTxId);
        } on ApiException catch (error) {
          if (error.isOffline) {
            _isOffline = true;
            remaining.add(mutation);
          } else {
            remaining.add(mutation);
          }
        }
      }
    }

    _outbox
      ..clear()
      ..addAll(remaining);

    if (flushedLocalIds.isNotEmpty) {
      final updatedTxs = [
        for (final t in _dataset.transactions)
          flushedLocalIds.contains(t.id)
              ? Transaction(
                  id: t.id,
                  accountId: t.accountId,
                  date: t.date,
                  description: t.description,
                  amountCents: t.amountCents,
                  kind: t.kind,
                  category: t.category,
                  essentiality: t.essentiality,
                  installment: t.installment,
                  installmentCount: t.installmentCount,
                  paymentMethod: t.paymentMethod,
                  tags: t.tags,
                  isAtypical: t.isAtypical,
                  splits: t.splits,
                  isCashEntry: t.isCashEntry,
                  pendingSync: false,
                )
              : t,
      ];
      _dataset = Dataset(
        banks: _dataset.banks,
        accounts: _dataset.accounts,
        transactions: updatedTxs,
        today: _dataset.today,
      );
      _recompute();
      notifyListeners();
    }
    return flushed;
  }

  /// RF-13, RF-21 & RF-44: flushes pending offline cash entries, pulls
  /// incremental changes using the saved cursor, saves the updated encrypted
  /// offline snapshot, or gracefully falls back to the encrypted cache when
  /// the server is unreachable.
  Future<bool> syncFromServer({bool triggerBankSync = false}) async {
    if (isDemoMode) return false;
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      await flushPendingOutbox();
      if (triggerBankSync) {
        await _apiClient.syncConnections();
      }
      SyncChangesResponse delta;
      try {
        delta = await _apiClient.fetchSyncChanges(cursor: _syncCursor);
      } on ApiException catch (error) {
        if (error.fullResyncRequired && _syncCursor != null) {
          _syncCursor = null;
          delta = await _apiClient.fetchSyncChanges(cursor: null);
        } else {
          rethrow;
        }
      }
      if (delta.fullResyncRequired && _syncCursor != null) {
        _syncCursor = null;
        delta = await _apiClient.fetchSyncChanges(cursor: null);
      }
      _applySyncDelta(delta);
      _isOffline = false;
      await _preferences.writeHasActiveServerProfile(true);
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
      _txIdToUuid
        ..clear()
        ..addAll(snapshot.transactionUuidById);
      _rules
        ..clear()
        ..addAll(snapshot.rules);
      _adjustments
        ..clear()
        ..addAll(snapshot.adjustments);
      if (snapshot.alerts.isNotEmpty) {
        _alerts = snapshot.alerts
            .where((a) => !a.isResolved)
            .map(AppAlert.fromSyncItem)
            .toList(growable: false);
      }
      if (markOffline) {
        _isOffline = true;
      }
      if (_dataset.transactions.isNotEmpty) {
        final latestDate = _latestTransactionDate(_dataset.transactions);
        _selectedMonth = DateTime(latestDate.year, latestDate.month);
      } else {
        _selectedMonth = DateTime(_dataset.today.year, _dataset.today.month);
      }
      _spendingMonth = _selectedMonth;
      final (from, to) = monthRange(_selectedMonth);
      _historyFilter = TxFilter(from: from, to: to);
      _recompute();
      notifyListeners();
      return true;
    } on CacheIntegrityException {
      if (await _encryptedCache.hasPinWrappedKey() &&
          !_encryptedCache.hasUnlockedKeyInMemory) {
        return false;
      }
      await _encryptedCache.wipe();
      return false;
    }
  }

  DateTime _latestTransactionDate(List<Transaction> transactions) {
    var latest = transactions.first.date;
    for (final tx in transactions) {
      if (tx.date.isAfter(latest)) {
        latest = tx.date;
      }
    }
    return latest;
  }

  void _applySyncDelta(SyncChangesResponse delta) {
    final mergedBanks = <String, Bank>{
      if (!delta.isFullSync)
        for (final b in _dataset.banks) b.id: b,
      for (final b in delta.banks) b.id: b,
    };
    final mergedAccounts = <String, Account>{
      if (!delta.isFullSync)
        for (final a in _dataset.accounts) a.id: a,
      for (final a in delta.accounts) a.id: a,
    };
    final mergedTxs = <int, Transaction>{
      if (!delta.isFullSync)
        for (final t in _dataset.transactions) t.id: t,
      for (final t in delta.transactions) t.id: t,
    };
    if (delta.isFullSync) {
      _txIdToUuid.clear();
    }
    _txIdToUuid.addAll(delta.transactionUuidById);
    for (final removedId in delta.removedTransactionIds) {
      mergedTxs.remove(removedId);
      _txIdToUuid.remove(removedId);
    }

    if (delta.isFullSync) {
      _serverConnections = List<BankConnectionInfo>.from(delta.connections);
    } else if (delta.connections.isNotEmpty) {
      final mergedConns = <String, BankConnectionInfo>{
        for (final c in _serverConnections) c.id: c,
        for (final c in delta.connections) c.id: c,
      };
      _serverConnections = mergedConns.values.toList();
    }

    if (delta.isFullSync) {
      _syncedCardBills = List<SyncCardBillItem>.from(delta.cardBills);
    } else if (delta.cardBills.isNotEmpty) {
      final mergedBills = <String, SyncCardBillItem>{
        for (final b in _syncedCardBills) b.id: b,
        for (final b in delta.cardBills) b.id: b,
      };
      _syncedCardBills = mergedBills.values.toList(growable: false);
    }

    if (delta.isFullSync) {
      _rules
        ..clear()
        ..addAll(delta.rules);
    } else if (delta.rules.isNotEmpty) {
      final mergedRules = <String, UserRule>{
        for (final r in _rules) r.id: r,
        for (final r in delta.rules) r.id: r,
      };
      _rules
        ..clear()
        ..addAll(mergedRules.values);
    }

    if (delta.isFullSync) {
      _adjustments
        ..clear()
        ..addAll(delta.adjustments);
    } else if (delta.adjustments.isNotEmpty) {
      final mergedAdjs = <String, TxAdjustment>{
        for (final a in _adjustments) a.id: a,
        for (final a in delta.adjustments) a.id: a,
      };
      _adjustments
        ..clear()
        ..addAll(mergedAdjs.values);
    }

    if (delta.isFullSync) {
      _alerts = delta.alerts
          .where((a) => !a.isResolved)
          .map(AppAlert.fromSyncItem)
          .toList(growable: false);
    } else if (delta.alerts.isNotEmpty) {
      final mergedAlerts = <String, AppAlert>{
        for (final a in _alerts) a.id: a,
      };
      for (final item in delta.alerts) {
        if (item.isResolved) {
          mergedAlerts.remove(item.id);
        } else {
          mergedAlerts[item.id] = AppAlert.fromSyncItem(item);
        }
      }
      _alerts = mergedAlerts.values.toList(growable: false);
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
      final latestDate = _latestTransactionDate(_dataset.transactions);
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
      transactionUuidById: Map<int, String>.from(_txIdToUuid),
    );
    await _encryptedCache.saveSnapshot(snapshot);
  }

  void _recompute() {
    final accountsById = {for (final a in _dataset.accounts) a.id: a};
    _effectiveTransactions = List.unmodifiable(
      resolveEffectiveTransactions(
        originals: _dataset.transactions,
        rules: _rules,
        adjustments: _adjustments,
        accountsById: accountsById,
        splitsByTxId: _splitsByTxId,
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

  bool get _shouldPersistToServer =>
      isServerMode && isAuthenticated && !_isOffline;

  void _enqueueServerMutation(Future<void> Function() task) {
    _mutationChain = _mutationChain.then((_) async {
      try {
        _lastMutationError = null;
        await task();
      } on ApiException catch (error) {
        _lastMutationError = error.message;
        if (error.isOffline) {
          _isOffline = true;
        }
        notifyListeners();
      }
    });
  }

  /// Ensures the local physical-cash wallet bank & account exist lazily.
  void _ensureCashAccountExists() {
    final hasCashBank = _dataset.banks.any((b) => b.id == cashBankId);
    final hasCashAcct = _dataset.accounts.any((a) => a.id == cashAccountId);
    if (hasCashBank && hasCashAcct) return;

    final nextBanks = [
      ..._dataset.banks,
      if (!hasCashBank)
        const Bank(
          cashBankId,
          'Dinheiro físico',
          colorValue: 0xFF7A5A43,
          lastSyncedLabel: 'Lançamentos manuais locais',
        ),
    ];
    final nextAccounts = [
      ..._dataset.accounts,
      if (!hasCashAcct)
        const Account(
          id: cashAccountId,
          bankId: cashBankId,
          name: 'Carteira (Dinheiro)',
          kind: AccountKind.cash,
        ),
    ];
    _dataset = Dataset(
      banks: nextBanks,
      accounts: nextAccounts,
      transactions: _dataset.transactions,
      today: _dataset.today,
    );
  }

  /// RF-44: Quick-entry for physical cash spending. Works instantaneously in
  /// demo mode AND while offline in server mode by queueing a
  /// [PendingOutboxMutation] that flushes on the next sync.
  Future<EffectiveTransaction> addCashTransaction({
    required String description,
    required int amountCents,
    required DateTime date,
    SpendingCategory? category,
    Essentiality? essentiality,
    List<String> tags = const [],
  }) async {
    _ensureCashAccountExists();
    final cleanedDesc = description.trim().isEmpty
        ? 'Gasto em dinheiro'
        : description.trim();
    final cleanedTags = decodeTags(encodeTags(tags));
    final localId = _localTxSeq++;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final signedAmount = -amountCents.abs();
    var queuedOffline = isServerMode && _isOffline;

    if (isServerMode && !_isOffline && isAuthenticated) {
      try {
        await _apiClient.createCashTransaction(
          date: normalizedDate,
          description: cleanedDesc,
          amountCents: amountCents.abs(),
          category: category,
          essentiality: essentiality,
          tags: cleanedTags,
        );
      } on ApiException catch (error) {
        if (error.isOffline) {
          _isOffline = true;
          queuedOffline = true;
        } else {
          queuedOffline = true;
        }
      }
    }

    final tx = Transaction(
      id: localId,
      accountId: cashAccountId,
      date: normalizedDate,
      description: cleanedDesc,
      amountCents: signedAmount,
      kind: TxKind.expense,
      category: category,
      essentiality: essentiality,
      paymentMethod: PaymentMethod.cash,
      tags: cleanedTags,
      isCashEntry: true,
      pendingSync: queuedOffline,
    );

    if (queuedOffline) {
      _outbox.add(
        PendingOutboxMutation(
          id: 'outbox-${_outboxSeq++}',
          type: OutboxMutationType.cashEntry,
          createdAt: DateTime.now(),
          localTxId: localId,
          payload: {
            'date': normalizedDate.toIso8601String(),
            'description': cleanedDesc,
            'amountCents': amountCents.abs(),
            'category': category?.name,
            'essentiality': essentiality?.name,
            'tags': cleanedTags,
          },
        ),
      );
    }

    _dataset = Dataset(
      banks: _dataset.banks,
      accounts: _dataset.accounts,
      transactions: [..._dataset.transactions, tx],
      today: _dataset.today,
    );
    _recompute();
    _evaluateSpendingAlertsForMonth(DateTime(date.year, date.month));
    notifyListeners();
    return effectiveById(localId);
  }

  /// Appends immutable manual adjustments for only the fields that actually
  /// changed, keeping category and essentiality strictly independent (RF-24,
  /// RF-22, RF-23). Refuses mutations cleanly when in offline server mode
  /// (RF-21). When in authenticated online server mode, persists via
  /// `POST /api/v1/transactions/{id}/adjustments` and reconciles server IDs.
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
    PaymentMethod? paymentMethod,
    bool changePaymentMethod = false,
    List<String>? tags,
    bool changeTags = false,
    bool? isAtypical,
    bool changeAtypical = false,
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

    String? cleanedDesc;
    if (changeDescription && description != null) {
      final cleaned = description.trim();
      if (cleaned.isNotEmpty) {
        cleanedDesc = cleaned;
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
    if (changePaymentMethod && paymentMethod != null) {
      addField(
        AdjustmentField.paymentMethod,
        current.paymentMethod.name,
        paymentMethod.name,
      );
    }
    if (changeTags && tags != null) {
      final oldEncoded = encodeTags(current.tags);
      final newEncoded = encodeTags(tags);
      addField(AdjustmentField.tags, oldEncoded, newEncoded);
    }
    if (changeAtypical && isAtypical != null) {
      addField(
        AdjustmentField.atypical,
        current.isAtypical ? 'true' : 'false',
        isAtypical ? 'true' : 'false',
      );
    }

    if (created.isNotEmpty) {
      _recompute();
      _evaluateSpendingAlertsForMonth(
        DateTime(current.date.year, current.date.month),
      );
      notifyListeners();
      if (_shouldPersistToServer) {
        final serverTxId = _txIdToUuid[txId] ?? '$txId';
        final createdIds = {for (final a in created) a.id};
        _enqueueServerMutation(() async {
          try {
            final persisted = await _apiClient.applyTransactionAdjustments(
              transactionId: serverTxId,
              category: changeCategory ? category : null,
              essentiality: changeEssentiality ? essentiality : null,
              kind: changeKind ? kind : null,
              description: cleanedDesc,
              reason: trimmedReason,
            );
            if (persisted.isNotEmpty) {
              _adjustments.removeWhere((a) => createdIds.contains(a.id));
              _adjustments.addAll(persisted);
              _recompute();
            }
            await _persistEncryptedCache();
            notifyListeners();
          } on ApiException {
            _adjustments.removeWhere((a) => createdIds.contains(a.id));
            _recompute();
            rethrow;
          }
        });
      }
    }
    return created;
  }

  /// Replaces splits on [txId], strictly enforcing exact-cent sum (RN-24,
  /// ADR-013). Passing an empty list clears splits.
  bool replaceSplits(int txId, List<TxSplit> splits) {
    if (!canEditTransactions) return false;
    final current = effectiveById(txId);
    if (splits.isEmpty) {
      _splitsByTxId.remove(txId);
      _recompute();
      notifyListeners();
      return true;
    }
    if (!validateSplitTotal(current.amountCents, splits)) {
      return false;
    }
    final normalized = [
      for (var i = 0; i < splits.length; i++)
        splits[i].copyWith(
          id: splits[i].id.isEmpty ? 'split-$txId-${i + 1}' : splits[i].id,
          amountCents: splits[i].amountCents.abs(),
        ),
    ];
    _splitsByTxId[txId] = normalized;
    _recompute();
    _evaluateSpendingAlertsForMonth(
      DateTime(current.date.year, current.date.month),
    );
    notifyListeners();
    return true;
  }

  /// Applies append-only adjustments in batch across multiple selected
  /// transactions (Bulk Edit). Returns the number of modified transactions.
  int applyBulkAdjustments({
    required Set<int> txIds,
    SpendingCategory? category,
    bool changeCategory = false,
    Essentiality? essentiality,
    bool changeEssentiality = false,
    PaymentMethod? paymentMethod,
    bool changePaymentMethod = false,
    bool? isAtypical,
    bool changeAtypical = false,
    String? reason,
  }) {
    if (!canEditTransactions || txIds.isEmpty) return 0;
    var updatedCount = 0;
    final now = DateTime.now();
    final trimmedReason = (reason == null || reason.trim().isEmpty)
        ? 'Correção em lote'
        : reason.trim();

    for (final txId in txIds) {
      final current = effectiveById(txId);
      var changedThis = false;

      void addField(AdjustmentField field, String? oldVal, String? newVal) {
        if (oldVal == newVal) return;
        _adjustments.add(
          TxAdjustment(
            id: 'adj-${_adjustmentSeq++}',
            txId: txId,
            field: field,
            oldValue: oldVal,
            newValue: newVal,
            reason: trimmedReason,
            timestamp: now,
          ),
        );
        changedThis = true;
      }

      if (changeCategory && isSpendingKind(current.kind)) {
        addField(
          AdjustmentField.category,
          current.category?.name,
          category?.name,
        );
      }
      if (changeEssentiality && isSpendingKind(current.kind)) {
        addField(
          AdjustmentField.essentiality,
          current.essentiality?.name,
          essentiality?.name,
        );
      }
      if (changePaymentMethod && paymentMethod != null) {
        addField(
          AdjustmentField.paymentMethod,
          current.paymentMethod.name,
          paymentMethod.name,
        );
      }
      if (changeAtypical && isAtypical != null) {
        addField(
          AdjustmentField.atypical,
          current.isAtypical ? 'true' : 'false',
          isAtypical ? 'true' : 'false',
        );
      }
      if (changedThis) updatedCount++;
    }

    if (updatedCount > 0) {
      _recompute();
      _evaluateSpendingAlertsForMonth(_spendingMonth);
      notifyListeners();
    }
    return updatedCount;
  }

  /// Appends an undo record pointing to [adjustmentId] (ADR-012, RF-25).
  /// When in authenticated online server mode, persists via
  /// `POST /api/v1/transactions/{id}/adjustments/{adjustmentId}/undo`.
  void undoAdjustment(String adjustmentId) {
    if (!canEditTransactions) return;
    final index = _adjustments.indexWhere((a) => a.id == adjustmentId);
    if (index == -1) return;
    final target = _adjustments[index];
    if (target.isUndo || undoneIds.contains(target.id)) return;

    final optimistic = TxAdjustment(
      id: 'adj-${_adjustmentSeq++}',
      txId: target.txId,
      field: target.field,
      oldValue: target.newValue,
      newValue: target.oldValue,
      reason: 'Ajuste desfeito',
      timestamp: DateTime.now(),
      undoesId: target.id,
    );
    _adjustments.add(optimistic);
    _recompute();
    notifyListeners();

    if (_shouldPersistToServer) {
      final serverTxId = _txIdToUuid[target.txId] ?? '${target.txId}';
      _enqueueServerMutation(() async {
        try {
          final persisted = await _apiClient.undoTransactionAdjustment(
            transactionId: serverTxId,
            adjustmentId: adjustmentId,
          );
          if (persisted != null) {
            _adjustments.removeWhere((a) => a.id == optimistic.id);
            _adjustments.add(persisted);
            _recompute();
          }
          await _persistEncryptedCache();
          notifyListeners();
        } on ApiException {
          _adjustments.removeWhere((a) => a.id == optimistic.id);
          _recompute();
          rethrow;
        }
      });
    }
  }

  /// Creates a user rule from a transaction correction (RF-26, RF-31).
  /// When in authenticated online server mode, persists via `POST /api/v1/rules`.
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
    final explanation =
        'Regra criada por você para aplicar ${parts.join(' e ')} em '
        'transações de "${tx.original.description}".';
    final rule = UserRule(
      id: 'user-rule-${_ruleSeq++}',
      merchantKey: key,
      name: tx.original.description,
      explanation: explanation,
      category: category,
      essentiality: essentiality,
      kind: kind,
      isActive: true,
      layer: RuleLayer.user,
    );
    _rules.add(rule);
    _recompute();
    notifyListeners();

    if (_shouldPersistToServer && (category != null || essentiality != null)) {
      _enqueueServerMutation(() async {
        try {
          final persisted = await _apiClient.createRule(
            matchMerchant: tx.original.description,
            name: rule.name,
            explanation: explanation,
            category: category,
            essentiality: essentiality,
          );
          final idx = _rules.indexWhere((r) => r.id == rule.id);
          if (idx != -1) {
            _rules[idx] = persisted;
          } else {
            _rules.add(persisted);
          }
          _recompute();
          await _persistEncryptedCache();
          notifyListeners();
        } on ApiException {
          _rules.removeWhere((r) => r.id == rule.id);
          _recompute();
          rethrow;
        }
      });
    }
    return rule;
  }

  void toggleRuleActive(String ruleId, bool active) {
    if (!canEditTransactions) return;
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return;
    final previous = _rules[index];
    _rules[index] = previous.copyWith(isActive: active);
    _recompute();
    notifyListeners();

    if (_shouldPersistToServer) {
      _enqueueServerMutation(() async {
        try {
          final updated = await _apiClient.updateRuleActive(
            ruleId: ruleId,
            isActive: active,
          );
          final idx = _rules.indexWhere((r) => r.id == ruleId);
          if (idx != -1) {
            _rules[idx] = updated;
          }
          _recompute();
          await _persistEncryptedCache();
          notifyListeners();
        } on ApiException {
          final idx = _rules.indexWhere((r) => r.id == ruleId);
          if (idx != -1) {
            _rules[idx] = previous;
          }
          _recompute();
          rethrow;
        }
      });
    }
  }

  void deleteRule(String ruleId) {
    if (!canEditTransactions) return;
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return;
    final removed = _rules.removeAt(index);
    _recompute();
    notifyListeners();

    if (_shouldPersistToServer) {
      _enqueueServerMutation(() async {
        try {
          await _apiClient.deleteRule(ruleId);
          await _persistEncryptedCache();
        } on ApiException {
          _rules.insert(index.clamp(0, _rules.length), removed);
          _recompute();
          rethrow;
        }
      });
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

  // ---- Planning: Budgets, Goals & Custom Spending Alerts ----

  void upsertBudget({
    required SpendingCategory category,
    required int limitCents,
    double alertThreshold = 0.8,
  }) {
    if (limitCents <= 0) return;
    final existingIdx = _budgets.indexWhere((b) => b.category == category);
    if (existingIdx >= 0) {
      _budgets[existingIdx] = _budgets[existingIdx].copyWith(
        limitCents: limitCents,
        alertThreshold: alertThreshold,
      );
    } else {
      _budgets.add(
        Budget(
          id: 'budget-${_planningSeq++}',
          category: category,
          limitCents: limitCents,
          alertThreshold: alertThreshold,
        ),
      );
    }
    notifyListeners();
  }

  void deleteBudget(String budgetId) {
    final before = _budgets.length;
    _budgets.removeWhere((b) => b.id == budgetId);
    if (_budgets.length != before) notifyListeners();
  }

  Goal addGoal({
    required String name,
    required int targetCents,
    int currentCents = 0,
    DateTime? targetDate,
  }) {
    final goal = Goal(
      id: 'goal-${_planningSeq++}',
      name: name.trim(),
      targetCents: targetCents,
      currentCents: currentCents,
      targetDate: targetDate,
    );
    _goals.add(goal);
    notifyListeners();
    return goal;
  }

  void contributeToGoal(String goalId, int amountCents) {
    if (amountCents <= 0) return;
    final idx = _goals.indexWhere((g) => g.id == goalId);
    if (idx == -1) return;
    final g = _goals[idx];
    _goals[idx] = g.copyWith(currentCents: g.currentCents + amountCents);
    notifyListeners();
  }

  void deleteGoal(String goalId) {
    final before = _goals.length;
    _goals.removeWhere((g) => g.id == goalId);
    if (_goals.length != before) notifyListeners();
  }

  /// Parses a natural-language alert expression, registers the rule, and
  /// immediately raises an in-app alert if the active spending month already
  /// exceeds the threshold.
  SpendingAlertRule? addSpendingAlertRuleFromText(String rawExpression) {
    final parsed = parseSpendingAlertRule(
      rawExpression,
      id: 'alert-rule-${_planningSeq++}',
    );
    if (parsed == null) return null;
    _spendingAlertRules.add(parsed);
    _evaluateSpendingAlertsForMonth(_spendingMonth);
    notifyListeners();
    return parsed;
  }

  void toggleSpendingAlertRule(String ruleId, bool active) {
    final idx = _spendingAlertRules.indexWhere((r) => r.id == ruleId);
    if (idx == -1) return;
    _spendingAlertRules[idx] = _spendingAlertRules[idx].copyWith(
      isActive: active,
    );
    if (active) {
      _evaluateSpendingAlertsForMonth(_spendingMonth);
    }
    notifyListeners();
  }

  void deleteSpendingAlertRule(String ruleId) {
    final before = _spendingAlertRules.length;
    _spendingAlertRules.removeWhere((r) => r.id == ruleId);
    if (_spendingAlertRules.length != before) notifyListeners();
  }

  void _evaluateSpendingAlertsForMonth(DateTime month) {
    final plainTxs = _effectiveDataset.transactions;
    final monthKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';

    for (final rule in _spendingAlertRules) {
      if (!rule.isActive) continue;
      final eval = evaluateSpendingAlertRule(rule, plainTxs, month);
      if (!eval.triggered) continue;

      final alertId = 'custom-${rule.id}-$monthKey';
      if (_alerts.any((a) => a.id == alertId)) continue;

      _alerts = [
        AppAlert(
          id: alertId,
          title: 'Alerta atingido: ${rule.label}',
          body:
              'Em ${formatMonthYear(month)}, o gasto acumulado chegou a '
              '${formatBrl(eval.currentCents)}, acima do limite de '
              '${formatBrl(rule.thresholdCents)} configurado em '
              '"${rule.rawExpression}".',
          dateLabel: formatFullDate(_dataset.today),
          target: AlertTarget.spending,
        ),
        ..._alerts,
      ];
    }
  }

  // ---- Paçoca Assistant ----

  Future<AssistantMessage> askAssistant(
    String question, {
    DateTime? month,
  }) async {
    final trimmed = question.trim();
    final targetMonth = month ?? _selectedMonth;
    final userMsg = AssistantMessage(
      id: 'user-${_assistantSeq++}',
      isUser: true,
      text: trimmed,
      timestamp: DateTime.now(),
    );
    _assistantMessages.add(userMsg);
    _isAssistantLoading = true;
    notifyListeners();

    AssistantMessage reply;
    try {
      if (isServerMode && !_isOffline && isAuthenticated) {
        try {
          reply = await _apiClient.askAssistant(
            question: trimmed,
            month: targetMonth,
          );
        } on ApiException {
          reply = answerFinancialQuestion(
            trimmed,
            _effectiveDataset,
            targetMonth,
            budgets: _budgets,
            goals: _goals,
            replyId: 'pacoca-${_assistantSeq++}',
          );
        }
      } else {
        reply = answerFinancialQuestion(
          trimmed,
          _effectiveDataset,
          targetMonth,
          budgets: _budgets,
          goals: _goals,
          replyId: 'pacoca-${_assistantSeq++}',
        );
      }
      _assistantMessages.add(reply);
      return reply;
    } finally {
      _isAssistantLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateAiProviderConfig(
    AiProviderConfig config, {
    String? apiKey,
  }) async {
    _aiProviderConfig = config.copyWith(
      hasApiKey:
          config.hasApiKey || (apiKey != null && apiKey.trim().isNotEmpty),
    );
    if (isServerMode && !_isOffline && isAuthenticated) {
      await _apiClient.updateAiProviderConfig(
        _aiProviderConfig,
        apiKey: apiKey,
      );
    }
    notifyListeners();
  }

  /// Explicitly confirms a low-confidence Paçoca suggestion and creates a
  /// user classification rule.
  UserRule? confirmAssistantSuggestion(String suggestionId) {
    final idx = _assistantSuggestions.indexWhere((s) => s.id == suggestionId);
    if (idx == -1) return null;
    final sugg = _assistantSuggestions[idx];
    if (sugg.resolved) return null;

    final rule = UserRule(
      id: 'user-rule-${_ruleSeq++}',
      merchantKey: sugg.merchantKey,
      name: sugg.merchantDisplay,
      explanation:
          'Regra confirmada na Paçoca para ${sugg.suggestedCategory.label} · '
          '${sugg.suggestedEssentiality.label}.',
      category: sugg.suggestedCategory,
      essentiality: sugg.suggestedEssentiality,
      isActive: true,
      layer: RuleLayer.user,
    );
    _rules.add(rule);
    _assistantSuggestions[idx] = sugg.copyWith(resolved: true, accepted: true);
    _recompute();
    notifyListeners();
    return rule;
  }

  /// Dismisses a low-confidence suggestion without creating any rule.
  void dismissAssistantSuggestion(String suggestionId) {
    final idx = _assistantSuggestions.indexWhere((s) => s.id == suggestionId);
    if (idx == -1) return;
    _assistantSuggestions[idx] = _assistantSuggestions[idx].copyWith(
      resolved: true,
      accepted: false,
    );
    notifyListeners();
  }

  // ---- Receipts Consent & Statement Import ----

  void acceptReceiptConsent() {
    if (_receiptConsentAccepted) return;
    _receiptConsentAccepted = true;
    notifyListeners();
  }

  void revokeReceiptConsent() {
    if (!_receiptConsentAccepted) return;
    _receiptConsentAccepted = false;
    notifyListeners();
  }

  /// Imports parsed statement transactions locally (demo mode preview or
  /// offline fallback) into the active dataset.
  int importStatementTransactions(List<Transaction> imported) {
    if (imported.isEmpty) return 0;
    final assigned = <Transaction>[];
    for (final tx in imported) {
      assigned.add(
        Transaction(
          id: _localTxSeq++,
          accountId: tx.accountId,
          date: tx.date,
          description: tx.description,
          amountCents: tx.amountCents,
          kind: tx.kind,
          category: tx.category,
          essentiality: tx.essentiality,
          paymentMethod: tx.paymentMethod,
          tags: tx.tags,
        ),
      );
    }
    _dataset = Dataset(
      banks: _dataset.banks,
      accounts: _dataset.accounts,
      transactions: [..._dataset.transactions, ...assigned],
      today: _dataset.today,
    );
    _recompute();
    notifyListeners();
    return assigned.length;
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
