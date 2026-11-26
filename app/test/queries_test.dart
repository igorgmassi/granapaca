import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:granapaca/demo/demo_data.dart';
import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/queries.dart';
import 'package:granapaca/finance/taxonomy.dart';
import 'package:granapaca/state/preferences_store_io.dart';

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
        Essentiality.flexible,
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

    test('filters by a set of categories and preserves copyWith', () {
      const filter = TxFilter(
        categories: {SpendingCategory.health, SpendingCategory.housing},
      );
      expect(filter.hasActiveFilters, isTrue);

      final h = history(data, filter);
      expect(h.items.map((t) => t.description), [
        'Aluguel',
        'Farmácia Central',
      ]);
      expect(h.totalCents, -83000);

      final resolved = resolveEffectiveTransactions(
        originals: data.transactions,
        rules: const [],
        adjustments: const [],
      );
      final eh = effectiveHistory(data, resolved, filter);
      expect(eh.items.map((t) => t.description), [
        'Aluguel',
        'Farmácia Central',
      ]);
      expect(eh.totalCents, -83000);

      final cleared = filter.copyWith(clearCategories: true);
      expect(cleared.categories, isNull);
      expect(cleared.hasActiveFilters, isFalse);
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

  group('taxonomy and movement labels', () {
    test('exposes judgment-free essentiality labels', () {
      expect(Essentiality.values.map((e) => e.label), [
        'Essencial',
        'Importante',
        'Flexível',
      ]);
    });

    test('exposes written pt-BR labels for all 8 movement types (RF-19)', () {
      expect(TxKind.expense.label, 'Gasto');
      expect(TxKind.income.label, 'Receita');
      expect(TxKind.ownTransfer.label, 'Transferência própria');
      expect(TxKind.billPayment.label, 'Pagamento de fatura');
      expect(TxKind.refund.label, 'Estorno');
      expect(TxKind.investment.label, 'Aplicação');
      expect(TxKind.redemption.label, 'Resgate');
      expect(TxKind.cashWithdrawal.label, 'Saque');
    });
  });

  group('refund and redemption', () {
    test('TxKind.refund lowers spending without counting as income', () {
      final withRefund = Dataset(
        banks: data.banks,
        accounts: data.accounts,
        today: data.today,
        transactions: [
          ...data.transactions,
          Transaction(
            id: 200,
            accountId: 'a-card',
            date: DateTime(2026, 3, 22),
            description: 'Estorno farmácia',
            amountCents: 1500,
            kind: TxKind.refund,
            category: SpendingCategory.health,
            essentiality: Essentiality.essential,
          ),
          Transaction(
            id: 201,
            accountId: 'a-cc',
            date: DateTime(2026, 3, 23),
            description: 'Resgate CDB',
            amountCents: 20000,
            kind: TxKind.redemption,
          ),
        ],
      );
      final s = summary(withRefund, march);
      // Refund reduces spent by 1500; redemption adds to neither income nor spending.
      expect(s.spentCents, 92001 - 1500);
      expect(s.receivedCents, 500000);

      final healthShare = categoryRanking(
        withRefund.transactions,
      ).firstWhere((c) => c.category == SpendingCategory.health);
      expect(healthShare.cents, 1500);

      final (from, to) = monthRange(march);
      final h = history(withRefund, spendingFilter(from, to));
      expect(-h.totalCents, s.spentCents);
    });
  });

  group('essentialityBreakdown', () {
    test('computes shares in natural order summing to 1', () {
      final shares = essentialityBreakdown(data.transactions);
      expect(shares.map((s) => s.essentiality), [
        Essentiality.essential,
        Essentiality.flexible,
      ]);
      expect(shares.first.cents, 85001);
      expect(shares.last.cents, 7000);
      expect(shares.fold(0.0, (s, x) => s + x.share), closeTo(1.0, 1e-9));
    });
  });

  group('cardBills (RF-20)', () {
    test('derives open and closed bills with installments on demo card', () {
      final demo = demoDataset();
      final bills = cardBills(demo, 'aurora-card');
      expect(bills.length, 3);

      final marchBill = bills[0];
      expect(marchBill.year, 2026);
      expect(marchBill.month, 3);
      expect(marchBill.isOpen, isTrue);
      expect(marchBill.totalCents, 198380);
      expect(marchBill.closingDate, DateTime(2026, 3, 28));
      expect(marchBill.dueDate, DateTime(2026, 4, 10));
      expect(
        marchBill.purchases.any(
          (p) => p.installment == 5 && p.installmentCount == 10,
        ),
        isTrue,
      );

      expect(bills[1].month, 2);
      expect(bills[1].isOpen, isFalse);
      expect(
        bills[1].purchases.any(
          (p) => p.installment == 4 && p.installmentCount == 10,
        ),
        isTrue,
      );

      expect(bills[2].month, 1);
      expect(bills[2].isOpen, isFalse);
      expect(
        bills[2].purchases.any(
          (p) => p.installment == 3 && p.installmentCount == 10,
        ),
        isTrue,
      );
    });
  });

  group('reviewQueue (RF-31)', () {
    test('groups uncategorized expenses by normalized merchant name', () {
      final txs = [
        Transaction(
          id: 1,
          accountId: 'a-cc',
          date: DateTime(2026, 3, 5),
          description: 'Café Central',
          amountCents: -1200,
          kind: TxKind.expense,
        ),
        Transaction(
          id: 2,
          accountId: 'a-cc',
          date: DateTime(2026, 3, 8),
          description: '  CAFE   central ',
          amountCents: -1800,
          kind: TxKind.expense,
        ),
        Transaction(
          id: 3,
          accountId: 'a-cc',
          date: DateTime(2026, 3, 9),
          description: 'Banca da Praça',
          amountCents: -900,
          kind: TxKind.expense,
        ),
        Transaction(
          id: 4,
          accountId: 'a-cc',
          date: DateTime(2026, 3, 10),
          description: 'Já categorizado',
          amountCents: -5000,
          kind: TxKind.expense,
          category: SpendingCategory.food,
        ),
      ];
      final queue = reviewQueue(txs);
      expect(queue.length, 2);
      expect(queue.first.merchantKey, 'cafe central');
      expect(queue.first.count, 2);
      expect(queue.first.totalCents, 3000);
      expect(queue.last.count, 1);
    });
  });

  group('effective transactions, rules and append-only adjustments', () {
    test('enforces manual > user rule > profile rule > system precedence', () {
      final originals = data.transactions;
      final profileRule = const UserRule(
        id: 'p1',
        merchantKey: 'restaurante',
        name: 'Perfil',
        explanation: 'Teste perfil',
        essentiality: Essentiality.important,
        layer: RuleLayer.profile,
      );
      final userRule = const UserRule(
        id: 'u1',
        merchantKey: 'restaurante',
        name: 'Usuário',
        explanation: 'Teste usuário',
        category: SpendingCategory.leisure,
        essentiality: Essentiality.essential,
        layer: RuleLayer.user,
      );
      // Transaction id 4 is 'Restaurante' (originally food, flexible).
      final manualCat = TxAdjustment(
        id: 'adj-1',
        txId: 4,
        field: AdjustmentField.category,
        oldValue: SpendingCategory.food.name,
        newValue: SpendingCategory.shopping.name,
        timestamp: DateTime(2026, 3, 25),
      );

      final resolved = resolveEffectiveTransactions(
        originals: originals,
        rules: [profileRule, userRule],
        adjustments: [manualCat],
      );
      final rest = resolved.firstWhere((t) => t.id == 4);
      // Category came from manual adjustment (wins over user rule),
      // while essentiality independently came from user rule (wins over profile).
      expect(rest.category, SpendingCategory.shopping);
      expect(rest.categorySource, ClassificationSource.manual);
      expect(rest.essentiality, Essentiality.essential);
      expect(rest.essentialitySource, ClassificationSource.userRule);

      // Undoing adj-1 appends a new record and restores user rule for category.
      final undoAdj = TxAdjustment(
        id: 'adj-2',
        txId: 4,
        field: AdjustmentField.category,
        oldValue: SpendingCategory.shopping.name,
        newValue: SpendingCategory.food.name,
        timestamp: DateTime(2026, 3, 26),
        undoesId: 'adj-1',
      );
      final afterUndo = resolveEffectiveTransactions(
        originals: originals,
        rules: [profileRule, userRule],
        adjustments: [manualCat, undoAdj],
      ).firstWhere((t) => t.id == 4);
      expect(afterUndo.category, SpendingCategory.leisure);
      expect(afterUndo.categorySource, ClassificationSource.userRule);
      expect(afterUndo.hasManualAdjustments, isFalse);
    });

    test('effectiveHistory searches original and corrected description and paginates', () {
      final manualDesc = TxAdjustment(
        id: 'adj-d1',
        txId: 4,
        field: AdjustmentField.description,
        oldValue: 'Restaurante',
        newValue: 'Almoço da Equipe',
        timestamp: DateTime(2026, 3, 25),
      );
      final resolved = resolveEffectiveTransactions(
        originals: data.transactions,
        rules: const [],
        adjustments: [manualDesc],
      );
      expect(
        effectiveHistory(
          data,
          resolved,
          const TxFilter(search: 'ALMOCO'),
        ).items.single.id,
        4,
      );
      expect(
        effectiveHistory(
          data,
          resolved,
          const TxFilter(search: 'restaurante'),
        ).items.single.id,
        4,
      );

      final paged = effectiveHistory(
        data,
        resolved,
        const TxFilter(),
        offset: 0,
        limit: 5,
      );
      expect(paged.items.length, 5);
      expect(paged.totalCount, data.transactions.length);
      expect(
        paged.totalCents,
        data.transactions.fold(0, (s, t) => s + t.amountCents),
      );
    });

    test('latestActiveAdjustmentIdsFor tracks the latest active record per field', () {
      final adj1 = TxAdjustment(
        id: 'adj-1',
        txId: 4,
        field: AdjustmentField.category,
        oldValue: SpendingCategory.food.name,
        newValue: SpendingCategory.leisure.name,
        timestamp: DateTime(2026, 3, 25),
      );
      final adj2 = TxAdjustment(
        id: 'adj-2',
        txId: 4,
        field: AdjustmentField.category,
        oldValue: SpendingCategory.leisure.name,
        newValue: SpendingCategory.health.name,
        timestamp: DateTime(2026, 3, 26),
      );
      final adj3 = TxAdjustment(
        id: 'adj-3',
        txId: 4,
        field: AdjustmentField.description,
        oldValue: 'Restaurante',
        newValue: 'Jantar',
        timestamp: DateTime(2026, 3, 26),
      );
      expect(latestActiveAdjustmentIdsFor(4, [adj1, adj2, adj3]), {
        'adj-2',
        'adj-3',
      });

      final undo2 = TxAdjustment(
        id: 'adj-4',
        txId: 4,
        field: AdjustmentField.category,
        oldValue: SpendingCategory.health.name,
        newValue: SpendingCategory.leisure.name,
        timestamp: DateTime(2026, 3, 27),
        undoesId: 'adj-2',
      );
      expect(latestActiveAdjustmentIdsFor(4, [adj1, adj2, adj3, undo2]), {
        'adj-1',
        'adj-3',
      });
    });
  });

  group('FilePreferencesStore', () {
    test('persists hideValues and themeMode across instances', () async {
      final dir = Directory.systemTemp.createTempSync('granapaca_prefs_test_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final file = File('${dir.path}/prefs.json');
      final store1 = FilePreferencesStore(file);
      expect(store1.readHideValues(), isFalse);
      expect(store1.readThemeMode(), ThemeMode.system);

      await store1.writeHideValues(true);
      await store1.writeThemeMode(ThemeMode.dark);

      final store2 = FilePreferencesStore(file);
      expect(store2.readHideValues(), isTrue);
      expect(store2.readThemeMode(), ThemeMode.dark);
    });
  });
}
