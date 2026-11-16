import 'package:flutter_test/flutter_test.dart';

import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/queries.dart';
import 'package:granapaca/finance/taxonomy.dart';

// A tiny month where the same money moves around several times.
Dataset _month() {
  var id = 0;
  Transaction tx(
    String account,
    int day,
    String description,
    int cents,
    TxKind kind, [
    SpendingCategory? category,
    Essentiality? essentiality,
  ]) => Transaction(
    id: id++,
    accountId: account,
    date: DateTime(2026, 3, day),
    description: description,
    amountCents: cents,
    kind: kind,
    category: category,
    essentiality: essentiality,
  );

  return Dataset(
    banks: const [Bank('a', 'Banco A'), Bank('b', 'Banco B')],
    accounts: const [
      Account(
        id: 'a-cc',
        bankId: 'a',
        name: 'CC',
        kind: AccountKind.checking,
        openingBalanceCents: 10000,
      ),
      Account(
        id: 'a-card',
        bankId: 'a',
        name: 'Cartão',
        kind: AccountKind.creditCard,
      ),
      Account(id: 'b-cc', bankId: 'b', name: 'CC', kind: AccountKind.checking),
    ],
    transactions: [
      tx('a-cc', 1, 'Salário', 500000, TxKind.income),
      tx('a-cc', 2, 'Pix para B', -100000, TxKind.ownTransfer),
      tx('b-cc', 2, 'Pix de A', 100000, TxKind.ownTransfer),
      tx(
        'a-card',
        3,
        'Farmácia Central',
        -3000,
        TxKind.expense,
        SpendingCategory.health,
        Essentiality.essential,
      ),
      tx(
        'a-card',
        4,
        'Restaurante',
        -7000,
        TxKind.expense,
        SpendingCategory.food,
        Essentiality.superfluous,
      ),
      tx('a-cc', 10, 'Pagamento da fatura', -10000, TxKind.billPayment),
      tx('a-card', 10, 'Pagamento recebido', 10000, TxKind.billPayment),
      tx(
        'b-cc',
        12,
        'Aluguel',
        -80000,
        TxKind.expense,
        SpendingCategory.housing,
        Essentiality.essential,
      ),
      tx('b-cc', 13, 'Saque', -5000, TxKind.cashWithdrawal),
      tx('a-cc', 14, 'Aplicação', -50000, TxKind.investment),
      tx(
        'a-card',
        20,
        'Mercado',
        -2000,
        TxKind.expense,
        SpendingCategory.food,
        Essentiality.essential,
      ),
      tx(
        'a-cc',
        31,
        'Mercado do dia 31',
        -1,
        TxKind.expense,
        SpendingCategory.food,
        Essentiality.essential,
      ),
    ],
    today: DateTime(2026, 3, 20),
  );
}

int _sumCents(Iterable<CategoryShare> c) => c.fold(0, (s, x) => s + x.cents);

double _sumShare(Iterable<CategoryShare> c) =>
    c.fold(0.0, (s, x) => s + x.share);

void main() {
  final data = _month();
  final march = DateTime(2026, 3);

  group('summary', () {
    test('counts each real in or out once', () {
      final s = summary(data, march);
      // Card purchases and the rent count; the transfers, the bill payment,
      // the withdrawal and the investment do not.
      expect(s.spentCents, 3000 + 7000 + 80000 + 2000 + 1);
      expect(s.receivedCents, 500000);
      expect(s.leftoverCents, 500000 - 92001);
    });

    test('keeps the open card bill apart from the balance', () {
      final s = summary(data, march);
      expect(s.cardBillCents, 2000);
      expect(
        s.balanceCents,
        10000 + 500000 - 100000 - 10000 - 50000 - 1 + 100000 - 80000 - 5000,
      );
    });

    test('splits by bank and the banks add up to the whole', () {
      final a = summary(data, march, bankId: 'a');
      final b = summary(data, march, bankId: 'b');
      expect(b.spentCents, 80000);
      expect(b.receivedCents, 0);
      expect(b.cardBillCents, 0);
      final all = summary(data, march);
      expect(a.balanceCents + b.balanceCents, all.balanceCents);
      expect(a.spentCents + b.spentCents, all.spentCents);
      expect(a.receivedCents + b.receivedCents, all.receivedCents);
    });

    test('ignores other months', () {
      expect(summary(data, DateTime(2026, 4)).spentCents, 0);
      expect(summary(data, DateTime(2026, 4)).receivedCents, 0);
    });
  });

  group('history', () {
    test('without filters lists everything, newest first', () {
      final h = history(data, const TxFilter());
      expect(h.items.length, data.transactions.length);
      expect(h.items.first.description, 'Mercado do dia 31');
    });

    test('filters combine and the total follows the list', () {
      final h = history(
        data,
        const TxFilter(
          bankId: 'a',
          kind: TxKind.expense,
          category: SpendingCategory.food,
        ),
      );
      expect(h.items.map((t) => t.description), [
        'Mercado do dia 31',
        'Mercado',
        'Restaurante',
      ]);
      expect(h.totalCents, -9001);
    });

    test('period is from inclusive to exclusive', () {
      final h = history(
        data,
        TxFilter(from: DateTime(2026, 3, 10), to: DateTime(2026, 3, 12)),
      );
      expect(h.items.map((t) => t.description), [
        'Pagamento recebido',
        'Pagamento da fatura',
      ]);
    });

    test('filters by account and essentiality', () {
      final h = history(
        data,
        const TxFilter(
          accountId: 'a-card',
          essentiality: Essentiality.essential,
        ),
      );
      expect(h.items.map((t) => t.description), [
        'Mercado',
        'Farmácia Central',
      ]);
    });

    test('search ignores case and accents', () {
      expect(
        history(data, const TxFilter(search: 'FARMACIA')).items.single.id,
        3,
      );
      expect(
        history(data, const TxFilter(search: 'aplicacao')).items.single.id,
        9,
      );
    });

    test('a filter with no match is empty with a zero total', () {
      final h = history(data, const TxFilter(search: 'nada disso'));
      expect(h.items, isEmpty);
      expect(h.totalCents, 0);
    });
  });

  group('categories', () {
    test('ranking only counts spending, largest first', () {
      final r = categoryRanking(data.transactions);
      expect(r.map((c) => c.category), [
        SpendingCategory.housing,
        SpendingCategory.food,
        SpendingCategory.health,
      ]);
      expect(r.map((c) => c.cents), [80000, 9001, 3000]);
      expect(_sumShare(r), closeTo(1, 1e-9));
    });

    test('ranking of a period without spending is empty', () {
      final (from, to) = monthRange(DateTime(2026, 5));
      final h = history(data, spendingFilter(from, to));
      expect(categoryRanking(h.items), isEmpty);
      expect(categoryDonut(categoryRanking(h.items)).slices, isEmpty);
    });

    test('a refund lowers its category', () {
      final refund = Transaction(
        id: 99,
        accountId: 'a-card',
        date: DateTime(2026, 3, 21),
        description: 'Estorno',
        amountCents: 1000,
        kind: TxKind.expense,
        category: SpendingCategory.health,
      );
      expect(categoryRanking([...data.transactions, refund]).last.cents, 2000);
    });

    test('donut keeps the top categories and sums the rest', () {
      final ranking = [
        for (final (i, c) in SpendingCategory.values.indexed)
          (category: c, cents: 900 - i * 100, share: (900 - i * 100) / 4500),
      ];
      final d = categoryDonut(ranking);
      expect(d.slices.length, donutCategories);
      expect(d.slices.first.category, SpendingCategory.housing);
      expect(d.restCents + _sumCents(d.slices), 4500);
      expect(d.restShare + _sumShare(d.slices), closeTo(1, 1e-9));
    });

    test('donut with few categories has no rest', () {
      final d = categoryDonut(categoryRanking(data.transactions));
      expect(d.slices.length, 3);
      expect(d.restCents, 0);
    });
  });

  group('Gastos filter', () {
    test('charts match the history under the same filters', () {
      final (from, to) = monthRange(march);
      final h = history(data, spendingFilter(from, to, bankId: 'a'));
      expect(_sumCents(categoryRanking(h.items)), -h.totalCents);
      expect(-h.totalCents, summary(data, march, bankId: 'a').spentCents);
    });

    test('by account narrows to that account', () {
      final (from, to) = monthRange(march);
      final h = history(data, spendingFilter(from, to, accountId: 'b-cc'));
      expect(h.items.single.description, 'Aluguel');
    });
  });
}
