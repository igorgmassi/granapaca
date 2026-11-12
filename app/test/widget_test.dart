import 'package:flutter_test/flutter_test.dart';

import 'package:granapaca/demo/demo_data.dart';
import 'package:granapaca/main.dart';

void main() {
  testWidgets('opens in demo mode with synthetic data', (tester) async {
    await tester.pumpWidget(const GranaPaCaApp());

    expect(find.textContaining('Modo demonstração'), findsOneWidget);
    expect(find.text('Saldo do mês'), findsOneWidget);
    expect(find.text(r'R$ 3.583,91'), findsOneWidget);
  });

  // Pinned values: if the generator changes, every screenshot and doc changes too.
  test('demo data is deterministic', () {
    final t = demoTransactions();
    expect(t.length, 21);
    expect(t.fold(0, (sum, x) => sum + x.amountCents), 358391);
    expect(t.first.date, DateTime(2026, 1, 30));
    expect(t.first.description, 'Conta de luz');
  });

  test('formats reais in pt-BR', () {
    expect(formatBrl(0), r'R$ 0,00');
    expect(formatBrl(650000), r'R$ 6.500,00');
    expect(formatBrl(-123456789), r'-R$ 1.234.567,89');
  });
}
