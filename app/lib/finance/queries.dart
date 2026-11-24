// Pure functions behind Início, bank drilldowns, Extrato, Gastos, cards and
// rules classification. No widgets and no I/O, so the server can compute the
// same totals later.

import 'model.dart';
import 'taxonomy.dart';

bool isSpendingKind(TxKind kind) =>
    kind == TxKind.expense || kind == TxKind.refund;

bool isSpending(Transaction t) => isSpendingKind(t.kind);

bool isIncome(Transaction t) => t.kind == TxKind.income;

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
/// apart. Spent and received only count [isSpending] and [isIncome] in [month].
Summary summary(Dataset data, DateTime month, {String? bankId}) {
  bool ofBank(String accountId) =>
      bankId == null || data.account(accountId).bankId == bankId;

  var balance = 0, cardBill = 0, spent = 0, received = 0;
  for (final a in data.accounts.where((a) => ofBank(a.id))) {
    final cents = accountBalanceCents(data, a);
    if (a.kind == AccountKind.creditCard) {
      cardBill -= cents;
    } else {
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

/// Filters of the history (RF-18). Every field is optional and they combine.
/// The period is [from] inclusive to [to] exclusive.
class TxFilter {
  const TxFilter({
    this.from,
    this.to,
    this.bankId,
    this.accountId,
    this.kind,
    this.category,
    this.essentiality,
    this.search,
    this.spendingOnly = false,
  });

  final DateTime? from;
  final DateTime? to;
  final String? bankId;
  final String? accountId;
  final TxKind? kind;
  final SpendingCategory? category;
  final Essentiality? essentiality;

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
      essentiality != null ||
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
    Essentiality? essentiality,
    bool clearEssentiality = false,
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
    essentiality: clearEssentiality
        ? null
        : (essentiality ?? this.essentiality),
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
  final matched = data.transactions.where((t) {
    if (f.from != null && t.date.isBefore(f.from!)) return false;
    if (f.to != null && !t.date.isBefore(f.to!)) return false;
    if (f.bankId != null && data.account(t.accountId).bankId != f.bankId) {
      return false;
    }
    if (f.accountId != null && t.accountId != f.accountId) return false;
    if (f.spendingOnly && !isSpending(t)) return false;
    if (f.kind != null && t.kind != f.kind) return false;
    if (f.category != null && t.category != f.category) return false;
    if (f.essentiality != null && t.essentiality != f.essentiality) {
      return false;
    }
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
  final matched = effectiveTransactions.where((t) {
    if (f.from != null && t.date.isBefore(f.from!)) return false;
    if (f.to != null && !t.date.isBefore(f.to!)) return false;
    if (f.bankId != null && data.account(t.accountId).bankId != f.bankId) {
      return false;
    }
    if (f.accountId != null && t.accountId != f.accountId) return false;
    if (f.spendingOnly && !isSpendingKind(t.kind)) return false;
    if (f.kind != null && t.kind != f.kind) return false;
    if (f.category != null && t.category != f.category) return false;
    if (f.essentiality != null && t.essentiality != f.essentiality) {
      return false;
    }
    if (query != null) {
      final originalMatches = normalizeText(
        t.original.description,
      ).contains(query);
      final effectiveMatches = normalizeText(t.description).contains(query);
      if (!originalMatches && !effectiveMatches) return false;
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

/// One category's spending; [share] is from 0 to 1 of the total.
typedef CategoryShare = ({SpendingCategory category, int cents, double share});

/// RF-35: categories by spending, largest first. Non-spending transactions
/// are ignored, so it can take a whole history.
List<CategoryShare> categoryRanking(Iterable<Transaction> transactions) {
  final totals = <SpendingCategory, int>{};
  for (final t in transactions.where(isSpending)) {
    final category = t.category ?? SpendingCategory.other;
    totals[category] = (totals[category] ?? 0) - t.amountCents;
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
        : a.category.index - b.category.index,
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
/// Flexível).
List<EssentialityShare> essentialityBreakdown(
  Iterable<Transaction> transactions,
) {
  final totals = <Essentiality, int>{};
  for (final t in transactions.where(isSpending)) {
    final level = t.essentiality;
    if (level == null) continue;
    totals[level] = (totals[level] ?? 0) - t.amountCents;
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
    if (t.kind == TxKind.expense && t.category == null) {
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

/// Computes the set of adjustment IDs that have been undone by later records.
Set<String> undoneAdjustmentIds(List<TxAdjustment> adjustments) => {
  for (final a in adjustments)
    if (a.undoesId != null) a.undoesId!,
};

/// Resolves effective transactions by layering:
/// 1. Manual [TxAdjustment] (highest precedence, never overwritten by rules)
/// 2. Active user rules ([RuleLayer.user])
/// 3. Active profile rules ([RuleLayer.profile])
/// 4. Original bank/system classification
List<EffectiveTransaction> resolveEffectiveTransactions({
  required List<Transaction> originals,
  required List<UserRule> rules,
  required List<TxAdjustment> adjustments,
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

        final adjustedFields = <AdjustmentField>{
          if (descAdj != null) AdjustmentField.description,
          if (kindAdj != null) AdjustmentField.kind,
          if (catAdj != null) AdjustmentField.category,
          if (essAdj != null) AdjustmentField.essentiality,
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
