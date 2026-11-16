import 'package:flutter_test/flutter_test.dart';

import 'package:granapaca/demo/demo_data.dart';
import 'package:granapaca/finance/model.dart';
import 'package:granapaca/finance/queries.dart';
import 'package:granapaca/main.dart';

void main() {
  testWidgets('opens in demo mode with synthetic data', (tester) async {
    await tester.pumpWidget(const GranaPaCaApp());

    expect(find.textContaining('Modo demonstração'), findsOneWidget);
    expect(find.text('Saldo do mês'), findsOneWidget);
    expect(find.text(r'R$ 2.881,82'), findsOneWidget);
  });

  // Pinned values: if the dataset changes, every screenshot and doc changes
  // too. The web must produce the same numbers as the VM.
  test('demo data is deterministic', () {
    final d = demoDataset();
    final t = d.transactions;
    expect(t.length, 72);
    expect(t.fold(0, (sum, x) => sum + x.amountCents), 538901);
    expect(t.first.date, DateTime(2026, 3, 27));
    expect(t.first.description, 'Padaria Pão de Ontem');
    expect(summary(d, d.today), (
      balanceCents: 2594281,
      spentCents: 416818,
      receivedCents: 705000,
      leftoverCents: 288182,
      cardBillCents: 198380,
    ));
  });

  test('demo data covers what the Phase 1 screens need', () {
    final d = demoDataset();
    final t = d.transactions;
    expect(d.banks.length, greaterThan(1));
    for (final kind in TxKind.values) {
      expect(t.any((x) => x.kind == kind), isTrue, reason: '$kind');
    }
    expect(t.any((x) => x.installment != null), isTrue);
    expect(t.map((x) => DateTime(x.date.year, x.date.month)).toSet(), {
      DateTime(2026, 1),
      DateTime(2026, 2),
      DateTime(2026, 3),
    });
    for (final x in t) {
      expect(x.essentiality != null, isSpending(x), reason: x.description);
      expect(x.category != null, isSpending(x), reason: x.description);
    }
  });

  test('each bill payment pays the previous month of card purchases', () {
    final d = demoDataset();
    for (final m in [2, 3]) {
      final (bf, bt) = monthRange(DateTime(2026, m - 1));
      final (pf, pt) = monthRange(DateTime(2026, m));
      final bought = history(
        d,
        TxFilter(
          from: bf,
          to: bt,
          accountId: 'aurora-card',
          kind: TxKind.expense,
        ),
      );
      final paid = history(
        d,
        TxFilter(
          from: pf,
          to: pt,
          accountId: 'aurora-cc',
          kind: TxKind.billPayment,
        ),
      );
      expect(paid.totalCents, bought.totalCents);
    }
  });

  test('formats reais in pt-BR', () {
    expect(formatBrl(0), r'R$ 0,00');
    expect(formatBrl(650000), r'R$ 6.500,00');
    expect(formatBrl(-123456789), r'-R$ 1.234.567,89');
  });
}
