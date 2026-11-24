import 'taxonomy.dart';

export 'taxonomy.dart' show RuleLayer, TxKind;

enum AccountKind {
  checking('Conta corrente'),
  savings('Poupança'),
  creditCard('Cartão de crédito'),
  cash('Dinheiro físico');

  const AccountKind(this.label);

  final String label;
}

/// Payment instrument used for a transaction (RF-22).
enum PaymentMethod {
  pix('Pix'),
  debit('Débito'),
  credit('Crédito'),
  cash('Dinheiro'),
  boleto('Boleto'),
  transfer('Transferência'),
  other('Outro');

  const PaymentMethod(this.label);

  final String label;
}

enum ConnectionStatus {
  connected('Conectado'),
  expiringSoon('Autorização vencendo'),
  needsReconnect('Precisa reconectar');

  const ConnectionStatus(this.label);

  final String label;
}

class Bank {
  const Bank(
    this.id,
    this.name, {
    this.colorValue = 0xFFA0521A,
    this.lastSyncedLabel = 'Sincronizado hoje às 08:15',
    this.connectionStatus = ConnectionStatus.connected,
    this.consentDaysRemaining,
  });

  final String id;
  final String name;
  final int colorValue;
  final String lastSyncedLabel;
  final ConnectionStatus connectionStatus;
  final int? consentDaysRemaining;
}

class Account {
  const Account({
    required this.id,
    required this.bankId,
    required this.name,
    required this.kind,
    this.openingBalanceCents = 0,
    this.lastFourDigits,
    this.closingDay,
    this.dueDay,
  });

  final String id;
  final String bankId;
  final String name;
  final AccountKind kind;

  /// Balance before the first transaction of the dataset.
  final int openingBalanceCents;

  /// Only the last four digits of a credit card, never a full card number.
  final String? lastFourDigits;

  /// Closing day of the credit card billing cycle.
  final int? closingDay;

  /// Due day of the credit card bill in the following month.
  final int? dueDay;
}

/// One part of a split transaction (RN-24, ADR-013).
/// [amountCents] is stored in exact integer cents.
class TxSplit {
  const TxSplit({
    this.id = '',
    required this.description,
    required this.amountCents,
    this.category,
    this.essentiality,
  });

  final String id;
  final String description;
  final int amountCents;
  final SpendingCategory? category;
  final Essentiality? essentiality;

  TxSplit copyWith({
    String? id,
    String? description,
    int? amountCents,
    SpendingCategory? category,
    bool clearCategory = false,
    Essentiality? essentiality,
    bool clearEssentiality = false,
  }) => TxSplit(
    id: id ?? this.id,
    description: description ?? this.description,
    amountCents: amountCents ?? this.amountCents,
    category: clearCategory ? null : (category ?? this.category),
    essentiality: clearEssentiality
        ? null
        : (essentiality ?? this.essentiality),
  );
}

/// Validates RN-24 / ADR-013 exact-cent split invariant:
/// - At least one split must exist.
/// - Every split must have non-zero cents and consistent sign.
/// - The exact sum of split cents must equal [totalCents] (or its magnitude
///   when splits are stored as positive amounts).
bool validateSplitTotal(int totalCents, Iterable<TxSplit> splits) {
  final list = splits.toList(growable: false);
  if (list.isEmpty || totalCents == 0) return false;

  var allPositive = true;
  var allNegative = true;
  var sum = 0;
  for (final split in list) {
    if (split.amountCents == 0) return false;
    if (split.amountCents < 0) allPositive = false;
    if (split.amountCents > 0) allNegative = false;
    sum += split.amountCents;
  }

  if (allPositive) {
    return sum == totalCents.abs();
  }
  if (allNegative && totalCents < 0) {
    return sum == totalCents;
  }
  return false;
}

/// Signed remainder in cents needed for [splits] to match [totalCents.abs()].
/// Returns 0 when splits close the exact cent total.
int splitRemainingCents(int totalCents, Iterable<TxSplit> splits) {
  final allocated = splits.fold(0, (sum, s) => sum + s.amountCents.abs());
  return totalCents.abs() - allocated;
}

/// A movement in one account. Cents in an `int`; negative means money out.
/// On a credit card, a purchase is negative and the bill payment positive.
class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.date,
    required this.description,
    required this.amountCents,
    required this.kind,
    this.category,
    this.essentiality,
    this.installment,
    this.installmentCount,
    this.paymentMethod,
    this.tags = const [],
    this.isAtypical = false,
    this.splits = const [],
    this.isCashEntry = false,
    this.pendingSync = false,
  });

  /// Unique; breaks ties so the order is the same on every platform.
  final int id;
  final String accountId;
  final DateTime date;
  final String description;
  final int amountCents;
  final TxKind kind;
  final SpendingCategory? category;
  final Essentiality? essentiality;

  /// Installment number and total, e.g. 3 of 10.
  final int? installment;
  final int? installmentCount;

  /// Optional explicit payment method (RF-22); inferred if null.
  final PaymentMethod? paymentMethod;

  /// User-defined free-form tags (RF-23).
  final List<String> tags;

  /// Marks one-off expenses that should be excluded from daily projections.
  final bool isAtypical;

  /// Optional split parts summing to exact [amountCents] (RN-24).
  final List<TxSplit> splits;

  /// True for manual physical-cash entries (RF-44).
  final bool isCashEntry;

  /// True when a local offline mutation has not yet flushed to the server.
  final bool pendingSync;
}

/// Fields that can be manually corrected without altering the immutable
/// original bank record (ADR-012).
enum AdjustmentField {
  category('Categoria'),
  essentiality('Essencialidade'),
  kind('Tipo de movimento'),
  description('Descrição'),
  paymentMethod('Meio de pagamento'),
  tags('Tags'),
  atypical('Despesa atípica');

  const AdjustmentField(this.label);

  final String label;
}

/// Append-only record of a manual correction or undo (ADR-012).
class TxAdjustment {
  const TxAdjustment({
    required this.id,
    required this.txId,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.timestamp,
    this.reason,
    this.undoesId,
  });

  final String id;
  final int txId;
  final AdjustmentField field;
  final String? oldValue;
  final String? newValue;
  final String? reason;
  final DateTime timestamp;

  /// Points to the adjustment undone by this record, if this is an undo entry.
  final String? undoesId;

  bool get isUndo => undoesId != null;
}

/// Formats a raw stored adjustment field value for display in pt-BR.
String formatAdjustmentValue(AdjustmentField field, String? raw) {
  if (raw == null || raw.isEmpty) {
    if (field == AdjustmentField.tags) return 'Sem tags';
    if (field == AdjustmentField.atypical) return 'Normal';
    return 'Automático';
  }
  switch (field) {
    case AdjustmentField.category:
      for (final c in SpendingCategory.values) {
        if (c.name == raw) return c.label;
      }
      return raw;
    case AdjustmentField.essentiality:
      for (final e in Essentiality.values) {
        if (e.name == raw) return e.label;
      }
      return raw;
    case AdjustmentField.kind:
      for (final k in TxKind.values) {
        if (k.name == raw) return k.label;
      }
      return raw;
    case AdjustmentField.description:
      return raw;
    case AdjustmentField.paymentMethod:
      for (final p in PaymentMethod.values) {
        if (p.name == raw) return p.label;
      }
      return raw;
    case AdjustmentField.tags:
      final items = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      return items.isEmpty ? 'Sem tags' : items.map((t) => '#$t').join(' ');
    case AdjustmentField.atypical:
      return raw == 'true' ? 'Atípica' : 'Normal';
  }
}

/// A classification rule created by the user or generated by the profile guide.
class UserRule {
  const UserRule({
    required this.id,
    required this.merchantKey,
    required this.name,
    required this.explanation,
    this.category,
    this.essentiality,
    this.kind,
    this.isActive = true,
    this.layer = RuleLayer.user,
  });

  final String id;

  /// Normalized merchant/description key matched against original description.
  final String merchantKey;
  final String name;
  final String explanation;
  final SpendingCategory? category;
  final Essentiality? essentiality;
  final TxKind? kind;
  final bool isActive;
  final RuleLayer layer;

  UserRule copyWith({
    String? id,
    String? merchantKey,
    String? name,
    String? explanation,
    SpendingCategory? category,
    Essentiality? essentiality,
    TxKind? kind,
    bool? isActive,
    RuleLayer? layer,
  }) => UserRule(
    id: id ?? this.id,
    merchantKey: merchantKey ?? this.merchantKey,
    name: name ?? this.name,
    explanation: explanation ?? this.explanation,
    category: category ?? this.category,
    essentiality: essentiality ?? this.essentiality,
    kind: kind ?? this.kind,
    isActive: isActive ?? this.isActive,
    layer: layer ?? this.layer,
  );
}

enum ClassificationSource {
  manual('Ajuste manual'),
  userRule('Regra minha'),
  profileRule('Regra do perfil'),
  systemRule('Regra do sistema');

  const ClassificationSource(this.label);

  final String label;
}

/// Effective view merging the immutable bank [original] transaction, active
/// rules, splits, and latest manual adjustments.
class EffectiveTransaction {
  const EffectiveTransaction({
    required this.original,
    required this.description,
    required this.kind,
    required this.category,
    required this.essentiality,
    required this.categorySource,
    required this.essentialitySource,
    this.categoryRuleName,
    this.categoryRuleExplanation,
    this.essentialityRuleName,
    this.essentialityRuleExplanation,
    this.adjustedFields = const {},
    this.paymentMethod = PaymentMethod.debit,
    this.tags = const [],
    this.isAtypical = false,
    this.splits = const [],
  });

  final Transaction original;
  final String description;
  final TxKind kind;
  final SpendingCategory? category;
  final Essentiality? essentiality;
  final ClassificationSource categorySource;
  final ClassificationSource essentialitySource;
  final String? categoryRuleName;
  final String? categoryRuleExplanation;
  final String? essentialityRuleName;
  final String? essentialityRuleExplanation;
  final Set<AdjustmentField> adjustedFields;
  final PaymentMethod paymentMethod;
  final List<String> tags;
  final bool isAtypical;
  final List<TxSplit> splits;

  int get id => original.id;
  String get accountId => original.accountId;
  DateTime get date => original.date;
  int get amountCents => original.amountCents;
  int? get installment => original.installment;
  int? get installmentCount => original.installmentCount;
  bool get hasManualAdjustments => adjustedFields.isNotEmpty;
  bool get isCashEntry => original.isCashEntry;
  bool get pendingSync => original.pendingSync;

  /// Converts to a plain [Transaction] with effective fields so pure
  /// query functions work uniformly on both original and adjusted data.
  Transaction toTransaction() => Transaction(
    id: original.id,
    accountId: original.accountId,
    date: original.date,
    description: description,
    amountCents: original.amountCents,
    kind: kind,
    category: category,
    essentiality: essentiality,
    installment: original.installment,
    installmentCount: original.installmentCount,
    paymentMethod: paymentMethod,
    tags: tags,
    isAtypical: isAtypical,
    splits: splits,
    isCashEntry: original.isCashEntry,
    pendingSync: original.pendingSync,
  );
}

/// Derived credit card bill for one billing month (RF-20).
class CardBill {
  const CardBill({
    required this.accountId,
    required this.year,
    required this.month,
    required this.closingDate,
    required this.dueDate,
    required this.totalCents,
    required this.isOpen,
    required this.purchases,
  });

  final String accountId;
  final int year;
  final int month;
  final DateTime closingDate;
  final DateTime dueDate;
  final int totalCents;
  final bool isOpen;
  final List<Transaction> purchases;
}

/// Monthly budget target per spending category.
class Budget {
  const Budget({
    required this.id,
    required this.category,
    required this.limitCents,
    this.alertThreshold = 0.8,
  });

  final String id;
  final SpendingCategory category;
  final int limitCents;
  final double alertThreshold;

  Budget copyWith({
    String? id,
    SpendingCategory? category,
    int? limitCents,
    double? alertThreshold,
  }) => Budget(
    id: id ?? this.id,
    category: category ?? this.category,
    limitCents: limitCents ?? this.limitCents,
    alertThreshold: alertThreshold ?? this.alertThreshold,
  );
}

/// Financial savings goal with progress tracking.
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetCents,
    required this.currentCents,
    this.targetDate,
  });

  final String id;
  final String name;
  final int targetCents;
  final int currentCents;
  final DateTime? targetDate;

  double get progress =>
      targetCents <= 0 ? 0.0 : (currentCents / targetCents).clamp(0.0, 1.0);

  int get remainingCents =>
      targetCents > currentCents ? targetCents - currentCents : 0;

  bool get isCompleted => targetCents > 0 && currentCents >= targetCents;

  Goal copyWith({
    String? id,
    String? name,
    int? targetCents,
    int? currentCents,
    DateTime? targetDate,
  }) => Goal(
    id: id ?? this.id,
    name: name ?? this.name,
    targetCents: targetCents ?? this.targetCents,
    currentCents: currentCents ?? this.currentCents,
    targetDate: targetDate ?? this.targetDate,
  );
}

/// User-defined natural-language spending alert threshold rule.
class SpendingAlertRule {
  const SpendingAlertRule({
    required this.id,
    required this.rawExpression,
    required this.label,
    required this.thresholdCents,
    this.category,
    this.keyword,
    this.isActive = true,
  });

  final String id;
  final String rawExpression;
  final String label;
  final int thresholdCents;
  final SpendingCategory? category;
  final String? keyword;
  final bool isActive;

  SpendingAlertRule copyWith({
    String? id,
    String? rawExpression,
    String? label,
    int? thresholdCents,
    SpendingCategory? category,
    String? keyword,
    bool? isActive,
  }) => SpendingAlertRule(
    id: id ?? this.id,
    rawExpression: rawExpression ?? this.rawExpression,
    label: label ?? this.label,
    thresholdCents: thresholdCents ?? this.thresholdCents,
    category: category ?? this.category,
    keyword: keyword ?? this.keyword,
    isActive: isActive ?? this.isActive,
  );
}

/// Recurring merchant or subscription detected across >= 2 months.
class DetectedSubscription {
  const DetectedSubscription({
    required this.merchantKey,
    required this.displayName,
    required this.averageCents,
    required this.monthsCount,
    required this.typicalDayOfMonth,
    required this.lastDate,
    this.category,
  });

  final String merchantKey;
  final String displayName;
  final int averageCents;
  final int monthsCount;
  final int typicalDayOfMonth;
  final DateTime lastDate;
  final SpendingCategory? category;
}

/// 50/30/20 breakdown:
/// - Needs = Essencial
/// - Wants = Importante + Flexível
/// - Savings = max(0, leftover)
class FiftyThirtyTwenty {
  const FiftyThirtyTwenty({
    required this.incomeCents,
    required this.needsCents,
    required this.wantsCents,
    required this.savingsCents,
  });

  final int incomeCents;
  final int needsCents;
  final int wantsCents;
  final int savingsCents;

  int get baseCents =>
      incomeCents > 0 ? incomeCents : (needsCents + wantsCents + savingsCents);

  double get needsShare => baseCents <= 0 ? 0.0 : needsCents / baseCents;
  double get wantsShare => baseCents <= 0 ? 0.0 : wantsCents / baseCents;
  double get savingsShare => baseCents <= 0 ? 0.0 : savingsCents / baseCents;
}

typedef CategoryDelta = ({
  SpendingCategory? category,
  int currentCents,
  int previousCents,
  int deltaCents,
});

/// Month-over-month spending comparison summary.
class MonthComparison {
  const MonthComparison({
    required this.currentMonth,
    required this.previousMonth,
    required this.currentSpentCents,
    required this.previousSpentCents,
    required this.deltaCents,
    required this.deltaPercent,
    required this.categoryDeltas,
  });

  final DateTime currentMonth;
  final DateTime previousMonth;
  final int currentSpentCents;
  final int previousSpentCents;
  final int deltaCents;
  final double deltaPercent;
  final List<CategoryDelta> categoryDeltas;
}

/// Single day cell in the calendar spending heatmap (0 = empty, 1..5 scale).
class DailySpendingCell {
  const DailySpendingCell({
    required this.date,
    required this.spentCents,
    required this.intensity,
    required this.transactionCount,
  });

  final DateTime date;
  final int spentCents;
  final int intensity;
  final int transactionCount;
}

/// End-of-month spending projection excluding atypical one-off expenses.
class MonthProjection {
  const MonthProjection({
    required this.month,
    required this.elapsedDays,
    required this.totalDays,
    required this.regularSpentCents,
    required this.atypicalSpentCents,
    required this.projectedRegularCents,
    required this.projectedTotalCents,
    required this.atypicalCount,
  });

  final DateTime month;
  final int elapsedDays;
  final int totalDays;
  final int regularSpentCents;
  final int atypicalSpentCents;
  final int projectedRegularCents;
  final int projectedTotalCents;
  final int atypicalCount;
}

/// One extracted line item from an NFC-e XML or receipt scan.
class ReceiptItem {
  const ReceiptItem({
    required this.description,
    required this.amountCents,
    this.quantity = 1.0,
    this.suggestedCategory,
    this.suggestedEssentiality,
  });

  final String description;
  final int amountCents;
  final double quantity;
  final SpendingCategory? suggestedCategory;
  final Essentiality? suggestedEssentiality;
}

/// Parsed NFC-e receipt metadata and item breakdown.
class ReceiptParseResult {
  const ReceiptParseResult({
    required this.sourceType,
    required this.issuerName,
    required this.totalCents,
    required this.items,
    this.accessKey,
    this.issuedAt,
    this.sourceUrl,
  });

  /// `'nfce_xml'` or `'nfce_qr_url'`.
  final String sourceType;
  final String issuerName;
  final int totalCents;
  final List<ReceiptItem> items;
  final String? accessKey;
  final DateTime? issuedAt;
  final String? sourceUrl;
}

/// Offline outbox mutation queued for later replay when connectivity returns
/// (RF-44).
enum OutboxMutationType { cashEntry }

class PendingOutboxMutation {
  const PendingOutboxMutation({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.localTxId,
    required this.payload,
  });

  final String id;
  final OutboxMutationType type;
  final DateTime createdAt;
  final int localTxId;
  final Map<String, dynamic> payload;
}

/// BYOK AI provider options for Paçoca assistant (self-hosted server).
enum AiProviderKind {
  none('Desativado (somente local)'),
  openai('OpenAI'),
  anthropic('Anthropic'),
  google('Google Gemini'),
  ollama('Ollama (local / self-hosted)');

  const AiProviderKind(this.label);

  final String label;
}

class AiProviderConfig {
  const AiProviderConfig({
    this.provider = AiProviderKind.none,
    this.model = '',
    this.endpointUrl = '',
    this.hasApiKey = false,
  });

  final AiProviderKind provider;
  final String model;
  final String endpointUrl;
  final bool hasApiKey;

  AiProviderConfig copyWith({
    AiProviderKind? provider,
    String? model,
    String? endpointUrl,
    bool? hasApiKey,
  }) => AiProviderConfig(
    provider: provider ?? this.provider,
    model: model ?? this.model,
    endpointUrl: endpointUrl ?? this.endpointUrl,
    hasApiKey: hasApiKey ?? this.hasApiKey,
  );
}

/// Single turn in Paçoca's read-only financial chat.
class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.periodLabel,
    this.citedFigures = const [],
  });

  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final String? periodLabel;
  final List<String> citedFigures;
}

/// Low-confidence categorization suggestion requiring explicit user
/// confirmation before creating a rule.
class AssistantSuggestion {
  const AssistantSuggestion({
    required this.id,
    required this.merchantKey,
    required this.merchantDisplay,
    required this.suggestedCategory,
    required this.suggestedEssentiality,
    required this.confidence,
    required this.explanation,
    this.resolved = false,
    this.accepted = false,
  });

  final String id;
  final String merchantKey;
  final String merchantDisplay;
  final SpendingCategory suggestedCategory;
  final Essentiality suggestedEssentiality;
  final double confidence;
  final String explanation;
  final bool resolved;
  final bool accepted;

  AssistantSuggestion copyWith({bool? resolved, bool? accepted}) =>
      AssistantSuggestion(
        id: id,
        merchantKey: merchantKey,
        merchantDisplay: merchantDisplay,
        suggestedCategory: suggestedCategory,
        suggestedEssentiality: suggestedEssentiality,
        confidence: confidence,
        explanation: explanation,
        resolved: resolved ?? this.resolved,
        accepted: accepted ?? this.accepted,
      );
}

class Dataset {
  Dataset({
    required this.banks,
    required this.accounts,
    required List<Transaction> transactions,
    required this.today,
  }) : transactions = List.unmodifiable(
         [...transactions]..sort(
           (a, b) => b.date != a.date ? b.date.compareTo(a.date) : b.id - a.id,
         ),
       );

  final List<Bank> banks;
  final List<Account> accounts;

  /// Newest first.
  final List<Transaction> transactions;

  /// "Now" for this dataset; the default month of every screen.
  final DateTime today;

  late final Map<String, Account> _accounts = {
    for (final a in accounts) a.id: a,
  };

  late final Map<String, Bank> _banks = {for (final b in banks) b.id: b};

  Account account(String id) => _accounts[id]!;

  Bank bank(String id) => _banks[id]!;
}
