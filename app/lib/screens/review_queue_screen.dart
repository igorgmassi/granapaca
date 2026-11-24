import 'package:material_ui/material_ui.dart';

import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

/// Dedicated Review Queue ("A revisar") screen grouping uncategorized expenses
/// by normalized merchant name with count, quick categorization, and
/// "Aplicar às semelhantes" rule creation (RF-31, RF-26).
class ReviewQueueScreen extends StatelessWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final groups = state.reviewQueueGroups;
    final totalTxs = state.reviewQueueTransactionCount;
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('A revisar')),
      body: Column(
        children: [
          if (state.isDemoMode)
            const DemoBanner()
          else if (state.isOffline)
            OfflineBanner(
              lastSyncedAt: state.lastSyncedAt,
              onRetry: state.syncFromServer,
            ),
          Expanded(
            child: groups.isEmpty
                ? const EmptyStateView(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Tudo classificado por aqui!',
                    subtitle:
                        'Todas as suas despesas já possuem categoria. Quando '
                        'aparecerem compras sem categoria, elas serão '
                        'agrupadas aqui por estabelecimento.',
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: GranaSpacing.maxContentWidth,
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(GranaSpacing.lg),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(GranaSpacing.md),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(
                                GranaRadius.chip,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.pending_actions_outlined,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: GranaSpacing.md),
                                Expanded(
                                  child: Text(
                                    '${groups.length} '
                                    '${groups.length == 1 ? 'estabelecimento' : 'estabelecimentos'} '
                                    '· $totalTxs '
                                    '${totalTxs == 1 ? 'transação' : 'transações'} '
                                    'sem categoria',
                                    key: const Key('review_queue_summary'),
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: GranaSpacing.lg),
                          for (final group in groups) ...[
                            Card(
                              child: InkWell(
                                key: Key('review_group_${group.merchantKey}'),
                                borderRadius: BorderRadius.circular(
                                  GranaRadius.card,
                                ),
                                onTap: () => _openQuickClassifySheet(
                                  context,
                                  state,
                                  group,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(GranaSpacing.lg),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: tokens.milho.withValues(
                                            alpha: 0.22,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.help_outline_rounded,
                                          color: tokens.sobreMilho,
                                        ),
                                      ),
                                      const SizedBox(width: GranaSpacing.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              group.displayName,
                                              style: textTheme.titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: GranaSpacing.sm,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: scheme
                                                        .secondaryContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          GranaRadius.chip,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '${group.count} '
                                                    '${group.count == 1 ? 'transação' : 'transações'}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: scheme
                                                          .onSecondaryContainer,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  'Sem categoria',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: scheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: GranaSpacing.md),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          MoneyText(
                                            cents: group.totalCents,
                                            hideValues: state.hideValues,
                                            style: tokens.valorLinha,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Classificar',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: scheme.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: GranaSpacing.sm),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openQuickClassifySheet(
    BuildContext context,
    AppState state,
    ReviewQueueGroup group,
  ) {
    if (!state.canEditTransactions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppState.offlineEditBlockedMessage)),
      );
      return Future<void>.value();
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _QuickClassifySheet(group: group),
    );
  }
}

class _QuickClassifySheet extends StatefulWidget {
  const _QuickClassifySheet({required this.group});

  final ReviewQueueGroup group;

  @override
  State<_QuickClassifySheet> createState() => _QuickClassifySheetState();
}

class _QuickClassifySheetState extends State<_QuickClassifySheet> {
  SpendingCategory? _selectedCategory;
  Essentiality? _selectedEssentiality;

  Future<void> _save(AppState state) async {
    if (!state.canEditTransactions) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppState.offlineEditBlockedMessage)),
      );
      return;
    }
    final category = _selectedCategory;
    if (category == null) return;

    final leadTx = widget.group.transactions.first;
    final created = state.adjustTransaction(
      txId: leadTx.id,
      category: category,
      changeCategory: true,
      essentiality: _selectedEssentiality,
      changeEssentiality: _selectedEssentiality != null,
    );
    if (created.isEmpty) return;

    if (!mounted) return;
    final otherCount = widget.group.count - 1;
    final applySimilar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aplicar às semelhantes?'),
        content: Text(
          otherCount > 0
              ? 'Existem mais $otherCount transação(ões) de '
                    '"${widget.group.displayName}". Deseja criar uma regra '
                    'para aplicar ${category.label} a todas elas e às próximas '
                    'compras semelhantes?'
              : 'Deseja criar uma regra para aplicar ${category.label} '
                    'automaticamente às próximas compras de '
                    '"${widget.group.displayName}"?',
        ),
        actions: [
          TextButton(
            key: const Key('review_only_this_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Só esta'),
          ),
          FilledButton(
            key: const Key('review_apply_similar_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Aplicar às semelhantes'),
          ),
        ],
      ),
    );

    if (applySimilar == true) {
      state.createUserRuleFromTransaction(
        txId: leadTx.id,
        category: category,
        essentiality: _selectedEssentiality,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          applySimilar == true
              ? 'Classificação salva e regra criada para "${widget.group.displayName}".'
              : 'Transação classificada em ${category.label}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        GranaSpacing.lg,
        0,
        GranaSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + GranaSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.group.displayName,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.group.count} '
              '${widget.group.count == 1 ? 'transação' : 'transações'} sem categoria',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),
            Text(
              'Escolha uma categoria',
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: GranaSpacing.sm),
            Wrap(
              spacing: GranaSpacing.sm,
              runSpacing: GranaSpacing.sm,
              children: [
                for (final c in SpendingCategory.values)
                  ChoiceChip(
                    key: Key('review_cat_${c.name}'),
                    label: Text(c.label),
                    selected: _selectedCategory == c,
                    onSelected: (_) => setState(() => _selectedCategory = c),
                  ),
              ],
            ),
            const SizedBox(height: GranaSpacing.lg),
            Text(
              'Essencialidade (opcional e independente)',
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: GranaSpacing.sm),
            Wrap(
              spacing: GranaSpacing.sm,
              runSpacing: GranaSpacing.sm,
              children: [
                for (final e in Essentiality.values)
                  ChoiceChip(
                    key: Key('review_ess_${e.name}'),
                    label: Text(e.label),
                    selected: _selectedEssentiality == e,
                    onSelected: (_) => setState(() {
                      _selectedEssentiality = _selectedEssentiality == e
                          ? null
                          : e;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: GranaSpacing.xl),
            FilledButton.icon(
              key: const Key('review_save_button'),
              onPressed: _selectedCategory == null ? null : () => _save(state),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar classificação'),
            ),
          ],
        ),
      ),
    );
  }
}
