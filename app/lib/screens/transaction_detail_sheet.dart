import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

/// Opens the transaction detail & manual adjustment bottom sheet
/// (RF-24, RF-25, RF-26).
Future<void> showTransactionDetailSheet(BuildContext context, int txId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _TransactionDetailSheet(txId: txId),
    ),
  );
}

class _TransactionDetailSheet extends StatefulWidget {
  const _TransactionDetailSheet({required this.txId});

  final int txId;

  @override
  State<_TransactionDetailSheet> createState() =>
      _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<_TransactionDetailSheet> {
  late TextEditingController _descriptionController;
  late TextEditingController _reasonController;
  late TxKind _kind;
  SpendingCategory? _category;
  Essentiality? _essentiality;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
    _reasonController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _syncFromState(AppScope.of(context));
      _initialized = true;
    }
  }

  void _syncFromState(AppState state) {
    final tx = state.effectiveById(widget.txId);
    _descriptionController.text = tx.description;
    _kind = tx.kind;
    _category = tx.category;
    _essentiality = tx.essentiality;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool _hasPendingChanges(EffectiveTransaction tx) {
    final descChanged =
        _descriptionController.text.trim().isNotEmpty &&
        _descriptionController.text.trim() != tx.description;
    final kindChanged = _kind != tx.kind;
    final isSpend = isSpendingKind(_kind);
    final catChanged = isSpend && _category != tx.category;
    final essChanged = isSpend && _essentiality != tx.essentiality;
    return descChanged || kindChanged || catChanged || essChanged;
  }

  Future<void> _saveCorrection(AppState state, EffectiveTransaction tx) async {
    final descTrimmed = _descriptionController.text.trim();
    final descChanged =
        descTrimmed.isNotEmpty && descTrimmed != tx.description;
    final kindChanged = _kind != tx.kind;
    final isSpend = isSpendingKind(_kind);
    final catChanged = isSpend && _category != tx.category;
    final essChanged = isSpend && _essentiality != tx.essentiality;

    final created = state.adjustTransaction(
      txId: tx.id,
      description: descTrimmed,
      changeDescription: descChanged,
      kind: _kind,
      changeKind: kindChanged,
      category: _category,
      changeCategory: catChanged,
      essentiality: _essentiality,
      changeEssentiality: essChanged,
      reason: _reasonController.text,
    );
    if (created.isEmpty) return;

    _reasonController.clear();

    if ((catChanged || essChanged || kindChanged) && mounted) {
      final similarCount = state.similarTransactionsCount(
        tx.id,
        checkCategory: catChanged,
        checkEssentiality: essChanged,
        checkKind: kindChanged,
      );
      if (similarCount > 0) {
        final applyAll = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Aplicar às transações semelhantes?'),
            content: Text(
              'Encontramos $similarCount outra(s) transação(ões) de '
              '"${tx.original.description}". Deseja criar uma regra para '
              'aplicar essa classificação a elas também? Ajustes manuais '
              'já feitos não serão alterados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Só esta'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Aplicar a todas'),
              ),
            ],
          ),
        );
        if (applyAll == true && mounted) {
          state.createUserRuleFromTransaction(
            txId: tx.id,
            category: catChanged ? _category : null,
            essentiality: essChanged ? _essentiality : null,
            kind: kindChanged ? _kind : null,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Regra criada e aplicada às transações semelhantes.'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tx = state.effectiveById(widget.txId);
    final account = state.originalDataset.account(tx.accountId);
    final bank = state.originalDataset.bank(account.bankId);
    final historyEntries = state.adjustmentsFor(tx.id);
    final undone = state.undoneIds;
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final canSave = _hasPendingChanges(tx);
    final showSpendingFields = isSpendingKind(_kind);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GranaSpacing.lg,
            0,
            GranaSpacing.sm,
            GranaSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.description,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    MoneyText(
                      cents: tx.amountCents,
                      hideValues: state.hideValues,
                      showPlusSign: tx.kind == TxKind.income,
                      useUnicodeMinus: true,
                      style: tokens.valorGrande,
                      colorOverride: tx.kind == TxKind.income
                          ? tokens.mata
                          : scheme.onSurface,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fechar',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(GranaSpacing.lg),
            children: [
              // Immutable bank data section
              Card(
                color: scheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: GranaSpacing.sm),
                          Text(
                            'Dados originais do banco',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: GranaSpacing.md),
                      _InfoLine(
                        label: 'Descrição original',
                        value: tx.original.description,
                      ),
                      _InfoLine(
                        label: 'Data',
                        value: formatFullDate(tx.original.date),
                      ),
                      _InfoLine(
                        label: 'Conta',
                        value: '${account.name} · ${bank.name}',
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Valor original',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          MoneyText(
                            cents: tx.original.amountCents,
                            hideValues: state.hideValues,
                            style: tokens.valorLinha,
                          ),
                        ],
                      ),
                      if (tx.installment != null &&
                          tx.installmentCount != null) ...[
                        const SizedBox(height: 6),
                        _InfoLine(
                          label: 'Parcela',
                          value:
                              'Parcela ${tx.installment} de ${tx.installmentCount}',
                        ),
                      ],
                      const SizedBox(height: GranaSpacing.sm),
                      Text(
                        'O registro original do banco é imutável e nunca é apagado.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: GranaSpacing.lg),

              // Classification provenance
              if (isSpendingKind(tx.kind)) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(GranaSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Origem da classificação',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: GranaSpacing.sm),
                        _ProvenanceLine(
                          field: 'Categoria',
                          source: tx.categorySource,
                          ruleExplanation: tx.categoryRuleExplanation,
                        ),
                        const SizedBox(height: GranaSpacing.sm),
                        _ProvenanceLine(
                          field: 'Essencialidade',
                          source: tx.essentialitySource,
                          ruleExplanation: tx.essentialityRuleExplanation,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GranaSpacing.lg),
              ],

              // Manual correction form (RF-24)
              Text(
                'Corrigir transação',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              TextField(
                key: const Key('tx_description_field'),
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descrição corrigida',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: GranaSpacing.lg),

              Text(
                'Tipo de movimento',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              Wrap(
                spacing: GranaSpacing.sm,
                runSpacing: GranaSpacing.sm,
                children: [
                  for (final k in TxKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) {
                        setState(() {
                          _kind = k;
                          if (isSpendingKind(k)) {
                            _category ??= SpendingCategory.other;
                            _essentiality ??= Essentiality.important;
                          }
                        });
                      },
                    ),
                ],
              ),

              if (showSpendingFields) ...[
                const SizedBox(height: GranaSpacing.lg),
                Text(
                  'Categoria',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
                Wrap(
                  spacing: GranaSpacing.sm,
                  runSpacing: GranaSpacing.sm,
                  children: [
                    for (final c in SpendingCategory.values)
                      ChoiceChip(
                        key: Key('cat_choice_${c.name}'),
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.lg),
                Text(
                  'Essencialidade (independente da categoria)',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
                Wrap(
                  spacing: GranaSpacing.sm,
                  runSpacing: GranaSpacing.sm,
                  children: [
                    for (final e in Essentiality.values)
                      ChoiceChip(
                        key: Key('ess_choice_${e.name}'),
                        label: Text(e.label),
                        selected: _essentiality == e,
                        onSelected: (_) => setState(() => _essentiality = e),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: GranaSpacing.lg),
              TextField(
                key: const Key('tx_reason_field'),
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Justificativa (opcional)',
                  hintText: 'Ex.: almoço de trabalho ou compra compartilhada',
                ),
              ),
              const SizedBox(height: GranaSpacing.lg),
              FilledButton.icon(
                key: const Key('save_correction_button'),
                onPressed: canSave ? () => _saveCorrection(state, tx) : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Salvar correção'),
              ),

              const SizedBox(height: GranaSpacing.xl),
              // Adjustment history (RF-25)
              Text(
                'Histórico de ajustes',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              if (historyEntries.isEmpty)
                Text(
                  'Nenhum ajuste manual registrado nesta transação.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                for (final entry in historyEntries) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(GranaSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      entry.field.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (entry.isUndo)
                                      Text(
                                        '· Desfazer',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.tertiary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    else if (undone.contains(entry.id))
                                      Text(
                                        '· Desfeito',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${formatAdjustmentValue(entry.field, entry.oldValue)} '
                                  '→ ${formatAdjustmentValue(entry.field, entry.newValue)}',
                                ),
                                if (entry.reason != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Motivo: ${entry.reason}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  formatFullDate(entry.timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!entry.isUndo && !undone.contains(entry.id))
                            OutlinedButton(
                              key: Key('undo_${entry.id}'),
                              onPressed: () {
                                state.undoAdjustment(entry.id);
                                setState(() => _syncFromState(state));
                              },
                              child: const Text('Desfazer'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: GranaSpacing.sm),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: GranaSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProvenanceLine extends StatelessWidget {
  const _ProvenanceLine({
    required this.field,
    required this.source,
    this.ruleExplanation,
  });

  final String field;
  final ClassificationSource source;
  final String? ruleExplanation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$field: ',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            Text(
              source.label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (ruleExplanation != null) ...[
          const SizedBox(height: 2),
          Text(
            ruleExplanation!,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
