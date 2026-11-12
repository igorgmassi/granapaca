import 'taxonomy.dart';

enum AccountKind { checking, savings, creditCard }

/// What a movement is. Only [expense] counts as spending and only [income]
/// as income; the others move the same money around and are never counted
/// twice (RN-15): transfers between own accounts, credit card bill payments,
/// investments and redemptions, cash withdrawals.
enum TxKind {
  expense,
  income,
  ownTransfer,
  billPayment,
  investment,
  cashWithdrawal,
}

class Bank {
  const Bank(this.id, this.name);

  final String id;
  final String name;
}

class Account {
  const Account({
    required this.id,
    required this.bankId,
    required this.name,
    required this.kind,
    this.openingBalanceCents = 0,
  });

  final String id;
  final String bankId;
  final String name;
  final AccountKind kind;

  /// Balance before the first transaction of the dataset.
  final int openingBalanceCents;
}

/// A movement in one account. Cents in an `int`; negative means money out.
/// On a credit card, a purchase is negative and the bill payment positive.
class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.date,
    required this.description,
    required this.amountCents,
    required this.kind,
    this.category,
    this.essentiality,
    this.installment,
    this.installmentCount,
  }) : assert(kind != TxKind.expense || category != null);

  /// Unique; breaks ties so the order is the same on every platform.
  final int id;
  final String accountId;
  final DateTime date;
  final String description;
  final int amountCents;
  final TxKind kind;
  final SpendingCategory? category;
  final Essentiality? essentiality;

  /// Installment number and total, e.g. 3 of 10.
  final int? installment;
  final int? installmentCount;
}

class Dataset {
  Dataset({
    required this.banks,
    required this.accounts,
    required List<Transaction> transactions,
    required this.today,
  }) : transactions = List.unmodifiable(
         [...transactions]..sort(
           (a, b) => b.date != a.date ? b.date.compareTo(a.date) : b.id - a.id,
         ),
       );

  final List<Bank> banks;
  final List<Account> accounts;

  /// Newest first.
  final List<Transaction> transactions;

  /// "Now" for this dataset; the default month of every screen.
  final DateTime today;

  late final Map<String, Account> _accounts = {
    for (final a in accounts) a.id: a,
  };

  Account account(String id) => _accounts[id]!;
}
