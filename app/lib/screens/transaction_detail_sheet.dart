import 'package:material_ui/material_ui.dart';

import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/planning_queries.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'receipts_export_screen.dart';

/// Opens the transaction detail & manual adjustment bottom sheet
/// (RF-22, RF-23, RF-24, RF-25, RF-26, RN-24).
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
  late TextEditingController _tagController;
  late TxKind _kind;
  SpendingCategory? _category;
  Essentiality? _essentiality;
  late PaymentMethod _paymentMethod;
  late List<String> _tags;
  late bool _isAtypical;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
    _reasonController = TextEditingController();
    _tagController = TextEditingController();
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
    _paymentMethod = tx.paymentMethod;
    _tags = List<String>.from(tx.tags);
    _isAtypical = tx.isAtypical;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _reasonController.dispose();
    _tagController.dispose();
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
    final pmChanged = _paymentMethod != tx.paymentMethod;
    final tagsChanged = encodeTags(_tags) != encodeTags(tx.tags);
    final atypicalChanged = _isAtypical != tx.isAtypical;
    return descChanged ||
        kindChanged ||
        catChanged ||
        essChanged ||
        pmChanged ||
        tagsChanged ||
        atypicalChanged;
  }

  void _addTagFromInput() {
    final parsed = decodeTags(_tagController.text);
    if (parsed.isEmpty) return;
    setState(() {
      _tags = decodeTags(encodeTags([..._tags, ...parsed]));
      _tagController.clear();
    });
  }

  Future<void> _saveCorrection(AppState state, EffectiveTransaction tx) async {
    if (!state.canEditTransactions) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppState.offlineEditBlockedMessage)),
        );
      }
      return;
    }

    final descTrimmed = _descriptionController.text.trim();
    final descChanged =
        descTrimmed.isNotEmpty && descTrimmed != tx.description;
    final kindChanged = _kind != tx.kind;
    final isSpend = isSpendingKind(_kind);
    final catChanged = isSpend && _category != tx.category;
    final essChanged = isSpend && _essentiality != tx.essentiality;
    final pmChanged = _paymentMethod != tx.paymentMethod;
    final tagsChanged = encodeTags(_tags) != encodeTags(tx.tags);
    final atypicalChanged = _isAtypical != tx.isAtypical;

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
      paymentMethod: _paymentMethod,
      changePaymentMethod: pmChanged,
      tags: _tags,
      changeTags: tagsChanged,
      isAtypical: _isAtypical,
      changeAtypical: atypicalChanged,
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
              content: Text(
                'Regra criada e aplicada às transações semelhantes.',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _openSplitEditor(
    BuildContext context,
    AppState state,
    EffectiveTransaction tx,
  ) {
    if (!state.canEditTransactions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppState.offlineEditBlockedMessage)),
      );
      return Future<void>.value();
    }
    return showDialog<void>(
      context: context,
      builder: (_) => _SplitEditorDialog(state: state, tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tx = state.effectiveById(widget.txId);
    final account = state.originalDataset.account(tx.accountId);
    final bank = state.originalDataset.bank(account.bankId);
    final historyEntries = state.adjustmentsFor(tx.id);
    final undone = state.undoneIds;
    final activeUndoableIds = latestActiveAdjustmentIdsFor(
      tx.id,
      state.adjustments,
    );
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
                      _InfoLine(
                        label: 'Meio de pagamento',
                        value: tx.paymentMethod.label,
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

              // Manual correction form (RF-22, RF-23, RF-24)
              Text(
                'Corrigir transação',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!state.canEditTransactions) ...[
                const SizedBox(height: GranaSpacing.sm),
                Card(
                  key: const Key('tx_offline_edit_warning'),
                  color: tokens.milho.withValues(alpha: 0.25),
                  child: Padding(
                    padding: const EdgeInsets.all(GranaSpacing.md),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off_outlined, color: tokens.sobreMilho),
                        const SizedBox(width: GranaSpacing.sm),
                        Expanded(
                          child: Text(
                            AppState.offlineEditBlockedMessage,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: tokens.sobreMilho,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

              // Payment method (RF-22)
              const SizedBox(height: GranaSpacing.lg),
              Text(
                'Meio de pagamento',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              Wrap(
                spacing: GranaSpacing.sm,
                runSpacing: GranaSpacing.sm,
                children: [
                  for (final pm in PaymentMethod.values)
                    ChoiceChip(
                      key: Key('pm_choice_${pm.name}'),
                      avatar: Icon(iconForPaymentMethod(pm), size: 16),
                      label: Text(pm.label),
                      selected: _paymentMethod == pm,
                      onSelected: (_) => setState(() => _paymentMethod = pm),
                    ),
                ],
              ),

              // Atypical expense switch
              if (showSpendingFields) ...[
                const SizedBox(height: GranaSpacing.md),
                SwitchListTile(
                  key: const Key('tx_atypical_switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Despesa atípica'),
                  subtitle: const Text(
                    'Exclui este gasto pontual do ritmo diário na projeção do mês.',
                  ),
                  value: _isAtypical,
                  onChanged: (val) => setState(() => _isAtypical = val),
                ),
              ],

              // Tags editor (RF-23)
              const SizedBox(height: GranaSpacing.md),
              Text(
                'Tags',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              if (_tags.isNotEmpty) ...[
                Wrap(
                  spacing: GranaSpacing.sm,
                  runSpacing: GranaSpacing.xs,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        key: Key('tx_tag_chip_$tag'),
                        label: Text('#$tag'),
                        onDeleted: () => setState(() {
                          _tags = _tags
                              .where((t) => t != tag)
                              .toList(growable: false);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.sm),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('tx_tag_input'),
                      controller: _tagController,
                      decoration: const InputDecoration(
                        labelText: 'Adicionar tag',
                        hintText: 'Ex.: viagem, reembolso',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addTagFromInput(),
                    ),
                  ),
                  const SizedBox(width: GranaSpacing.sm),
                  OutlinedButton(
                    key: const Key('tx_tag_add_button'),
                    onPressed: _addTagFromInput,
                    child: const Text('Adicionar'),
                  ),
                ],
              ),

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

              // Splits & NFC-e section (RN-24)
              if (showSpendingFields) ...[
                const SizedBox(height: GranaSpacing.xl),
                Card(
                  key: const Key('tx_splits_section'),
                  child: Padding(
                    padding: const EdgeInsets.all(GranaSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Divisão em partes e nota fiscal',
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: GranaSpacing.xs),
                        Text(
                          tx.splits.isEmpty
                              ? 'Divida uma compra mista em categorias diferentes '
                                    '(soma exata em centavos) ou anexe uma NFC-e.'
                              : '${tx.splits.length} parte(s) registrada(s) com '
                                    'soma exata de '
                                    '${state.hideValues ? r'R$ •••' : formatBrl(tx.amountCents.abs())}.',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (tx.splits.isNotEmpty) ...[
                          const SizedBox(height: GranaSpacing.sm),
                          for (final s in tx.splits)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${s.description} · '
                                      '${spendingCategoryLabel(s.category)}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  MoneyText(
                                    cents: s.amountCents,
                                    hideValues: state.hideValues,
                                    style: tokens.valorLinha.copyWith(
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: GranaSpacing.md),
                        Wrap(
                          spacing: GranaSpacing.sm,
                          runSpacing: GranaSpacing.sm,
                          children: [
                            OutlinedButton.icon(
                              key: const Key('tx_edit_splits_button'),
                              onPressed: () =>
                                  _openSplitEditor(context, state, tx),
                              icon: const Icon(Icons.call_split_rounded),
                              label: Text(
                                tx.splits.isEmpty
                                    ? 'Dividir em partes'
                                    : 'Editar divisão',
                              ),
                            ),
                            OutlinedButton.icon(
                              key: const Key('tx_attach_nfce_button'),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ReceiptsExportScreen(
                                      targetTransactionId: tx.id,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Anexar nota / NFC-e'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

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
                          if (activeUndoableIds.contains(entry.id))
                            OutlinedButton(
                              key: Key('undo_${entry.id}'),
                              onPressed: () {
                                if (!state.canEditTransactions) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        AppState.offlineEditBlockedMessage,
                                      ),
                                    ),
                                  );
                                  return;
                                }
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

class _SplitDraftRow {
  _SplitDraftRow({
    required this.descriptionController,
    required this.amountController,
    required this.category,
    required this.essentiality,
  });

  final TextEditingController descriptionController;
  final TextEditingController amountController;
  SpendingCategory category;
  Essentiality essentiality;

  void dispose() {
    descriptionController.dispose();
    amountController.dispose();
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

class _SplitEditorDialog extends StatefulWidget {
  const _SplitEditorDialog({required this.state, required this.tx});

  final AppState state;
  final EffectiveTransaction tx;

  @override
  State<_SplitEditorDialog> createState() => _SplitEditorDialogState();
}

class _SplitEditorDialogState extends State<_SplitEditorDialog> {
  late final List<_SplitDraftRow> _rows;

  @override
  void initState() {
    super.initState();
    final tx = widget.tx;
    final totalAbs = tx.amountCents.abs();
    final initialSplits = tx.splits.isNotEmpty
        ? tx.splits
        : [
            TxSplit(
              id: 'draft-1',
              description: '${tx.description} (parte 1)',
              amountCents: totalAbs ~/ 2,
              category: tx.category ?? SpendingCategory.food,
              essentiality: tx.essentiality ?? Essentiality.essential,
            ),
            TxSplit(
              id: 'draft-2',
              description: '${tx.description} (parte 2)',
              amountCents: totalAbs - (totalAbs ~/ 2),
              category: SpendingCategory.other,
              essentiality: Essentiality.flexible,
            ),
          ];

    _rows = [
      for (final s in initialSplits)
        _SplitDraftRow(
          descriptionController: TextEditingController(text: s.description),
          amountController: TextEditingController(
            text:
                '${s.amountCents ~/ 100},${(s.amountCents % 100).toString().padLeft(2, '0')}',
          ),
          category: s.category ?? SpendingCategory.other,
          essentiality: s.essentiality ?? Essentiality.important,
        ),
    ];
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<TxSplit> _buildCurrentSplits() {
    final list = <TxSplit>[];
    for (var i = 0; i < _rows.length; i++) {
      final cents = parseBrlToCents(_rows[i].amountController.text) ?? 0;
      list.add(
        TxSplit(
          id: 'split-${widget.tx.id}-${i + 1}',
          description: _rows[i].descriptionController.text.trim().isEmpty
              ? 'Parte ${i + 1}'
              : _rows[i].descriptionController.text.trim(),
          amountCents: cents,
          category: _rows[i].category,
          essentiality: _rows[i].essentiality,
        ),
      );
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final state = widget.state;
    final totalAbs = tx.amountCents.abs();
    final currentSplits = _buildCurrentSplits();
    final remaining = splitRemainingCents(tx.amountCents, currentSplits);
    final isValid = validateSplitTotal(tx.amountCents, currentSplits);
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);

    return AlertDialog(
      title: const Text('Dividir transação (RN-24)'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: GranaSpacing.sm,
                runSpacing: GranaSpacing.xs,
                children: [
                  Text(
                    'Total da transação: '
                    '${state.hideValues ? r'R$ •••' : formatBrl(totalAbs)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    remaining == 0
                        ? 'Soma exata fechada'
                        : (remaining > 0
                              ? 'Faltam ${formatBrl(remaining)}'
                              : 'Excede ${formatBrl(remaining.abs())}'),
                    key: const Key('splits_remaining_label'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: remaining == 0 ? tokens.mata : scheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GranaSpacing.md),
              for (var i = 0; i < _rows.length; i++) ...[
                Card(
                  color: scheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(GranaSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Parte ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_rows.length > 1)
                              IconButton(
                                tooltip: 'Remover parte',
                                onPressed: () {
                                  final removed = _rows.removeAt(i);
                                  removed.dispose();
                                  setState(() {});
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                        TextField(
                          key: Key('split_desc_$i'),
                          controller: _rows[i].descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descrição da parte',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: GranaSpacing.sm),
                        TextField(
                          key: Key('split_amount_$i'),
                          controller: _rows[i].amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor (R\$)',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: GranaSpacing.sm),
                        DropdownButtonFormField<SpendingCategory>(
                          initialValue: _rows[i].category,
                          decoration: const InputDecoration(
                            labelText: 'Categoria',
                            isDense: true,
                          ),
                          items: [
                            for (final c in SpendingCategory.values)
                              DropdownMenuItem(value: c, child: Text(c.label)),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _rows[i].category = val);
                            }
                          },
                        ),
                        const SizedBox(height: GranaSpacing.sm),
                        DropdownButtonFormField<Essentiality>(
                          initialValue: _rows[i].essentiality,
                          decoration: const InputDecoration(
                            labelText: 'Essencialidade',
                            isDense: true,
                          ),
                          items: [
                            for (final e in Essentiality.values)
                              DropdownMenuItem(value: e, child: Text(e.label)),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _rows[i].essentiality = val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
              ],
              OutlinedButton.icon(
                key: const Key('splits_add_row_button'),
                onPressed: () {
                  final rem = remaining > 0 ? remaining : 0;
                  _rows.add(
                    _SplitDraftRow(
                      descriptionController: TextEditingController(
                        text: 'Parte ${_rows.length + 1}',
                      ),
                      amountController: TextEditingController(
                        text:
                            '${rem ~/ 100},${(rem % 100).toString().padLeft(2, '0')}',
                      ),
                      category: SpendingCategory.other,
                      essentiality: Essentiality.important,
                    ),
                  );
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Adicionar parte'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (tx.splits.isNotEmpty)
          TextButton(
            key: const Key('splits_clear_button'),
            onPressed: () {
              state.replaceSplits(tx.id, const []);
              Navigator.of(context).pop();
            },
            child: const Text('Remover divisão'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('splits_save_button'),
          onPressed: isValid
              ? () {
                  state.replaceSplits(tx.id, currentSplits);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Salvar divisão'),
        ),
      ],
    );
  }
}
