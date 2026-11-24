// Pure functions behind Início, bank drilldowns, Extrato, Gastos, cards and
// rules classification. No widgets and no I/O, so the server can compute the
// same totals later.

import 'model.dart';
import 'taxonomy.dart';

bool isSpendingKind(TxKind kind) =>
    kind == TxKind.expense || kind == TxKind.refund;

bool isSpending(Transaction t) => isSpendingKind(t.kind);

bool isIncome(Transaction t) => t.kind == TxKind.income;

/// Infers the payment method for a transaction when not explicitly set (RF-22).
PaymentMethod inferPaymentMethod(Transaction t, [Account? account]) {
  if (t.paymentMethod != null) return t.paymentMethod!;
  if (t.isCashEntry ||
      account?.kind == AccountKind.cash ||
      t.kind == TxKind.cashWithdrawal) {
    return PaymentMethod.cash;
  }
  if (account?.kind == AccountKind.creditCard) {
    return PaymentMethod.credit;
  }
  final desc = normalizeText(t.description);
  if (desc.contains('pix')) return PaymentMethod.pix;
  if (desc.contains('boleto') ||
      desc.contains('aluguel') ||
      desc.contains('conta de luz') ||
      desc.contains('internet')) {
    return PaymentMethod.boleto;
  }
  if (t.kind == TxKind.ownTransfer ||
      desc.contains('transferencia') ||
      desc.contains('salario')) {
    return PaymentMethod.transfer;
  }
  if (t.kind == TxKind.billPayment) return PaymentMethod.boleto;
  return PaymentMethod.debit;
}

/// Encodes a clean, unique list of tags into a comma-separated string.
String encodeTags(Iterable<String> tags) {
  final seen = <String>{};
  final cleaned = <String>[];
  for (final raw in tags) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^#+'), '').trim();
    if (trimmed.isEmpty) continue;
    final key = normalizeText(trimmed);
    if (seen.add(key)) {
      cleaned.add(trimmed);
    }
  }
  return cleaned.join(',');
}

/// Decodes a comma-separated tag list into clean unique tags.
List<String> decodeTags(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final seen = <String>{};
  final result = <String>[];
  for (final part in raw.split(',')) {
    final trimmed = part.trim().replaceFirst(RegExp(r'^#+'), '').trim();
    if (trimmed.isEmpty) continue;
    final key = normalizeText(trimmed);
    if (seen.add(key)) {
      result.add(trimmed);
    }
  }
  return List.unmodifiable(result);
}

/// First instant of [month] and of the next month, for `from` and `to`.
(DateTime, DateTime) monthRange(DateTime month) =>
    (DateTime(month.year, month.month), DateTime(month.year, month.month + 1));

typedef Summary = ({
  int balanceCents,
  int spentCents,
  int receivedCents,
  int leftoverCents,
  int cardBillCents,
});

/// Current balance (or negative open bill for a credit card) of one account.
int accountBalanceCents(Dataset data, Account account) => data.transactions
    .where((t) => t.accountId == account.id)
    .fold(account.openingBalanceCents, (sum, t) => sum + t.amountCents);

/// RF-16 and RF-17: all accounts, or one bank with [bankId].
/// The balance adds checking and savings accounts; the open card bill comes
/// apart. Physical cash accounts contribute to monthly spending without
/// distorting bank checking/savings balances.
/// Spent and received only count [isSpending] and [isIncome] in [month].
Summary summary(Dataset data, DateTime month, {String? bankId}) {
  bool ofBank(String accountId) =>
      bankId == null || data.account(accountId).bankId == bankId;

  var balance = 0, cardBill = 0, spent = 0, received = 0;
  for (final a in data.accounts.where((a) => ofBank(a.id))) {
    final cents = accountBalanceCents(data, a);
    if (a.kind == AccountKind.creditCard) {
      cardBill -= cents;
    } else if (a.kind != AccountKind.cash) {
      balance += cents;
    }
  }
  final (from, to) = monthRange(month);
  for (final t in data.transactions) {
    if (!ofBank(t.accountId) || t.date.isBefore(from) || !t.date.isBefore(to)) {
      continue;
    }
    if (isSpending(t)) spent -= t.amountCents;
    if (isIncome(t)) received += t.amountCents;
  }
  return (
    balanceCents: balance,
    spentCents: spent,
    receivedCents: received,
    leftoverCents: received - spent,
    cardBillCents: cardBill,
  );
}

/// Filters of the history (RF-18, RF-22, RF-23). Every field is optional and
/// they combine. The period is [from] inclusive to [to] exclusive.
class TxFilter {
  const TxFilter({
    this.from,
    this.to,
    this.bankId,
    this.accountId,
    this.kind,
    this.category,
    this.categories,
    this.uncategorizedOnly = false,
    this.essentiality,
    this.paymentMethod,
    this.tag,
    this.atypicalOnly = false,
    this.search,
    this.spendingOnly = false,
  });

  final DateTime? from;
  final DateTime? to;
  final String? bankId;
  final String? accountId;
  final TxKind? kind;
  final SpendingCategory? category;
  final Set<SpendingCategory>? categories;

  /// When true, matches only transactions whose effective category is null
  /// ("Sem categoria", RF-31), or includes them alongside [categories] when
  /// both are set.
  final bool uncategorizedOnly;
  final Essentiality? essentiality;

  /// Matches transactions with the given payment method (RF-22).
  final PaymentMethod? paymentMethod;

  /// Matches transactions carrying this tag (accent/case-insensitive, RF-23).
  final String? tag;

  /// When true, matches only transactions marked as atypical expenses.
  final bool atypicalOnly;

  /// Matches the original or corrected description ignoring case and accents.
  final String? search;

  /// When true, matches both [TxKind.expense] and [TxKind.refund] so Gastos
  /// and Extrato stay strictly aligned even with refunds.
  final bool spendingOnly;

  bool get hasActiveFilters =>
      from != null ||
      to != null ||
      bankId != null ||
      accountId != null ||
      kind != null ||
      category != null ||
      (categories != null && categories!.isNotEmpty) ||
      uncategorizedOnly ||
      essentiality != null ||
      paymentMethod != null ||
      (tag != null && tag!.trim().isNotEmpty) ||
      atypicalOnly ||
      spendingOnly ||
      (search != null && search!.trim().isNotEmpty);

  TxFilter copyWith({
    DateTime? from,
    bool clearFrom = false,
    DateTime? to,
    bool clearTo = false,
    String? bankId,
    bool clearBankId = false,
    String? accountId,
    bool clearAccountId = false,
    TxKind? kind,
    bool clearKind = false,
    SpendingCategory? category,
    bool clearCategory = false,
    Set<SpendingCategory>? categories,
    bool clearCategories = false,
    bool? uncategorizedOnly,
    Essentiality? essentiality,
    bool clearEssentiality = false,
    PaymentMethod? paymentMethod,
    bool clearPaymentMethod = false,
    String? tag,
    bool clearTag = false,
    bool? atypicalOnly,
    String? search,
    bool clearSearch = false,
    bool? spendingOnly,
  }) => TxFilter(
    from: clearFrom ? null : (from ?? this.from),
    to: clearTo ? null : (to ?? this.to),
    bankId: clearBankId ? null : (bankId ?? this.bankId),
    accountId: clearAccountId ? null : (accountId ?? this.accountId),
    kind: clearKind ? null : (kind ?? this.kind),
    category: clearCategory ? null : (category ?? this.category),
    categories: clearCategories ? null : (categories ?? this.categories),
    uncategorizedOnly: uncategorizedOnly ?? this.uncategorizedOnly,
    essentiality: clearEssentiality
        ? null
        : (essentiality ?? this.essentiality),
    paymentMethod: clearPaymentMethod
        ? null
        : (paymentMethod ?? this.paymentMethod),
    tag: clearTag ? null : (tag ?? this.tag),
    atypicalOnly: atypicalOnly ?? this.atypicalOnly,
    search: clearSearch ? null : (search ?? this.search),
    spendingOnly: spendingOnly ?? this.spendingOnly,
  );
}

/// The Gastos filter (RF-36): spending only, in a period, all banks or one
/// bank or account.
TxFilter spendingFilter(
  DateTime from,
  DateTime to, {
  String? bankId,
  String? accountId,
}) => TxFilter(
  from: from,
  to: to,
  bankId: bankId,
  accountId: accountId,
  spendingOnly: true,
);

typedef History = ({List<Transaction> items, int totalCents});

bool _matchesCategory(Transaction t, SpendingCategory target) {
  if (t.splits.isNotEmpty) {
    return t.splits.any((s) => s.category == target);
  }
  return t.category == target;
}

bool _matchesAnyCategory(Transaction t, Set<SpendingCategory> targets) {
  if (t.splits.isNotEmpty) {
    return t.splits.any((s) => targets.contains(s.category));
  }
  return targets.contains(t.category);
}

bool _matchesUncategorized(Transaction t) {
  if (t.splits.isNotEmpty) {
    return t.splits.any((s) => s.category == null);
  }
  return t.category == null;
}

/// The history under [f], newest first, and its total, so the list and the
/// total always change together. Optionally matches [correctedDescriptions]
/// and supports incremental pagination via [offset] and [limit].
History history(
  Dataset data,
  TxFilter f, {
  Map<int, String>? correctedDescriptions,
  int offset = 0,
  int? limit,
}) {
  final rawSearch = f.search?.trim();
  final query = (rawSearch == null || rawSearch.isEmpty)
      ? null
      : normalizeText(rawSearch);
  final tagQuery = (f.tag == null || f.tag!.trim().isEmpty)
      ? null
      : normalizeText(f.tag!.trim());

  final matched = data.transactions.where((t) {
    if (f.from != null && t.date.isBefore(f.from!)) return false;
    if (f.to != null && !t.date.isBefore(f.to!)) return false;
    final acct = data.account(t.accountId);
    if (f.bankId != null && acct.bankId != f.bankId) {
      return false;
    }
    if (f.accountId != null && t.accountId != f.accountId) return false;
    if (f.spendingOnly && !isSpending(t)) return false;
    if (f.kind != null && t.kind != f.kind) return false;
    final hasCategories = f.categories != null && f.categories!.isNotEmpty;
    if (f.uncategorizedOnly && hasCategories) {
      if (!_matchesUncategorized(t) && !_matchesAnyCategory(t, f.categories!)) {
        return false;
      }
    } else if (f.uncategorizedOnly) {
      if (!_matchesUncategorized(t)) return false;
    } else {
      if (f.category != null && !_matchesCategory(t, f.category!)) {
        return false;
      }
      if (hasCategories && !_matchesAnyCategory(t, f.categories!)) {
        return false;
      }
    }
    if (f.essentiality != null && t.essentiality != f.essentiality) {
      return false;
    }
    if (f.paymentMethod != null &&
        inferPaymentMethod(t, acct) != f.paymentMethod) {
      return false;
    }
    if (tagQuery != null && !t.tags.any((tag) => normalizeText(tag) == tagQuery)) {
      return false;
    }
    if (f.atypicalOnly && !t.isAtypical) return false;
    if (query != null) {
      final originalMatches = normalizeText(t.description).contains(query);
      final corrected = correctedDescriptions?[t.id];
      final correctedMatches =
          corrected != null && normalizeText(corrected).contains(query);
      if (!originalMatches && !correctedMatches) return false;
    }
    return true;
  }).toList();

  final totalCents = matched.fold(0, (sum, t) => sum + t.amountCents);
  final sliced = (offset == 0 && limit == null)
      ? matched
      : matched
            .skip(offset)
            .take(limit ?? matched.length)
            .toList(growable: false);

  return (items: sliced, totalCents: totalCents);
}

typedef EffectiveHistory = ({
  List<EffectiveTransaction> items,
  int totalCents,
  int totalCount,
});

/// Filters effective transactions matching BOTH original and corrected
/// descriptions, keeping [totalCents] and [totalCount] aligned across the full
/// match while returning an optionally paginated slice.
EffectiveHistory effectiveHistory(
  Dataset data,
  List<EffectiveTransaction> effectiveTransactions,
  TxFilter f, {
  int offset = 0,
  int? limit,
}) {
  final rawSearch = f.search?.trim();
  final query = (rawSearch == null || rawSearch.isEmpty)
      ? null
      : normalizeText(rawSearch);
  final tagQuery = (f.tag == null || f.tag!.trim().isEmpty)
      ? null
      : normalizeText(f.tag!.trim());

  final matched = effectiveTransactions.where((t) {
    if (f.from != null && t.date.isBefore(f.from!)) return false;
    if (f.to != null && !t.date.isBefore(f.to!)) return false;
    if (f.bankId != null && data.account(t.accountId).bankId != f.bankId) {
      return false;
    }
    if (f.accountId != null && t.accountId != f.accountId) return false;
    if (f.spendingOnly && !isSpendingKind(t.kind)) return false;
    if (f.kind != null && t.kind != f.kind) return false;
    final hasCategories = f.categories != null && f.categories!.isNotEmpty;
    if (f.uncategorizedOnly && hasCategories) {
      final matches = t.splits.isNotEmpty
          ? t.splits.any(
              (s) => s.category == null || f.categories!.contains(s.category),
            )
          : (t.category == null || f.categories!.contains(t.category));
      if (!matches) return false;
    } else if (f.uncategorizedOnly) {
      final hasUncat = t.splits.isNotEmpty
          ? t.splits.any((s) => s.category == null)
          : t.category == null;
      if (!hasUncat) return false;
    } else {
      if (f.category != null) {
        final hasCat = t.splits.isNotEmpty
            ? t.splits.any((s) => s.category == f.category)
            : t.category == f.category;
        if (!hasCat) return false;
      }
      if (hasCategories) {
        final hasCat = t.splits.isNotEmpty
            ? t.splits.any((s) => f.categories!.contains(s.category))
            : f.categories!.contains(t.category);
        if (!hasCat) return false;
      }
    }
    if (f.essentiality != null) {
      final hasEss = t.splits.isNotEmpty
          ? t.splits.any(
              (s) => (s.essentiality ?? t.essentiality) == f.essentiality,
            )
          : t.essentiality == f.essentiality;
      if (!hasEss) return false;
    }
    if (f.paymentMethod != null && t.paymentMethod != f.paymentMethod) {
      return false;
    }
    if (tagQuery != null &&
        !t.tags.any((tag) => normalizeText(tag) == tagQuery)) {
      return false;
    }
    if (f.atypicalOnly && !t.isAtypical) return false;
    if (query != null) {
      final originalMatches = normalizeText(
        t.original.description,
      ).contains(query);
      final effectiveMatches = normalizeText(t.description).contains(query);
      final tagMatches = t.tags.any((tag) => normalizeText(tag).contains(query));
      final splitMatches = t.splits.any(
        (s) => normalizeText(s.description).contains(query),
      );
      if (!originalMatches &&
          !effectiveMatches &&
          !tagMatches &&
          !splitMatches) {
        return false;
      }
    }
    return true;
  }).toList();

  final totalCents = matched.fold(0, (sum, t) => sum + t.amountCents);
  final sliced = (offset == 0 && limit == null)
      ? matched
      : matched
            .skip(offset)
            .take(limit ?? matched.length)
            .toList(growable: false);

  return (items: sliced, totalCents: totalCents, totalCount: matched.length);
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', //
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', //
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', //
  'ç': 'c', 'ñ': 'n',
};

/// Case- and accent-insensitive normalization for pt-BR text search and rules.
String normalizeText(String s) =>
    s.toLowerCase().split('').map((c) => _accents[c] ?? c).join();

/// Normalized merchant key for grouping similar transactions (RF-26, RF-31).
String merchantKeyFor(String description) =>
    normalizeText(description).trim().replaceAll(RegExp(r'\s+'), ' ');

/// Display label for a spending category, rendering `null` as "Sem categoria"
/// (RF-31).
String spendingCategoryLabel(SpendingCategory? category) =>
    category?.label ?? 'Sem categoria';

/// One category's spending; [category] is `null` for uncategorized spending
/// ("Sem categoria", RF-31), and [share] is from 0 to 1 of the total.
typedef CategoryShare = ({SpendingCategory? category, int cents, double share});

/// RF-35, RF-31 & RN-24: categories by spending, largest first. Uncategorized
/// spending is kept explicitly under `null` ("Sem categoria") so it is never
/// silently dropped from monthly totals or merged into "Outros". Split
/// transactions allocate exact cents across each split's category.
List<CategoryShare> categoryRanking(Iterable<Transaction> transactions) {
  final totals = <SpendingCategory?, int>{};
  for (final t in transactions.where(isSpending)) {
    if (t.splits.isNotEmpty) {
      final sign = t.amountCents < 0 ? 1 : -1;
      for (final split in t.splits) {
        final category = split.category ?? t.category;
        totals[category] =
            (totals[category] ?? 0) + sign * split.amountCents.abs();
      }
    } else {
      final category = t.category;
      totals[category] = (totals[category] ?? 0) - t.amountCents;
    }
  }
  // A category refunded more than it spent has nothing to show.
  totals.removeWhere((_, cents) => cents <= 0);
  final total = totals.values.fold(0, (a, b) => a + b);
  if (total <= 0) return const [];
  return [
    for (final e in totals.entries)
      (category: e.key, cents: e.value, share: e.value / total),
  ]..sort(
    (a, b) => b.cents != a.cents
        ? b.cents - a.cents
        : (a.category?.index ?? 999) - (b.category?.index ?? 999),
  );
}

typedef Donut = ({List<CategoryShare> slices, int restCents, double restShare});

/// RF-34: the first [donutCategories] of a [categoryRanking] and the rest
/// summed into one slice. That slice is not the "Outros" category.
Donut categoryDonut(List<CategoryShare> ranking) {
  final rest = ranking.skip(donutCategories);
  return (
    slices: ranking.take(donutCategories).toList(),
    restCents: rest.fold(0, (sum, c) => sum + c.cents),
    restShare: rest.fold(0.0, (sum, c) => sum + c.share),
  );
}

/// One essentiality level's spending share for the Início stacked bar.
typedef EssentialityShare = ({
  Essentiality essentiality,
  int cents,
  double share,
});

/// Groups spending by essentiality in natural order (Essencial, Importante,
/// Flexível), accounting for transaction splits (RN-24).
List<EssentialityShare> essentialityBreakdown(
  Iterable<Transaction> transactions,
) {
  final totals = <Essentiality, int>{};
  for (final t in transactions.where(isSpending)) {
    if (t.splits.isNotEmpty) {
      final sign = t.amountCents < 0 ? 1 : -1;
      for (final split in t.splits) {
        final level = split.essentiality ?? t.essentiality;
        if (level == null) continue;
        totals[level] = (totals[level] ?? 0) + sign * split.amountCents.abs();
      }
    } else {
      final level = t.essentiality;
      if (level == null) continue;
      totals[level] = (totals[level] ?? 0) - t.amountCents;
    }
  }
  totals.removeWhere((_, cents) => cents <= 0);
  final total = totals.values.fold(0, (a, b) => a + b);
  if (total <= 0) return const [];
  return [
    for (final level in Essentiality.values)
      if (totals.containsKey(level))
        (
          essentiality: level,
          cents: totals[level]!,
          share: totals[level]! / total,
        ),
  ];
}

/// RF-20: derives open and closed bills for a credit card account, newest
/// month first, keeping purchases and installment labels intact.
List<CardBill> cardBills(Dataset data, String accountId) {
  final account = data.account(accountId);
  if (account.kind != AccountKind.creditCard) return const [];

  final closingDay = account.closingDay ?? 28;
  final dueDay = account.dueDay ?? 10;

  final byMonth = <(int, int), List<Transaction>>{};
  final paidMonths = <(int, int)>{};

  for (final t in data.transactions) {
    if (t.accountId != accountId) continue;
    if (isSpending(t)) {
      byMonth.putIfAbsent((t.date.year, t.date.month), () => []).add(t);
    } else if (t.kind == TxKind.billPayment && t.amountCents > 0) {
      // A bill payment in month M settles month M - 1.
      final settled = DateTime(t.date.year, t.date.month - 1);
      paidMonths.add((settled.year, settled.month));
    }
  }

  final keys = byMonth.keys.toList()
    ..sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2));

  return [
    for (final (year, month) in keys)
      CardBill(
        accountId: accountId,
        year: year,
        month: month,
        closingDate: DateTime(year, month, closingDay),
        dueDate: DateTime(year, month + 1, dueDay),
        totalCents: byMonth[(year, month)]!.fold(
          0,
          (sum, t) => sum - t.amountCents,
        ),
        isOpen:
            (year == data.today.year && month == data.today.month) ||
            !paidMonths.contains((year, month)),
        purchases: List.unmodifiable(byMonth[(year, month)]!),
      ),
  ];
}

/// RF-31: groups uncategorized expenses by normalized merchant name.
typedef ReviewQueueGroup = ({
  String merchantKey,
  String displayName,
  int count,
  int totalCents,
  List<Transaction> transactions,
});

List<ReviewQueueGroup> reviewQueue(Iterable<Transaction> transactions) {
  final groups = <String, List<Transaction>>{};
  for (final t in transactions) {
    if (t.kind == TxKind.expense && t.category == null && t.splits.isEmpty) {
      final key = merchantKeyFor(t.description);
      groups.putIfAbsent(key, () => []).add(t);
    }
  }
  return [
    for (final entry in groups.entries)
      (
        merchantKey: entry.key,
        displayName: entry.value.first.description,
        count: entry.value.length,
        totalCents: entry.value.fold(0, (sum, t) => sum - t.amountCents),
        transactions: List.unmodifiable(entry.value),
      ),
  ]..sort(
    (a, b) => b.count != a.count
        ? b.count - a.count
        : b.totalCents.compareTo(a.totalCents),
  );
}

SpendingCategory? _parseCategory(String? raw) {
  if (raw == null) return null;
  for (final c in SpendingCategory.values) {
    if (c.name == raw) return c;
  }
  return null;
}

Essentiality? _parseEssentiality(String? raw) {
  if (raw == null) return null;
  for (final e in Essentiality.values) {
    if (e.name == raw) return e;
  }
  return null;
}

TxKind? _parseTxKind(String? raw) {
  if (raw == null) return null;
  for (final k in TxKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}

PaymentMethod? _parsePaymentMethod(String? raw) {
  if (raw == null) return null;
  for (final p in PaymentMethod.values) {
    if (p.name == raw) return p;
  }
  return null;
}

/// Computes the set of adjustment IDs that have been undone by later records.
Set<String> undoneAdjustmentIds(List<TxAdjustment> adjustments) => {
  for (final a in adjustments)
    if (a.undoesId != null) a.undoesId!,
};

/// Returns the IDs of the latest active (non-undo, non-undone) manual
/// adjustment per [AdjustmentField] for [txId], matching the precedence order
/// applied by [resolveEffectiveTransactions].
Set<String> latestActiveAdjustmentIdsFor(
  int txId,
  List<TxAdjustment> adjustments,
) {
  final undone = undoneAdjustmentIds(adjustments);
  final latestByField = <AdjustmentField, String>{};
  for (final a in adjustments) {
    if (a.txId != txId || a.isUndo || undone.contains(a.id)) continue;
    latestByField[a.field] = a.id;
  }
  return latestByField.values.toSet();
}

/// Resolves effective transactions by layering:
/// 1. Manual [TxAdjustment] (highest precedence, never overwritten by rules)
/// 2. Active user rules ([RuleLayer.user])
/// 3. Active profile rules ([RuleLayer.profile])
/// 4. Original bank/system classification
List<EffectiveTransaction> resolveEffectiveTransactions({
  required List<Transaction> originals,
  required List<UserRule> rules,
  required List<TxAdjustment> adjustments,
  Map<String, Account>? accountsById,
  Map<int, List<TxSplit>>? splitsByTxId,
}) {
  final undone = undoneAdjustmentIds(adjustments);

  // Latest active (non-undo, non-undone) manual adjustment per (txId, field).
  final latestByTxField = <(int, AdjustmentField), TxAdjustment>{};
  for (final a in adjustments) {
    if (a.isUndo || undone.contains(a.id)) continue;
    latestByTxField[(a.txId, a.field)] = a;
  }

  final userRules = rules
      .where((r) => r.isActive && r.layer == RuleLayer.user)
      .toList(growable: false);
  final profileRules = rules
      .where((r) => r.isActive && r.layer == RuleLayer.profile)
      .toList(growable: false);

  UserRule? matchRule(
    List<UserRule> list,
    String merchantKey,
    bool Function(UserRule) hasField,
  ) {
    // Most recently added rule wins within the same layer.
    for (var i = list.length - 1; i >= 0; i--) {
      final r = list[i];
      if (!hasField(r)) continue;
      final ruleKey = merchantKeyFor(r.merchantKey);
      if (ruleKey.isNotEmpty && merchantKey.contains(ruleKey)) {
        return r;
      }
    }
    return null;
  }

  return [
    for (final t in originals)
      () {
        final key = merchantKeyFor(t.description);
        final descAdj = latestByTxField[(t.id, AdjustmentField.description)];
        final kindAdj = latestByTxField[(t.id, AdjustmentField.kind)];
        final catAdj = latestByTxField[(t.id, AdjustmentField.category)];
        final essAdj = latestByTxField[(t.id, AdjustmentField.essentiality)];
        final pmAdj = latestByTxField[(t.id, AdjustmentField.paymentMethod)];
        final tagsAdj = latestByTxField[(t.id, AdjustmentField.tags)];
        final atypicalAdj = latestByTxField[(t.id, AdjustmentField.atypical)];

        final adjustedFields = <AdjustmentField>{
          if (descAdj != null) AdjustmentField.description,
          if (kindAdj != null) AdjustmentField.kind,
          if (catAdj != null) AdjustmentField.category,
          if (essAdj != null) AdjustmentField.essentiality,
          if (pmAdj != null) AdjustmentField.paymentMethod,
          if (tagsAdj != null) AdjustmentField.tags,
          if (atypicalAdj != null) AdjustmentField.atypical,
        };

        final description = descAdj?.newValue ?? t.description;

        TxKind kind = t.kind;
        if (kindAdj != null) {
          kind = _parseTxKind(kindAdj.newValue) ?? t.kind;
        } else {
          final kindRule =
              matchRule(userRules, key, (r) => r.kind != null) ??
              matchRule(profileRules, key, (r) => r.kind != null);
          if (kindRule?.kind != null) {
            kind = kindRule!.kind!;
          }
        }

        SpendingCategory? category;
        ClassificationSource categorySource = ClassificationSource.systemRule;
        String? categoryRuleName;
        String? categoryRuleExplanation;

        Essentiality? essentiality;
        ClassificationSource essentialitySource =
            ClassificationSource.systemRule;
        String? essentialityRuleName;
        String? essentialityRuleExplanation;

        if (isSpendingKind(kind)) {
          if (catAdj != null) {
            category = _parseCategory(catAdj.newValue);
            categorySource = ClassificationSource.manual;
          } else {
            final userCat = matchRule(
              userRules,
              key,
              (r) => r.category != null,
            );
            if (userCat != null) {
              category = userCat.category;
              categorySource = ClassificationSource.userRule;
              categoryRuleName = userCat.name;
              categoryRuleExplanation = userCat.explanation;
            } else {
              final profCat = matchRule(
                profileRules,
                key,
                (r) => r.category != null,
              );
              if (profCat != null) {
                category = profCat.category;
                categorySource = ClassificationSource.profileRule;
                categoryRuleName = profCat.name;
                categoryRuleExplanation = profCat.explanation;
              } else {
                category = t.category;
                categorySource = ClassificationSource.systemRule;
              }
            }
          }

          if (essAdj != null) {
            essentiality = _parseEssentiality(essAdj.newValue);
            essentialitySource = ClassificationSource.manual;
          } else {
            final userEss = matchRule(
              userRules,
              key,
              (r) => r.essentiality != null,
            );
            if (userEss != null) {
              essentiality = userEss.essentiality;
              essentialitySource = ClassificationSource.userRule;
              essentialityRuleName = userEss.name;
              essentialityRuleExplanation = userEss.explanation;
            } else {
              final profEss = matchRule(
                profileRules,
                key,
                (r) => r.essentiality != null,
              );
              if (profEss != null) {
                essentiality = profEss.essentiality;
                essentialitySource = ClassificationSource.profileRule;
                essentialityRuleName = profEss.name;
                essentialityRuleExplanation = profEss.explanation;
              } else {
                essentiality = t.essentiality;
                essentialitySource = ClassificationSource.systemRule;
              }
            }
          }
        }

        final account = accountsById?[t.accountId];
        final paymentMethod = pmAdj != null
            ? (_parsePaymentMethod(pmAdj.newValue) ??
                  inferPaymentMethod(t, account))
            : inferPaymentMethod(t, account);

        final tags = tagsAdj != null ? decodeTags(tagsAdj.newValue) : t.tags;

        final isAtypical = atypicalAdj != null
            ? atypicalAdj.newValue == 'true'
            : t.isAtypical;

        final resolvedSplits =
            splitsByTxId != null && splitsByTxId.containsKey(t.id)
            ? List<TxSplit>.unmodifiable(splitsByTxId[t.id]!)
            : t.splits;

        return EffectiveTransaction(
          original: t,
          description: description,
          kind: kind,
          category: category,
          essentiality: essentiality,
          categorySource: categorySource,
          essentialitySource: essentialitySource,
          categoryRuleName: categoryRuleName,
          categoryRuleExplanation: categoryRuleExplanation,
          essentialityRuleName: essentialityRuleName,
          essentialityRuleExplanation: essentialityRuleExplanation,
          adjustedFields: adjustedFields,
          paymentMethod: paymentMethod,
          tags: tags,
          isAtypical: isAtypical,
          splits: resolvedSplits,
        );
      }(),
  ];
}

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

const _shortMonthNames = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez',
];

String formatMonthYear(DateTime month) =>
    '${_monthNames[month.month - 1]} ${month.year}';

String formatShortMonth(DateTime month) =>
    '${_shortMonthNames[month.month - 1]}/${month.year}';

String formatShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}';

String formatFullDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String formatPercent(double share, {int decimals = 1}) {
  final pct = share * 100;
  if (decimals == 0) {
    return '${pct.round()}%';
  }
  return '${pct.toStringAsFixed(decimals).replaceAll('.', ',')}%';
}
