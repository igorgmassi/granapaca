// Pure functions behind Início, the bank sections, the history and Gastos.
// No widgets and no I/O, so the server can compute the same totals later.

import 'model.dart';
import 'taxonomy.dart';

bool isSpending(Transaction t) => t.kind == TxKind.expense;

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

/// RF-16 and RF-17: all accounts, or one bank with [bankId].
/// The balance adds checking and savings accounts; the open card bill comes
/// apart [Suposição]. Spent and received only count [isSpending] and
/// [isIncome] in [month].
Summary summary(Dataset data, DateTime month, {String? bankId}) {
  bool ofBank(String accountId) =>
      bankId == null || data.account(accountId).bankId == bankId;

  var balance = 0, cardBill = 0, spent = 0, received = 0;
  for (final a in data.accounts.where((a) => ofBank(a.id))) {
    final cents = data.transactions
        .where((t) => t.accountId == a.id)
        .fold(a.openingBalanceCents, (sum, t) => sum + t.amountCents);
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
  });

  final DateTime? from;
  final DateTime? to;
  final String? bankId;
  final String? accountId;
  final TxKind? kind;
  final SpendingCategory? category;
  final Essentiality? essentiality;

  /// Matches the description ignoring case and accents.
  final String? search;
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
  kind: TxKind.expense,
);

typedef History = ({List<Transaction> items, int totalCents});

/// The history under [f], newest first, and its total, so the list and the
/// total always change together.
// shortcut: no paging and no corrected description yet; both arrive with the
// server (RNF-16) and with RF-19.
History history(Dataset data, TxFilter f) {
  final query = f.search == null ? null : _fold(f.search!);
  final items = data.transactions
      .where(
        (t) =>
            (f.from == null || !t.date.isBefore(f.from!)) &&
            (f.to == null || t.date.isBefore(f.to!)) &&
            (f.bankId == null ||
                data.account(t.accountId).bankId == f.bankId) &&
            (f.accountId == null || t.accountId == f.accountId) &&
            (f.kind == null || t.kind == f.kind) &&
            (f.category == null || t.category == f.category) &&
            (f.essentiality == null || t.essentiality == f.essentiality) &&
            (query == null || _fold(t.description).contains(query)),
      )
      .toList();
  return (
    items: items,
    totalCents: items.fold(0, (sum, t) => sum + t.amountCents),
  );
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i', //
  'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ü': 'u', 'ç': 'c',
};

String _fold(String s) =>
    s.toLowerCase().split('').map((c) => _accents[c] ?? c).join();

/// One category's spending; [share] is from 0 to 1 of the total.
typedef CategoryShare = ({SpendingCategory category, int cents, double share});

/// RF-35: categories by spending, largest first. Non-spending transactions
/// are ignored, so it can take a whole history.
List<CategoryShare> categoryRanking(Iterable<Transaction> transactions) {
  final totals = <SpendingCategory, int>{};
  for (final t in transactions.where(isSpending)) {
    totals[t.category!] = (totals[t.category!] ?? 0) - t.amountCents;
  }
  // A category refunded more than it spent has nothing to show.
  totals.removeWhere((_, cents) => cents <= 0);
  final total = totals.values.fold(0, (a, b) => a + b);
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
