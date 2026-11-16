// [Suposição] Everything in this file waits on the pending requirements of
// Part 2: P1 (the category list and the donut size) and P2 (the essentiality
// levels). Change it here when they are decided; nothing else hard-codes them.

/// [Suposição, P1] Spending categories: 8 groups plus "Outros".
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

/// [Suposição, P2] Essentiality, kept apart from the category: a restaurant
/// is food, but it is not essential.
enum Essentiality {
  essential('Essencial'),
  important('Importante'),
  superfluous('Supérfluo');

  const Essentiality(this.label);

  final String label;
}

/// [Suposição, P1] Categories the donut shows before the rest goes into one
/// remainder slice (P1: 5 or 6).
const donutCategories = 5;
