import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'review_queue_screen.dart';
import 'transaction_detail_sheet.dart';

/// Unified transaction history with accent-insensitive search, combinable
/// filters (including payment method, tag, and atypical), multi-select bulk
/// editing, incremental pagination, review queue indicator, and adjustment
/// modal (RF-18, RF-19, RF-22..26, RF-31).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _bulkMode = false;
  final Set<int> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleBulkMode() {
    setState(() {
      _bulkMode = !_bulkMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(int txId) {
    setState(() {
      if (_selectedIds.contains(txId)) {
        _selectedIds.remove(txId);
      } else {
        _selectedIds.add(txId);
      }
    });
  }

  Future<void> _openBulkEditDialog(BuildContext context, AppState state) async {
    if (_selectedIds.isEmpty) return;
    if (!state.canEditTransactions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppState.offlineEditBlockedMessage)),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    SpendingCategory? chosenCategory;
    Essentiality? chosenEssentiality;
    PaymentMethod? chosenPaymentMethod;
    bool? chosenAtypical;

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Correção em lote (${_selectedIds.length} itens)'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Escolha apenas os campos que deseja atualizar nas '
                    'transações selecionadas.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: GranaSpacing.md),
                  DropdownButtonFormField<SpendingCategory?>(
                    key: const Key('bulk_category_dropdown'),
                    initialValue: chosenCategory,
                    decoration: const InputDecoration(
                      labelText: 'Categoria (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<SpendingCategory?>(
                        value: null,
                        child: Text('Manter atual'),
                      ),
                      for (final c in SpendingCategory.values)
                        DropdownMenuItem<SpendingCategory?>(
                          value: c,
                          child: Text(c.label),
                        ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => chosenCategory = val),
                  ),
                  const SizedBox(height: GranaSpacing.md),
                  DropdownButtonFormField<Essentiality?>(
                    key: const Key('bulk_essentiality_dropdown'),
                    initialValue: chosenEssentiality,
                    decoration: const InputDecoration(
                      labelText: 'Essencialidade (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<Essentiality?>(
                        value: null,
                        child: Text('Manter atual'),
                      ),
                      for (final e in Essentiality.values)
                        DropdownMenuItem<Essentiality?>(
                          value: e,
                          child: Text(e.label),
                        ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => chosenEssentiality = val),
                  ),
                  const SizedBox(height: GranaSpacing.md),
                  DropdownButtonFormField<PaymentMethod?>(
                    key: const Key('bulk_payment_method_dropdown'),
                    initialValue: chosenPaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'Meio de pagamento (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<PaymentMethod?>(
                        value: null,
                        child: Text('Manter atual'),
                      ),
                      for (final pm in PaymentMethod.values)
                        DropdownMenuItem<PaymentMethod?>(
                          value: pm,
                          child: Text(pm.label),
                        ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => chosenPaymentMethod = val),
                  ),
                  const SizedBox(height: GranaSpacing.md),
                  DropdownButtonFormField<bool?>(
                    key: const Key('bulk_atypical_dropdown'),
                    initialValue: chosenAtypical,
                    decoration: const InputDecoration(
                      labelText: 'Despesa atípica (opcional)',
                    ),
                    items: const [
                      DropdownMenuItem<bool?>(
                        value: null,
                        child: Text('Manter atual'),
                      ),
                      DropdownMenuItem<bool?>(
                        value: true,
                        child: Text('Marcar como atípica'),
                      ),
                      DropdownMenuItem<bool?>(
                        value: false,
                        child: Text('Marcar como normal'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => chosenAtypical = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const Key('bulk_confirm_button'),
              onPressed:
                  chosenCategory == null &&
                      chosenEssentiality == null &&
                      chosenPaymentMethod == null &&
                      chosenAtypical == null
                  ? null
                  : () {
                      state.applyBulkAdjustments(
                        txIds: Set<int>.from(_selectedIds),
                        category: chosenCategory,
                        changeCategory: chosenCategory != null,
                        essentiality: chosenEssentiality,
                        changeEssentiality: chosenEssentiality != null,
                        paymentMethod: chosenPaymentMethod,
                        changePaymentMethod: chosenPaymentMethod != null,
                        isAtypical: chosenAtypical,
                        changeAtypical: chosenAtypical != null,
                      );
                      Navigator.of(dialogContext).pop(true);
                    },
              child: const Text('Aplicar em lote'),
            ),
          ],
        ),
      ),
    );

    if (applied == true && mounted) {
      final count = _selectedIds.length;
      setState(() {
        _bulkMode = false;
        _selectedIds.clear();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Correção em lote aplicada a $count transação(ões).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final filter = state.historyFilter;
    final data = state.effectiveDataset;

    // Keep text controller synced when filters are cleared externally.
    final desiredSearch = filter.search ?? '';
    if (_searchController.text != desiredSearch) {
      _searchController.value = TextEditingValue(
        text: desiredSearch,
        selection: TextSelection.collapsed(offset: desiredSearch.length),
      );
    }

    final result = effectiveHistory(
      data,
      state.effectiveTransactions,
      filter,
      limit: state.historyVisibleCount,
    );
    final uncategorizedGroups = reviewQueue([
      for (final t in state.effectiveTransactions) t.toTransaction(),
    ]);

    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final accountsForBank = data.accounts
        .where((a) => filter.bankId == null || a.bankId == filter.bankId)
        .toList(growable: false);

    return Column(
      children: [
        // Search & filter header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GranaSpacing.lg,
            GranaSpacing.md,
            GranaSpacing.lg,
            GranaSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('history_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por descrição original ou corrigida',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: desiredSearch.isNotEmpty
                      ? IconButton(
                          key: const Key('history_search_clear'),
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            state.updateHistoryFilter(
                              filter.copyWith(clearSearch: true),
                            );
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  state.updateHistoryFilter(
                    value.trim().isEmpty
                        ? filter.copyWith(clearSearch: true)
                        : filter.copyWith(search: value),
                  );
                },
              ),
              const SizedBox(height: GranaSpacing.md),
              SingleChildScrollView(
                key: const Key('history_filter_row_scroll'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterPickerButton(
                      key: const Key('filter_period_button'),
                      label: _periodLabel(filter),
                      active: filter.from != null || filter.to != null,
                      onPressed: () => _pickPeriod(context, state, filter),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_bank_button'),
                      label: filter.bankId == null
                          ? 'Banco'
                          : data.bank(filter.bankId!).name,
                      active: filter.bankId != null,
                      onPressed: () => _pickBank(context, state, filter, data),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_account_button'),
                      label: filter.accountId == null
                          ? 'Conta'
                          : data.account(filter.accountId!).name,
                      active: filter.accountId != null,
                      onPressed: () => _pickAccount(
                        context,
                        state,
                        filter,
                        accountsForBank,
                        data,
                      ),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_kind_button'),
                      label: filter.kind != null
                          ? filter.kind!.label
                          : (filter.spendingOnly ? 'Somente gastos' : 'Tipo'),
                      active: filter.kind != null || filter.spendingOnly,
                      onPressed: () => _pickKind(context, state, filter),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_category_button'),
                      label:
                          filter.uncategorizedOnly &&
                              (filter.categories == null ||
                                  filter.categories!.isEmpty)
                          ? 'Sem categoria'
                          : (filter.category != null
                                ? filter.category!.label
                                : (filter.categories != null &&
                                          filter.categories!.isNotEmpty
                                      ? _categoriesLabel(
                                          filter.categories!,
                                          includeUncategorized:
                                              filter.uncategorizedOnly,
                                        )
                                      : 'Categoria')),
                      active:
                          filter.category != null ||
                          (filter.categories != null &&
                              filter.categories!.isNotEmpty) ||
                          filter.uncategorizedOnly,
                      onPressed: () => _pickCategory(context, state, filter),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_essentiality_button'),
                      label: filter.essentiality?.label ?? 'Essencialidade',
                      active: filter.essentiality != null,
                      onPressed: () =>
                          _pickEssentiality(context, state, filter),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_payment_method_button'),
                      label: filter.paymentMethod?.label ?? 'Pagamento',
                      active: filter.paymentMethod != null,
                      onPressed: () =>
                          _pickPaymentMethod(context, state, filter),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    _FilterPickerButton(
                      key: const Key('filter_tag_button'),
                      label: filter.tag != null ? '#${filter.tag}' : 'Tag',
                      active: filter.tag != null && filter.tag!.isNotEmpty,
                      onPressed: () => _pickTag(context, state, filter),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    FilterChip(
                      key: const Key('filter_atypical_button'),
                      label: const Text('Atípicas'),
                      selected: filter.atypicalOnly,
                      onSelected: (val) => state.updateHistoryFilter(
                        filter.copyWith(atypicalOnly: val),
                      ),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    FilterChip(
                      key: const Key('history_bulk_mode_button'),
                      avatar: Icon(
                        _bulkMode
                            ? Icons.close_rounded
                            : Icons.checklist_rtl_rounded,
                        size: 16,
                      ),
                      label: Text(_bulkMode ? 'Cancelar lote' : 'Lote'),
                      selected: _bulkMode,
                      showCheckmark: false,
                      onSelected: (_) => _toggleBulkMode(),
                    ),
                  ],
                ),
              ),
              if (filter.hasActiveFilters) ...[
                const SizedBox(height: GranaSpacing.sm),
                Wrap(
                  spacing: GranaSpacing.sm,
                  runSpacing: GranaSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (filter.from != null)
                      InputChip(
                        label: Text(_periodLabel(filter)),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearFrom: true, clearTo: true),
                        ),
                      ),
                    if (filter.bankId != null)
                      InputChip(
                        label: Text(data.bank(filter.bankId!).name),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(
                            clearBankId: true,
                            clearAccountId: true,
                          ),
                        ),
                      ),
                    if (filter.accountId != null)
                      InputChip(
                        label: Text(data.account(filter.accountId!).name),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearAccountId: true),
                        ),
                      ),
                    if (filter.spendingOnly && filter.kind == null)
                      InputChip(
                        label: const Text('Somente gastos'),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(spendingOnly: false),
                        ),
                      ),
                    if (filter.kind != null)
                      InputChip(
                        label: Text(filter.kind!.label),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearKind: true),
                        ),
                      ),
                    if (filter.uncategorizedOnly)
                      InputChip(
                        label: const Text('Sem categoria'),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(uncategorizedOnly: false),
                        ),
                      ),
                    if (filter.category != null)
                      InputChip(
                        label: Text(filter.category!.label),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearCategory: true),
                        ),
                      ),
                    if (filter.categories != null &&
                        filter.categories!.isNotEmpty)
                      InputChip(
                        key: const Key('filter_chip_categories'),
                        label: Text(_categoriesLabel(filter.categories!)),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearCategories: true),
                        ),
                      ),
                    if (filter.essentiality != null)
                      InputChip(
                        label: Text(filter.essentiality!.label),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearEssentiality: true),
                        ),
                      ),
                    if (filter.paymentMethod != null)
                      InputChip(
                        label: Text(filter.paymentMethod!.label),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearPaymentMethod: true),
                        ),
                      ),
                    if (filter.tag != null && filter.tag!.isNotEmpty)
                      InputChip(
                        label: Text('#${filter.tag}'),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(clearTag: true),
                        ),
                      ),
                    if (filter.atypicalOnly)
                      InputChip(
                        label: const Text('Somente atípicas'),
                        onDeleted: () => state.updateHistoryFilter(
                          filter.copyWith(atypicalOnly: false),
                        ),
                      ),
                    TextButton(
                      key: const Key('clear_filters_inline'),
                      onPressed: state.clearHistoryFilters,
                      child: const Text('Limpar filtros'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Live filtered total bar
        Container(
          width: double.infinity,
          color: scheme.surfaceContainer,
          padding: const EdgeInsets.symmetric(
            horizontal: GranaSpacing.lg,
            vertical: GranaSpacing.sm,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: GranaSpacing.md,
            runSpacing: GranaSpacing.xs,
            children: [
              Text(
                '${result.totalCount} '
                '${result.totalCount == 1 ? 'transação' : 'transações'}',
                key: const Key('history_count_label'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Total filtrado: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  MoneyText(
                    key: const Key('history_filtered_total'),
                    cents: result.totalCents,
                    hideValues: state.hideValues,
                    useUnicodeMinus: true,
                    style: tokens.valorLinha,
                  ),
                ],
              ),
            ],
          ),
        ),

        if (state.pendingOutboxCount > 0)
          Material(
            key: const Key('history_outbox_banner'),
            color: tokens.milho.withValues(alpha: 0.25),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GranaSpacing.lg,
                vertical: GranaSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 18,
                    color: tokens.sobreMilho,
                  ),
                  const SizedBox(width: GranaSpacing.sm),
                  Expanded(
                    child: Text(
                      '${state.pendingOutboxCount} lançamento(s) em dinheiro '
                      'aguardando envio ao servidor.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.sobreMilho,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (uncategorizedGroups.isNotEmpty)
          Material(
            color: scheme.secondaryContainer,
            child: InkWell(
              key: const Key('history_open_review_queue'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReviewQueueScreen(),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GranaSpacing.lg,
                  vertical: GranaSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pending_actions_outlined,
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    Expanded(
                      child: Text(
                        'A revisar: ${uncategorizedGroups.length} '
                        'estabelecimento(s) sem categoria.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    Text(
                      'Revisar',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),

        const Divider(height: 1),

        // Results list or empty state
        Expanded(
          child: result.items.isEmpty
              ? EmptyStateView(
                  icon: Icons.filter_list_off_rounded,
                  title: 'Nenhuma transação encontrada',
                  subtitle:
                      'Nenhuma movimentação combina com os filtros ativos. '
                      'Limpe os filtros para ver todo o extrato.',
                  actionLabel: 'Limpar filtros',
                  onAction: state.clearHistoryFilters,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  itemCount:
                      result.items.length +
                      (result.totalCount > result.items.length ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == result.items.length) {
                      final remaining = result.totalCount - result.items.length;
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: GranaSpacing.md,
                          ),
                          child: OutlinedButton(
                            key: const Key('load_more_history'),
                            onPressed: state.loadMoreHistory,
                            child: Text('Carregar mais ($remaining restantes)'),
                          ),
                        ),
                      );
                    }
                    final tx = result.items[index];
                    final account = data.account(tx.accountId);
                    final bank = data.bank(account.bankId);
                    final isSelected = _selectedIds.contains(tx.id);
                    return Card(
                      color: isSelected
                          ? scheme.primaryContainer.withValues(alpha: 0.35)
                          : null,
                      child: TransactionRow(
                        tx: tx,
                        account: account,
                        bank: bank,
                        hideValues: state.hideValues,
                        leading: _bulkMode
                            ? Checkbox(
                                key: Key('bulk_select_${tx.id}'),
                                value: isSelected,
                                onChanged: (_) => _toggleSelected(tx.id),
                              )
                            : null,
                        onTap: _bulkMode
                            ? () => _toggleSelected(tx.id)
                            : () => showTransactionDetailSheet(context, tx.id),
                      ),
                    );
                  },
                ),
        ),

        if (_bulkMode)
          Material(
            key: const Key('history_bulk_action_bar'),
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GranaSpacing.lg,
                vertical: GranaSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedIds.length} selecionada(s)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const Key('history_bulk_apply_button'),
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () => _openBulkEditDialog(context, state),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Editar em lote'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _periodLabel(TxFilter filter) {
    if (filter.from == null) return 'Período';
    return formatShortMonth(filter.from!);
  }

  String _categoriesLabel(
    Set<SpendingCategory> categories, {
    bool includeUncategorized = false,
  }) {
    final total = categories.length + (includeUncategorized ? 1 : 0);
    if (total == 1 && !includeUncategorized) return categories.first.label;
    return 'Demais categorias ($total)';
  }

  Future<void> _pickPeriod(
    BuildContext context,
    AppState state,
    TxFilter filter,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por período',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todos os meses'),
            trailing: filter.from == null ? const Icon(Icons.check) : null,
            onTap: () {
              state.updateHistoryFilter(
                filter.copyWith(clearFrom: true, clearTo: true),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final m in state.availableMonths)
            ListTile(
              title: Text(formatMonthYear(m)),
              trailing:
                  filter.from != null &&
                      filter.from!.year == m.year &&
                      filter.from!.month == m.month
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                final (from, to) = monthRange(m);
                state.updateHistoryFilter(filter.copyWith(from: from, to: to));
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickBank(
    BuildContext context,
    AppState state,
    TxFilter filter,
    Dataset data,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por banco',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todos os bancos'),
            trailing: filter.bankId == null ? const Icon(Icons.check) : null,
            onTap: () {
              state.updateHistoryFilter(
                filter.copyWith(clearBankId: true, clearAccountId: true),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final b in data.banks)
            ListTile(
              title: Text(b.name),
              trailing: filter.bankId == b.id ? const Icon(Icons.check) : null,
              onTap: () {
                state.updateHistoryFilter(
                  filter.copyWith(bankId: b.id, clearAccountId: true),
                );
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickAccount(
    BuildContext context,
    AppState state,
    TxFilter filter,
    List<Account> accounts,
    Dataset data,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por conta',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todas as contas'),
            trailing: filter.accountId == null ? const Icon(Icons.check) : null,
            onTap: () {
              state.updateHistoryFilter(filter.copyWith(clearAccountId: true));
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final a in accounts)
            ListTile(
              title: Text('${a.name} (${data.bank(a.bankId).name})'),
              trailing: filter.accountId == a.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                state.updateHistoryFilter(filter.copyWith(accountId: a.id));
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickKind(
    BuildContext context,
    AppState state,
    TxFilter filter,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por tipo de movimento',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todos os tipos'),
            trailing: filter.kind == null && !filter.spendingOnly
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              state.updateHistoryFilter(
                filter.copyWith(clearKind: true, spendingOnly: false),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final k in TxKind.values)
            ListTile(
              title: Text(k.label),
              trailing: filter.kind == k ? const Icon(Icons.check) : null,
              onTap: () {
                state.updateHistoryFilter(
                  filter.copyWith(kind: k, spendingOnly: false),
                );
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickCategory(
    BuildContext context,
    AppState state,
    TxFilter filter,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por categoria',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todas as categorias'),
            trailing:
                filter.category == null &&
                    (filter.categories == null || filter.categories!.isEmpty) &&
                    !filter.uncategorizedOnly
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              state.updateHistoryFilter(
                filter.copyWith(
                  clearCategory: true,
                  clearCategories: true,
                  uncategorizedOnly: false,
                ),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final c in SpendingCategory.values)
            ListTile(
              title: Text(c.label),
              trailing: !filter.uncategorizedOnly && filter.category == c
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                state.updateHistoryFilter(
                  filter.copyWith(
                    category: c,
                    clearCategories: true,
                    uncategorizedOnly: false,
                  ),
                );
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickEssentiality(
    BuildContext context,
    AppState state,
    TxFilter filter,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por essencialidade',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todas'),
            trailing: filter.essentiality == null
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              state.updateHistoryFilter(
                filter.copyWith(clearEssentiality: true),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final e in Essentiality.values)
            ListTile(
              title: Text(e.label),
              trailing: filter.essentiality == e
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                state.updateHistoryFilter(filter.copyWith(essentiality: e));
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickPaymentMethod(
    BuildContext context,
    AppState state,
    TxFilter filter,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por meio de pagamento',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todos os meios'),
            trailing: filter.paymentMethod == null
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              state.updateHistoryFilter(
                filter.copyWith(clearPaymentMethod: true),
              );
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final pm in PaymentMethod.values)
            ListTile(
              key: Key('pick_pm_${pm.name}'),
              leading: Icon(iconForPaymentMethod(pm)),
              title: Text(pm.label),
              trailing: filter.paymentMethod == pm
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                state.updateHistoryFilter(filter.copyWith(paymentMethod: pm));
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _pickTag(
    BuildContext context,
    AppState state,
    TxFilter filter,
  ) {
    final tags = state.allTags;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar por tag',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todas as tags'),
            trailing: filter.tag == null ? const Icon(Icons.check) : null,
            onTap: () {
              state.updateHistoryFilter(filter.copyWith(clearTag: true));
              Navigator.of(sheetContext).pop();
            },
          ),
          if (tags.isEmpty)
            const Padding(
              padding: EdgeInsets.all(GranaSpacing.lg),
              child: Text(
                'Nenhuma tag cadastrada ainda. Adicione tags nos detalhes de '
                'uma transação ou ao lançar um gasto em dinheiro.',
              ),
            )
          else
            for (final tag in tags)
              ListTile(
                key: Key('pick_tag_$tag'),
                leading: const Icon(Icons.label_outline_rounded),
                title: Text('#$tag'),
                trailing: filter.tag == tag ? const Icon(Icons.check) : null,
                onTap: () {
                  state.updateHistoryFilter(filter.copyWith(tag: tag));
                  Navigator.of(sheetContext).pop();
                },
              ),
        ],
      ),
    );
  }
}

class _FilterPickerButton extends StatelessWidget {
  const _FilterPickerButton({
    super.key,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down_rounded, size: 18),
        ],
      ),
      selected: active,
      showCheckmark: false,
      selectedColor: scheme.primaryContainer,
      onSelected: (_) => onPressed(),
    );
  }
}
