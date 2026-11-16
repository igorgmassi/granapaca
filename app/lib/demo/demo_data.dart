import '../finance/model.dart';
import '../finance/taxonomy.dart';

// [Suposição, P4] A fictitious person: two made-up banks, three months of
// 2026, no real data. Built from fixed tables and integer arithmetic only
// (no Random, no clock), so every run and every platform, web included,
// gets the very same data.

const _food = SpendingCategory.food;
const _essential = Essentiality.essential;
const _important = Essentiality.important;
const _superfluous = Essentiality.superfluous;

/// Card purchases repeated every month: day, description, cents, category,
/// essentiality.
const _cardPurchases = [
  (3, 'Supermercado Bom Preço', 48230, _food, _essential),
  (9, 'Posto Estrada Real', 21000, SpendingCategory.transport, _important),
  (11, 'Restaurante Sabor da Serra', 8950, _food, _superfluous),
  (14, 'Farmácia Vida Plena', 6420, SpendingCategory.health, _essential),
  (17, 'Supermercado Bom Preço', 39110, _food, _essential),
  (19, 'Streaming Cine+', 3990, SpendingCategory.services, _superfluous),
  (22, 'Livraria Página Virada', 7480, SpendingCategory.education, _important),
  (25, 'Loja Tudo pra Casa', 12900, SpendingCategory.shopping, _superfluous),
];

/// Debit and Pix spending in the second bank, same shape.
const _debitSpending = [
  (6, 'Academia Movimento', 9900, SpendingCategory.health, _important),
  (8, 'Aluguel', 165000, SpendingCategory.housing, _essential),
  (12, 'Conta de luz', 15800, SpendingCategory.housing, _essential),
  (15, 'Internet Fibra Lar', 11990, SpendingCategory.services, _essential),
  (20, 'Padaria Pão de Ontem', 2350, _food, _essential),
  (23, 'Corrida de app', 2780, SpendingCategory.transport, _important),
  (27, 'Padaria Pão de Ontem', 1980, _food, _essential),
];

/// Integer jitter of up to R$ 19,99 so the months differ; far below 2^53,
/// so the web computes it exactly like the VM.
int _vary(int cents, int month, int salt) =>
    cents + (month * 7919 + salt * 104729) % 2000;

/// The demo dataset (RF-63). "Today" is 28/03/2026.
Dataset demoDataset() {
  final txs = <Transaction>[];
  void add(
    String account,
    int month,
    int day,
    String description,
    int cents,
    TxKind kind, [
    SpendingCategory? category,
    Essentiality? essentiality,
    int? installment,
  ]) => txs.add(
    Transaction(
      id: txs.length,
      accountId: account,
      date: DateTime(2026, month, day),
      description: description,
      amountCents: cents,
      kind: kind,
      category: category,
      essentiality: essentiality,
      installment: installment,
      installmentCount: installment == null ? null : 10,
    ),
  );

  var openBill = 0;
  for (var m = 1; m <= 3; m++) {
    add('aurora-cc', m, 5, 'Salário', 620000, TxKind.income);
    add(
      'aurora-cc',
      m,
      6,
      'Transferência para a poupança',
      -50000,
      TxKind.ownTransfer,
    );
    add(
      'aurora-poup',
      m,
      6,
      'Transferência da conta corrente',
      50000,
      TxKind.ownTransfer,
    );
    add(
      'aurora-cc',
      m,
      6,
      'Pix para Banco Siriema',
      -260000,
      TxKind.ownTransfer,
    );
    add('siriema-cc', m, 6, 'Pix de Banco Aurora', 260000, TxKind.ownTransfer);
    if (openBill > 0) {
      add(
        'aurora-cc',
        m,
        10,
        'Pagamento da fatura do cartão',
        -openBill,
        TxKind.billPayment,
      );
      add(
        'aurora-card',
        m,
        10,
        'Pagamento recebido',
        openBill,
        TxKind.billPayment,
      );
    }
    add('aurora-cc', m, 18, 'Saque', -20000, TxKind.cashWithdrawal);

    // Bought in November 2025 in 10 installments; January is the 3rd.
    final bill = [
      (4, 'Notebook Loja Byte', 42000, SpendingCategory.shopping, _important),
      ..._cardPurchases,
    ];
    openBill = 0;
    for (final (i, (day, description, cents, category, essentiality))
        in bill.indexed) {
      final amount = i == 0 ? cents : _vary(cents, m, i);
      add(
        'aurora-card',
        m,
        day,
        description,
        -amount,
        TxKind.expense,
        category,
        essentiality,
        i == 0 ? m + 2 : null,
      );
      openBill += amount;
    }
    for (final (i, (day, description, cents, category, essentiality))
        in _debitSpending.indexed) {
      add(
        'siriema-cc',
        m,
        day,
        description,
        -_vary(cents, m, i + 10),
        TxKind.expense,
        category,
        essentiality,
      );
    }
  }
  add('aurora-poup', 2, 13, 'Aplicação CDB', -100000, TxKind.investment);
  add(
    'siriema-cc',
    3,
    21,
    'Pix recebido: projeto freelance',
    85000,
    TxKind.income,
  );

  return Dataset(
    banks: const [
      Bank('aurora', 'Banco Aurora'),
      Bank('siriema', 'Banco Siriema'),
    ],
    accounts: const [
      Account(
        id: 'aurora-cc',
        bankId: 'aurora',
        name: 'Conta corrente',
        kind: AccountKind.checking,
        openingBalanceCents: 312000,
      ),
      Account(
        id: 'aurora-poup',
        bankId: 'aurora',
        name: 'Poupança',
        kind: AccountKind.savings,
        openingBalanceCents: 1450000,
      ),
      Account(
        id: 'aurora-card',
        bankId: 'aurora',
        name: 'Cartão Aurora',
        kind: AccountKind.creditCard,
      ),
      Account(
        id: 'siriema-cc',
        bankId: 'siriema',
        name: 'Conta corrente',
        kind: AccountKind.checking,
        openingBalanceCents: 95000,
      ),
    ],
    transactions: txs,
    today: DateTime(2026, 3, 28),
  );
}

/// Formats cents as Brazilian reais, e.g. -123456 -> "-R$ 1.234,56".
String formatBrl(int cents) {
  final abs = cents.abs();
  final reais = (abs ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => '.',
  );
  final centavos = (abs % 100).toString().padLeft(2, '0');
  return '${cents < 0 ? '-' : ''}R\$ $reais,$centavos';
}
