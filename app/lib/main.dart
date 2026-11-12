import 'package:material_ui/material_ui.dart';

import 'demo/demo_data.dart';

void main() {
  runApp(const GranaPaCaApp());
}

class GranaPaCaApp extends StatelessWidget {
  const GranaPaCaApp({super.key});

  // Neutral Material 3 theme; the design tokens replace it in issue #12.
  static ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blueGrey,
      brightness: brightness,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GranaPaCá',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: DemoHomePage(transactions: demoTransactions()),
    );
  }
}

class DemoHomePage extends StatelessWidget {
  const DemoHomePage({super.key, required this.transactions});

  final List<DemoTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final balance = transactions.fold(0, (sum, t) => sum + t.amountCents);

    return Scaffold(
      appBar: AppBar(title: const Text('GranaPaCá')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: colors.tertiaryContainer,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Modo demonstração: todos os dados são fictícios.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo do mês', style: text.labelLarge),
                Text(formatBrl(balance), style: text.headlineMedium),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: transactions.length,
              itemBuilder: (context, i) {
                final t = transactions[i];
                return ListTile(
                  title: Text(t.description),
                  subtitle: Text(
                    '${t.date.day.toString().padLeft(2, '0')}/'
                    '${t.date.month.toString().padLeft(2, '0')}',
                  ),
                  trailing: Text(formatBrl(t.amountCents)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
