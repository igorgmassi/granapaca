// Spending categories, essentiality levels, movement types and rule layers.

/// Spending categories: 8 groups plus "Outros".
enum SpendingCategory {
  housing('Moradia'),
  food('Alimentação'),
  transport('Transporte'),
  health('Saúde'),
  education('Educação'),
  leisure('Lazer'),
  shopping('Compras'),
  services('Serviços e assinaturas'),
  other('Outros');

  const SpendingCategory(this.label);

  final String label;
}

/// Essentiality, kept apart from the category with judgment-free labels:
/// a restaurant is food, and can be flexible rather than essential.
enum Essentiality {
  essential('Essencial'),
  important('Importante'),
  flexible('Flexível');

  const Essentiality(this.label);

  final String label;
}

/// What a movement is. Only [expense] and [refund] count toward spending and
/// only [income] counts as income; the others move the same money around and
/// are never counted twice (ADR-014).
enum TxKind {
  expense('Gasto'),
  income('Receita'),
  ownTransfer('Transferência própria'),
  billPayment('Pagamento de fatura'),
  refund('Estorno'),
  investment('Aplicação'),
  redemption('Resgate'),
  cashWithdrawal('Saque');

  const TxKind(this.label);

  final String label;
}

/// Rule layers ordered by precedence below manual adjustments.
enum RuleLayer {
  user('Regra minha'),
  profile('Regra do perfil'),
  system('Regra do sistema');

  const RuleLayer(this.label);

  final String label;
}

/// Categories the donut shows before the rest goes into one remainder slice.
const donutCategories = 5;
