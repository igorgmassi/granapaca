import 'dart:math';

/// A synthetic transaction. Amounts are in cents; negative means money out.
class DemoTransaction {
  const DemoTransaction(this.date, this.description, this.amountCents);

  final DateTime date;
  final String description;
  final int amountCents;
}

const _expenses = [
  'Mercado',
  'Padaria',
  'Farmácia',
  'Combustível',
  'Restaurante',
  'Streaming',
  'Conta de luz',
  'Transporte',
];

/// Builds the demo dataset. Fixed seed and fixed dates, so every run and
/// every platform shows the same fictitious data. No real data, no backend.
List<DemoTransaction> demoTransactions() {
  final random = Random(42);
  final start = DateTime(2026, 1, 31);
  final transactions = [
    DemoTransaction(DateTime(2026, 1, 5), 'Salário', 650000),
    for (var day = 0; day < 20; day++)
      DemoTransaction(
        start.subtract(Duration(days: day + random.nextInt(2))),
        _expenses[random.nextInt(_expenses.length)],
        -(1500 + random.nextInt(28500)),
      ),
  ];
  return transactions..sort((a, b) => b.date.compareTo(a.date));
}

/// Formats cents as Brazilian reais, e.g. -123456 -> "-R$ 1.234,56".
String formatBrl(int cents) {
  final abs = cents.abs();
  final reais = (abs ~/ 100)
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '.');
  final centavos = (abs % 100).toString().padLeft(2, '0');
  return '${cents < 0 ? '-' : ''}R\$ $reais,$centavos';
}
