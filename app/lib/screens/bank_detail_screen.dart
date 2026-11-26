import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/queries.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'onboarding_screen.dart';
import 'transaction_detail_sheet.dart';

/// Bank detail & switcher screen (RF-17) including Credit Cards & Bills (RF-20).
class BankDetailScreen extends StatefulWidget {
  const BankDetailScreen({super.key, this.initialBankId});

  final String? initialBankId;

  @override
  State<BankDetailScreen> createState() => _BankDetailScreenState();
}

class _BankDetailScreenState extends State<BankDetailScreen> {
  String? _selectedBankId;

  @override
  void initState() {
    super.initState();
    _selectedBankId = widget.initialBankId;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final data = state.effectiveDataset;
    final banks = data.banks;
    final selectedBank = _selectedBankId == null
        ? null
        : banks.firstWhere((b) => b.id == _selectedBankId);
    final s = summary(data, state.selectedMonth, bankId: _selectedBankId);

    final accounts = data.accounts
        .where((a) => _selectedBankId == null || a.bankId == _selectedBankId)
        .toList(growable: false);
    final regularAccounts = accounts
        .where((a) => a.kind != AccountKind.creditCard)
        .toList(growable: false);
    final cardAccounts = accounts
        .where((a) => a.kind == AccountKind.creditCard)
        .toList(growable: false);

    final txResult = effectiveHistory(
      data,
      state.effectiveTransactions,
      TxFilter(bankId: _selectedBankId),
      limit: 30,
    );

    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedBank?.name ?? 'Todos os bancos'),
        actions: [
          IconButton(
            onPressed: state.toggleHideValues,
            tooltip: state.hideValues ? 'Mostrar valores' : 'Esconder valores',
            icon: Icon(
              state.hideValues
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          DemoBanner(
            onExploreGuide: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OnboardingScreen(profileOnly: false),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: GranaSpacing.maxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  children: [
                    // Bank switcher chips (RF-17)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            key: const Key('bank_switch_all'),
                            label: const Text('Todos'),
                            selected: _selectedBankId == null,
                            onSelected: (_) =>
                                setState(() => _selectedBankId = null),
                          ),
                          for (final b in banks) ...[
                            const SizedBox(width: GranaSpacing.sm),
                            ChoiceChip(
                              key: Key('bank_switch_${b.id}'),
                              label: Text(b.name),
                              selected: _selectedBankId == b.id,
                              onSelected: (_) =>
                                  setState(() => _selectedBankId = b.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.lg),

                    // Summary card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(GranaSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedBank == null
                                        ? 'Resumo consolidado · ${formatShortMonth(state.selectedMonth)}'
                                        : '${selectedBank.name} · ${formatShortMonth(state.selectedMonth)}',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (selectedBank != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          selectedBank.connectionStatus ==
                                              ConnectionStatus.expiringSoon
                                          ? tokens.milho.withValues(alpha: 0.25)
                                          : tokens.mata.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(
                                        GranaRadius.chip,
                                      ),
                                    ),
                                    child: Text(
                                      selectedBank.connectionStatus.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            selectedBank.connectionStatus ==
                                                ConnectionStatus.expiringSoon
                                            ? scheme.onSurface
                                            : tokens.mata,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (selectedBank != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                selectedBank.lastSyncedLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: GranaSpacing.lg),
                            Wrap(
                              spacing: GranaSpacing.xl,
                              runSpacing: GranaSpacing.md,
                              children: [
                                _SummaryMetric(
                                  label: 'Saldo em contas',
                                  cents: s.balanceCents,
                                  hideValues: state.hideValues,
                                ),
                                _SummaryMetric(
                                  label: 'Fatura aberta',
                                  cents: s.cardBillCents,
                                  hideValues: state.hideValues,
                                ),
                                _SummaryMetric(
                                  label: 'Receitas do mês',
                                  cents: s.receivedCents,
                                  hideValues: state.hideValues,
                                  showPlusSign: true,
                                  colorOverride: tokens.mata,
                                ),
                                _SummaryMetric(
                                  label: 'Gastos do mês',
                                  cents: -s.spentCents,
                                  hideValues: state.hideValues,
                                  useUnicodeMinus: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.xl),

                    // Accounts section
                    Text(
                      'Contas',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    for (final a in regularAccounts) ...[
                      Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Color(
                              data.bank(a.bankId).colorValue,
                            ).withValues(alpha: 0.14),
                            child: Icon(
                              a.kind == AccountKind.savings
                                  ? Icons.savings_outlined
                                  : Icons.account_balance_outlined,
                              color: Color(data.bank(a.bankId).colorValue),
                            ),
                          ),
                          title: Text(
                            a.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${a.kind.label} · ${data.bank(a.bankId).name}',
                          ),
                          trailing: MoneyText(
                            cents: accountBalanceCents(data, a),
                            hideValues: state.hideValues,
                            style: tokens.valorLinha,
                          ),
                        ),
                      ),
                      const SizedBox(height: GranaSpacing.sm),
                    ],

                    // Credit cards & bills section (RF-20)
                    if (cardAccounts.isNotEmpty) ...[
                      const SizedBox(height: GranaSpacing.lg),
                      Text(
                        'Cartões e faturas',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: GranaSpacing.sm),
                      for (final card in cardAccounts) ...[
                        _CreditCardSection(
                          card: card,
                          bills: cardBills(data, card.id),
                          hideValues: state.hideValues,
                          onTapBill: (bill) =>
                              _showCardBillSheet(context, card, bill),
                        ),
                        const SizedBox(height: GranaSpacing.md),
                      ],
                    ],

                    // Transactions for this bank / all banks
                    const SizedBox(height: GranaSpacing.lg),
                    Text(
                      selectedBank == null
                          ? 'Movimentações recentes'
                          : 'Movimentações de ${selectedBank.name}',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, tx) in txResult.items.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            TransactionRow(
                              tx: tx,
                              account: data.account(tx.accountId),
                              bank: data.bank(
                                data.account(tx.accountId).bankId,
                              ),
                              hideValues: state.hideValues,
                              onTap: () =>
                                  showTransactionDetailSheet(context, tx.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCardBillSheet(
    BuildContext context,
    Account card,
    CardBill initialBill,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final state = AppScope.of(sheetContext);
        final data = state.effectiveDataset;
        final bank = data.bank(card.bankId);
        final bill = cardBills(data, card.id).firstWhere(
          (b) => b.year == initialBill.year && b.month == initialBill.month,
          orElse: () => CardBill(
            accountId: initialBill.accountId,
            year: initialBill.year,
            month: initialBill.month,
            closingDate: initialBill.closingDate,
            dueDate: initialBill.dueDate,
            totalCents: 0,
            isOpen: initialBill.isOpen,
            purchases: const [],
          ),
        );
        final billTxs = [
          for (final p in bill.purchases) state.effectiveById(p.id),
        ];
        final tokens = GranaTokens.of(sheetContext);
        final textTheme = Theme.of(sheetContext).textTheme;

        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GranaSpacing.lg,
                  0,
                  GranaSpacing.sm,
                  GranaSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fatura ${formatMonthYear(DateTime(bill.year, bill.month))}',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${card.name} ${card.lastFourDigits != null ? '•••• ${card.lastFourDigits}' : ''} · '
                            '${bill.isOpen ? 'Aberta' : 'Fechada'}',
                            style: TextStyle(
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          MoneyText(
                            cents: bill.totalCents,
                            hideValues: state.hideValues,
                            style: tokens.valorGrande,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fechamento: ${formatFullDate(bill.closingDate)} · '
                            'Vencimento: ${formatFullDate(bill.dueDate)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      tooltip: 'Fechar',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(GranaSpacing.md),
                  itemCount: billTxs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (itemContext, index) {
                    final tx = billTxs[index];
                    return TransactionRow(
                      tx: tx,
                      account: card,
                      bank: bank,
                      hideValues: state.hideValues,
                      onTap: () =>
                          showTransactionDetailSheet(sheetContext, tx.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.cents,
    required this.hideValues,
    this.showPlusSign = false,
    this.useUnicodeMinus = false,
    this.colorOverride,
  });

  final String label;
  final int cents;
  final bool hideValues;
  final bool showPlusSign;
  final bool useUnicodeMinus;
  final Color? colorOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        MoneyText(
          cents: cents,
          hideValues: hideValues,
          showPlusSign: showPlusSign,
          useUnicodeMinus: useUnicodeMinus,
          colorOverride: colorOverride,
          style: tokens.valorGrande,
        ),
      ],
    );
  }
}

class _CreditCardSection extends StatelessWidget {
  const _CreditCardSection({
    required this.card,
    required this.bills,
    required this.hideValues,
    required this.onTapBill,
  });

  final Account card;
  final List<CardBill> bills;
  final bool hideValues;
  final void Function(CardBill bill) onTapBill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_rounded, color: scheme.primary),
                const SizedBox(width: GranaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (card.lastFourDigits != null)
                        Text(
                          'Final •••• ${card.lastFourDigits}',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (card.closingDay != null && card.dueDay != null)
                  Text(
                    'Fecha dia ${card.closingDay} · Vence dia ${card.dueDay}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: GranaSpacing.md),
            const Divider(height: 1),
            for (final (i, bill) in bills.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                key: Key('card_bill_${bill.year}_${bill.month}'),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: GranaSpacing.xs,
                ),
                title: Row(
                  children: [
                    Text(
                      formatMonthYear(DateTime(bill.year, bill.month)),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: bill.isOpen
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(GranaRadius.chip),
                      ),
                      child: Text(
                        bill.isOpen ? 'Aberta' : 'Fechada',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: bill.isOpen
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${bill.purchases.length} compras · '
                  'Vence em ${formatFullDate(bill.dueDate)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoneyText(
                      cents: bill.totalCents,
                      hideValues: hideValues,
                      style: tokens.valorLinha,
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () => onTapBill(bill),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
