import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/queries.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'bank_detail_screen.dart';
import 'transaction_detail_sheet.dart';

/// Main overview screen (RF-16, RF-17, RF-05).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.simulateNoConnections) {
      return EmptyStateView(
        icon: Icons.account_balance_outlined,
        title: 'Conecte seus bancos para começar',
        subtitle:
            'Reúna contas, cartões e faturas num só lugar, somente leitura '
            'e na sua própria instância.',
        actionLabel: 'Conectar primeiro banco',
        onAction: () =>
            showServerOnlyDialog(context, 'Conectar banco via Meu Pluggy'),
        secondaryActionLabel: 'Voltar aos dados da demo',
        onSecondaryAction: () => state.setSimulateNoConnections(false),
      );
    }

    final data = state.effectiveDataset;
    final month = state.selectedMonth;
    final (from, to) = monthRange(month);
    final s = summary(data, month);
    final monthHistory = effectiveHistory(
      data,
      state.effectiveTransactions,
      TxFilter(from: from, to: to),
    );
    final monthPlainTxs = [for (final t in monthHistory.items) t.toTransaction()];
    final essShares = essentialityBreakdown(monthPlainTxs);
    final ranking = categoryRanking(monthPlainTxs);
    final recentTxs = monthHistory.items.take(5).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;

        final monthBar = _MonthSelectorBar(
          months: state.availableMonths,
          selected: month,
          onSelect: state.selectMonth,
        );

        final heroCard = _HeroSummaryCard(
          summaryData: s,
          essentialityShares: essShares,
          hideValues: state.hideValues,
        );

        final accountsCard = _AccountsSummaryCard(
          summaryData: s,
          hideValues: state.hideValues,
          onOpenCard: () => _openBank(context, 'aurora'),
        );

        final banksSection = _BanksSection(
          data: data,
          month: month,
          hideValues: state.hideValues,
          onSelectBank: (bankId) => _openBank(context, bankId),
        );

        final recentSection = _RecentTransactionsSection(
          data: data,
          transactions: recentTxs,
          hideValues: state.hideValues,
          onViewAll: () => state.openHistoryWithFilter(
            TxFilter(from: from, to: to),
          ),
          onTapTransaction: (txId) => showTransactionDetailSheet(context, txId),
        );

        if (isDesktop) {
          return ListView(
            padding: const EdgeInsets.all(GranaSpacing.lg),
            children: [
              monthBar,
              const SizedBox(height: GranaSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heroCard,
                        const SizedBox(height: GranaSpacing.lg),
                        accountsCard,
                        const SizedBox(height: GranaSpacing.xl),
                        banksSection,
                      ],
                    ),
                  ),
                  const SizedBox(width: GranaSpacing.xl),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MiniSpendingPreviewCard(
                          ranking: ranking,
                          hideValues: state.hideValues,
                          onOpenSpending: () {
                            state.setSpendingFilters(month: month);
                            state.selectTab(2);
                          },
                        ),
                        const SizedBox(height: GranaSpacing.lg),
                        recentSection,
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.all(GranaSpacing.lg),
          children: [
            monthBar,
            const SizedBox(height: GranaSpacing.lg),
            heroCard,
            const SizedBox(height: GranaSpacing.lg),
            accountsCard,
            const SizedBox(height: GranaSpacing.xl),
            banksSection,
            const SizedBox(height: GranaSpacing.xl),
            recentSection,
          ],
        );
      },
    );
  }

  void _openBank(BuildContext context, String bankId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BankDetailScreen(initialBankId: bankId),
      ),
    );
  }
}

class _MonthSelectorBar extends StatelessWidget {
  const _MonthSelectorBar({
    required this.months,
    required this.selected,
    required this.onSelect,
  });

  final List<DateTime> months;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, m) in months.indexed) ...[
            if (i > 0) const SizedBox(width: GranaSpacing.sm),
            ChoiceChip(
              key: Key('home_month_${m.year}_${m.month}'),
              label: Text(formatShortMonth(m)),
              selected: m.year == selected.year && m.month == selected.month,
              onSelected: (_) => onSelect(m),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroSummaryCard extends StatelessWidget {
  const _HeroSummaryCard({
    required this.summaryData,
    required this.essentialityShares,
    required this.hideValues,
  });

  final Summary summaryData;
  final List<EssentialityShare> essentialityShares;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo do mês',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: GranaSpacing.xs),
            MoneyText(
              cents: summaryData.leftoverCents,
              hideValues: hideValues,
              style: tokens.valorDestaque,
              colorOverride: summaryData.leftoverCents < 0
                  ? scheme.error
                  : scheme.onSurface,
            ),
            const SizedBox(height: 4),
            Text(
              summaryData.leftoverCents >= 0
                  ? 'Sobrou este mês'
                  : 'Saiu mais do que entrou este mês',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(GranaSpacing.md),
                    decoration: BoxDecoration(
                      color: tokens.mata.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(GranaRadius.chip),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Receitas',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.mata,
                          ),
                        ),
                        const SizedBox(height: 4),
                        MoneyText(
                          cents: summaryData.receivedCents,
                          hideValues: hideValues,
                          showPlusSign: summaryData.receivedCents > 0,
                          colorOverride: tokens.mata,
                          style: tokens.valorLinha,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: GranaSpacing.md),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(GranaSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(GranaRadius.chip),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gastos',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        MoneyText(
                          cents: -summaryData.spentCents,
                          hideValues: hideValues,
                          useUnicodeMinus: true,
                          style: tokens.valorLinha,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (essentialityShares.isNotEmpty) ...[
              const SizedBox(height: GranaSpacing.lg),
              Text(
                'Essencialidade dos gastos',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(GranaRadius.pill),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      for (final (i, item) in essentialityShares.indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: (item.share * 1000).round().clamp(1, 1000),
                          child: Container(
                            color: tokens.colorForEssentiality(
                              item.essentiality,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              Wrap(
                spacing: GranaSpacing.md,
                runSpacing: GranaSpacing.xs,
                children: [
                  for (final item in essentialityShares)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EssentialityBadge(essentiality: item.essentiality),
                        const SizedBox(width: 4),
                        Text(
                          formatPercent(item.share, decimals: 0),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                            fontFeatures: GranaTokens.tabularFeatures,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountsSummaryCard extends StatelessWidget {
  const _AccountsSummaryCard({
    required this.summaryData,
    required this.hideValues,
    required this.onOpenCard,
  });

  final Summary summaryData;
  final bool hideValues;
  final VoidCallback onOpenCard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.lg),
        child: Wrap(
          spacing: GranaSpacing.xl,
          runSpacing: GranaSpacing.md,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo em contas',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                MoneyText(
                  cents: summaryData.balanceCents,
                  hideValues: hideValues,
                  style: tokens.valorGrande,
                ),
                const SizedBox(height: 2),
                Text(
                  'Corrente + poupança (fatura separada)',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: onOpenCard,
              borderRadius: BorderRadius.circular(GranaRadius.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GranaSpacing.sm,
                  vertical: GranaSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Fatura aberta do cartão',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    MoneyText(
                      cents: summaryData.cardBillCents,
                      hideValues: hideValues,
                      style: tokens.valorGrande,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cartão Aurora •••• 4821',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BanksSection extends StatelessWidget {
  const _BanksSection({
    required this.data,
    required this.month,
    required this.hideValues,
    required this.onSelectBank,
  });

  final Dataset data;
  final DateTime month;
  final bool hideValues;
  final ValueChanged<String> onSelectBank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Seus bancos',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        for (final bank in data.banks) ...[
          () {
            final bankSummary = summary(data, month, bankId: bank.id);
            final acctCount = data.accounts
                .where((a) => a.bankId == bank.id)
                .length;
            return Card(
              child: InkWell(
                key: Key('bank_card_${bank.id}'),
                onTap: () => onSelectBank(bank.id),
                borderRadius: BorderRadius.circular(GranaRadius.card),
                child: Padding(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Color(bank.colorValue),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: GranaSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: GranaSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  bank.name,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        bank.connectionStatus ==
                                            ConnectionStatus.expiringSoon
                                        ? tokens.milho.withValues(alpha: 0.25)
                                        : tokens.mata.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(
                                      GranaRadius.chip,
                                    ),
                                  ),
                                  child: Text(
                                    bank.connectionStatus.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          bank.connectionStatus ==
                                              ConnectionStatus.expiringSoon
                                          ? scheme.onSurface
                                          : tokens.mata,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$acctCount conta(s) · ${bank.lastSyncedLabel}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GranaSpacing.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                            cents: bankSummary.balanceCents,
                            hideValues: hideValues,
                            style: tokens.valorLinha,
                          ),
                          if (bankSummary.cardBillCents > 0) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Fatura: ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                MoneyText(
                                  cents: bankSummary.cardBillCents,
                                  hideValues: hideValues,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: GranaTokens.tabularFeatures,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }(),
          const SizedBox(height: GranaSpacing.sm),
        ],
      ],
    );
  }
}

class _MiniSpendingPreviewCard extends StatelessWidget {
  const _MiniSpendingPreviewCard({
    required this.ranking,
    required this.hideValues,
    required this.onOpenSpending,
  });

  final List<CategoryShare> ranking;
  final bool hideValues;
  final VoidCallback onOpenSpending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final top = ranking.take(4).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Onde foi o dinheiro',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onOpenSpending,
                  child: const Text('Ver gráficos'),
                ),
              ],
            ),
            if (top.isEmpty)
              Text(
                'Sem gastos registrados neste mês.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              for (final item in top) ...[
                const SizedBox(height: GranaSpacing.sm),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: tokens.colorForCategory(item.category),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    Expanded(
                      child: Text(
                        item.category.label,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (!hideValues) ...[
                      MoneyText(
                        cents: item.cents,
                        hideValues: false,
                        style: tokens.valorLinha.copyWith(fontSize: 13),
                      ),
                      const SizedBox(width: GranaSpacing.sm),
                    ],
                    Text(
                      formatPercent(item.share, decimals: 0),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: GranaTokens.tabularFeatures,
                      ),
                    ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _RecentTransactionsSection extends StatelessWidget {
  const _RecentTransactionsSection({
    required this.data,
    required this.transactions,
    required this.hideValues,
    required this.onViewAll,
    required this.onTapTransaction,
  });

  final Dataset data;
  final List<EffectiveTransaction> transactions;
  final bool hideValues;
  final VoidCallback onViewAll;
  final ValueChanged<int> onTapTransaction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Últimas transações',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: onViewAll, child: const Text('Ver tudo')),
          ],
        ),
        const SizedBox(height: GranaSpacing.sm),
        if (transactions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(GranaSpacing.xl),
              child: Center(
                child: Text(
                  'Sem movimentações neste mês.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, tx) in transactions.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  TransactionRow(
                    tx: tx,
                    account: data.account(tx.accountId),
                    bank: data.bank(data.account(tx.accountId).bankId),
                    hideValues: hideValues,
                    onTap: () => onTapTransaction(tx.id),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
