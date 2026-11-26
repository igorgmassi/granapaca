import 'package:material_ui/material_ui.dart';

import '../demo/demo_data.dart';
import '../finance/planning_queries.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';

/// Opens the quick physical-cash entry bottom sheet (RF-44).
/// Works instantaneously offline by queueing an outbox mutation in server mode.
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
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  SpendingCategory _category = SpendingCategory.food;
  Essentiality _essentiality = Essentiality.essential;
  DateTime? _selectedDate;
  String? _errorMessage;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
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
        _errorMessage = 'Informe uma descrição para o gasto em dinheiro.';
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
                      'Lançar gasto em dinheiro',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Dinheiro físico · Carteira local',
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
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  hintText: 'Ex.: Feira livre ou café na padaria',
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Data do gasto'),
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
                  isOfflineServer
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
