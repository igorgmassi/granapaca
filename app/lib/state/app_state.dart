import 'package:material_ui/material_ui.dart';

import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import 'demo_profiles.dart';
import 'preferences_store.dart';

enum AlertTarget { connections, bankAurora, spending }

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
}

/// Application state for Phase 1 + interactive Demo Mode Phase 3.
class AppState extends ChangeNotifier {
  AppState({
    Dataset? dataset,
    PreferencesStore? preferencesStore,
    this._simulateNoConnections = false,
  }) : _dataset = dataset ?? demoDataset(),
       _preferences = preferencesStore ?? createDefaultPreferencesStore() {
    _hideValues = _preferences.readHideValues();
    _themeMode = _preferences.readThemeMode();
    _selectedMonth = DateTime(_dataset.today.year, _dataset.today.month);
    _spendingMonth = _selectedMonth;
    final (from, to) = monthRange(_selectedMonth);
    _historyFilter = TxFilter(from: from, to: to);
    _alerts = const [
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
    _recompute();
  }

  static const int historyPageSize = 25;

  final Dataset _dataset;
  final PreferencesStore _preferences;

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

  Dataset get originalDataset => _dataset;
  Dataset get effectiveDataset => _effectiveDataset;
  List<EffectiveTransaction> get effectiveTransactions =>
      _effectiveTransactions;

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

  /// Available demo months including an empty month (Abr/2026) to showcase
  /// empty states cleanly.
  List<DateTime> get availableMonths => [
    DateTime(2026, 1),
    DateTime(2026, 2),
    DateTime(2026, 3),
    DateTime(2026, 4),
  ];

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
  UserRule createUserRuleFromTransaction({
    required int txId,
    SpendingCategory? category,
    Essentiality? essentiality,
    TxKind? kind,
  }) {
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
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index == -1) return;
    _rules[index] = _rules[index].copyWith(isActive: active);
    _recompute();
    notifyListeners();
  }

  void deleteRule(String ruleId) {
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
