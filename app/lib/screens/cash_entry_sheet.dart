import 'package:material_ui/material_ui.dart';

import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/planning_queries.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import 'local_account_sheet.dart';

/// Opens the quick manual entry sheet (physical cash in demo/server mode per
/// RF-44, or ANY payment method and local account in [AppMode.localDevice]).
Future<void> showCashEntrySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: CashEntrySheet(),
    ),
  );
}

class CashEntrySheet extends StatefulWidget {
  const CashEntrySheet({super.key});

  @override
  State<CashEntrySheet> createState() => _CashEntrySheetState();
}

class _CashEntrySheetState extends State<CashEntrySheet> {
  static const List<PaymentMethod> _localPaymentMethods = [
    PaymentMethod.cash,
    PaymentMethod.pix,
    PaymentMethod.debit,
    PaymentMethod.credit,
    PaymentMethod.boleto,
  ];

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  TxKind _kind = TxKind.expense;
  String? _selectedAccountId;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  SpendingCategory _category = SpendingCategory.food;
  Essentiality _essentiality = Essentiality.essential;
  DateTime? _selectedDate;
  String? _errorMessage;
  bool _saving = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final state = AppScope.of(context);
      final accounts = state.originalDataset.accounts;
      if (accounts.isNotEmpty) {
        final first = accounts.first;
        _selectedAccountId = first.id;
        _paymentMethod = _defaultPaymentFor(first.kind);
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  static PaymentMethod _defaultPaymentFor(AccountKind kind) {
    switch (kind) {
      case AccountKind.cash:
        return PaymentMethod.cash;
      case AccountKind.creditCard:
        return PaymentMethod.credit;
      case AccountKind.checking:
      case AccountKind.savings:
        return PaymentMethod.pix;
    }
  }

  Future<void> _submit(AppState state) async {
    final cents = parseBrlToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      setState(() {
        _errorMessage = 'Informe um valor válido maior que zero (ex.: 25,50).';
      });
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() {
        _errorMessage = state.isLocalDeviceMode
            ? 'Informe uma descrição para o lançamento.'
            : 'Informe uma descrição para o gasto em dinheiro.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _saving = true;
    });

    final tags = decodeTags(_tagsController.text);
    final date = _selectedDate ?? state.originalDataset.today;

    try {
      if (state.isLocalDeviceMode) {
        final accounts = state.originalDataset.accounts;
        final targetAccountId =
            accounts.any((a) => a.id == _selectedAccountId)
            ? _selectedAccountId!
            : (accounts.isNotEmpty
                  ? accounts.first.id
                  : AppState.cashAccountId);
        await state.addManualTransaction(
          description: description,
          amountCents: cents,
          date: date,
          accountId: targetAccountId,
          paymentMethod: _paymentMethod,
          kind: _kind,
          category: _kind == TxKind.expense ? _category : null,
          essentiality: _kind == TxKind.expense ? _essentiality : null,
          tags: tags,
        );
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${_kind == TxKind.income ? 'Receita' : 'Gasto'} de '
              '${formatBrl(cents)} (${_paymentMethod.label}) salvo cifrado '
              'neste aparelho.',
            ),
          ),
        );
      } else {
        final created = await state.addCashTransaction(
          description: description,
          amountCents: cents,
          date: date,
          category: _category,
          essentiality: _essentiality,
          tags: tags,
        );
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              created.pendingSync
                  ? 'Gasto de ${formatBrl(cents)} salvo na fila offline e '
                        'será enviado ao servidor quando a conexão voltar.'
                  : 'Gasto em dinheiro de ${formatBrl(cents)} registrado.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final activeDate = _selectedDate ?? state.originalDataset.today;
    final isOfflineServer = state.isServerMode && state.isOffline;
    final isLocalMode = state.isLocalDeviceMode;
    final accounts = state.originalDataset.accounts;
    final effectiveAccountId = accounts.any((a) => a.id == _selectedAccountId)
        ? _selectedAccountId
        : (accounts.isNotEmpty ? accounts.first.id : null);

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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.payments_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: GranaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLocalMode
                          ? 'Lançar movimentação'
                          : 'Lançar gasto em dinheiro',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      isLocalMode
                          ? 'Qualquer conta e meio de pagamento · salvo cifrado'
                          : 'Dinheiro físico · Carteira local',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(context).pop(),
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
              if (isOfflineServer) ...[
                Card(
                  key: const Key('cash_offline_outbox_notice'),
                  color: tokens.milho.withValues(alpha: 0.25),
                  child: Padding(
                    padding: const EdgeInsets.all(GranaSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          color: tokens.sobreMilho,
                        ),
                        const SizedBox(width: GranaSpacing.sm),
                        Expanded(
                          child: Text(
                            'Você está sem conexão. Este lançamento em dinheiro '
                            'será salvo localmente na fila de envio e '
                            'sincronizado automaticamente ao reconectar.',
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
                const SizedBox(height: GranaSpacing.md),
              ],
              if (isLocalMode) ...[
                Wrap(
                  spacing: GranaSpacing.sm,
                  runSpacing: GranaSpacing.sm,
                  children: [
                    ChoiceChip(
                      key: const Key('entry_kind_expense'),
                      label: const Text('Gasto'),
                      selected: _kind == TxKind.expense,
                      onSelected: (_) => setState(() => _kind = TxKind.expense),
                    ),
                    ChoiceChip(
                      key: const Key('entry_kind_income'),
                      label: const Text('Receita'),
                      selected: _kind == TxKind.income,
                      onSelected: (_) => setState(() => _kind = TxKind.income),
                    ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.md),
              ],
              TextField(
                key: const Key('cash_amount_field'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor (R\$)',
                  prefixText: 'R\$ ',
                  hintText: 'Ex.: 32,50',
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              TextField(
                key: const Key('cash_description_field'),
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  hintText: isLocalMode
                      ? 'Ex.: Supermercado, Pix do aluguel ou salário'
                      : 'Ex.: Feira livre ou café na padaria',
                ),
              ),
              if (isLocalMode) ...[
                const SizedBox(height: GranaSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('entry_account_dropdown'),
                        initialValue: effectiveAccountId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Conta ou carteira',
                        ),
                        items: [
                          for (final acct in accounts)
                            DropdownMenuItem(
                              value: acct.id,
                              child: Text(
                                '${state.originalDataset.bank(acct.bankId).name} · ${acct.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          final acct = state.originalDataset.account(val);
                          setState(() {
                            _selectedAccountId = val;
                            _paymentMethod = _defaultPaymentFor(acct.kind);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: GranaSpacing.xs),
                    IconButton(
                      key: const Key('entry_add_account_shortcut'),
                      tooltip: 'Nova conta',
                      onPressed: () async {
                        final added = await showAddLocalAccountSheet(context);
                        if (added != null && mounted) {
                          setState(() {
                            _selectedAccountId = added.id;
                            _paymentMethod = _defaultPaymentFor(added.kind);
                          });
                        }
                      },
                      icon: const Icon(Icons.add_card_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.md),
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
                    for (final pm in _localPaymentMethods)
                      ChoiceChip(
                        key: Key('entry_pm_${pm.name}'),
                        label: Text(pm.label),
                        selected: _paymentMethod == pm,
                        onSelected: (_) => setState(() => _paymentMethod = pm),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: GranaSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(
                  isLocalMode ? 'Data do lançamento' : 'Data do gasto',
                ),
                subtitle: Text(formatFullDate(activeDate)),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: activeDate,
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime(2030, 12, 31),
                    );
                    if (picked != null && mounted) {
                      setState(() => _selectedDate = picked);
                    }
                  },
                  child: const Text('Alterar'),
                ),
              ),
              if (!isLocalMode || _kind == TxKind.expense) ...[
                const SizedBox(height: GranaSpacing.md),
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
                        key: Key('cash_cat_${c.name}'),
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.lg),
                Text(
                  'Essencialidade',
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
                        key: Key('cash_ess_${e.name}'),
                        label: Text(e.label),
                        selected: _essentiality == e,
                        onSelected: (_) => setState(() => _essentiality = e),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: GranaSpacing.lg),
              TextField(
                key: const Key('cash_tags_field'),
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (opcional, separadas por vírgula)',
                  hintText: 'Ex.: feira, semana',
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: GranaSpacing.md),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: GranaSpacing.xl),
              FilledButton.icon(
                key: const Key('cash_save_button'),
                onPressed: _saving ? null : () => _submit(state),
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  isLocalMode
                      ? 'Salvar lançamento'
                      : isOfflineServer
                      ? 'Salvar na fila offline'
                      : 'Salvar gasto em dinheiro',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
