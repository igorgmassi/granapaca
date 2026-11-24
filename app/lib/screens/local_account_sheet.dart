import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/planning_queries.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';

/// Opens a friendly 2-tap bottom sheet to add a local bank, checking/savings
/// account, or credit card directly in [AppMode.localDevice].
Future<Account?> showAddLocalAccountSheet(BuildContext context) {
  return showModalBottomSheet<Account>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: AddLocalAccountSheet(),
    ),
  );
}

class AddLocalAccountSheet extends StatefulWidget {
  const AddLocalAccountSheet({super.key});

  @override
  State<AddLocalAccountSheet> createState() => _AddLocalAccountSheetState();
}

class _AddLocalAccountSheetState extends State<AddLocalAccountSheet> {
  final TextEditingController _bankController = TextEditingController();
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _balanceController = TextEditingController();
  final TextEditingController _lastFourController = TextEditingController();

  AccountKind _kind = AccountKind.checking;
  String? _errorMessage;
  bool _saving = false;

  @override
  void dispose() {
    _bankController.dispose();
    _accountController.dispose();
    _balanceController.dispose();
    _lastFourController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState state) async {
    final bankName = _bankController.text.trim();
    if (bankName.isEmpty) {
      setState(() {
        _errorMessage = 'Informe o nome do banco ou instituição.';
      });
      return;
    }

    int openingBalanceCents = 0;
    final rawBalance = _balanceController.text.trim();
    if (rawBalance.isNotEmpty) {
      final parsed = parseBrlToCents(rawBalance);
      if (parsed == null) {
        setState(() {
          _errorMessage = 'Informe um saldo inicial válido (ex.: 1.250,00).';
        });
        return;
      }
      openingBalanceCents = parsed;
    }

    setState(() {
      _errorMessage = null;
      _saving = true;
    });

    try {
      final created = await state.addLocalBankAccount(
        bankName: bankName,
        accountName: _accountController.text.trim().isEmpty
            ? _kind.label
            : _accountController.text.trim(),
        kind: _kind,
        openingBalanceCents: openingBalanceCents,
        lastFourDigits: _kind == AccountKind.creditCard
            ? _lastFourController.text.trim()
            : null,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(created);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${created.name} ($bankName) adicionada e salva cifrada neste '
            'aparelho.',
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
    final textTheme = Theme.of(context).textTheme;

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
                  Icons.account_balance_outlined,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: GranaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adicionar banco ou cartão',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Salvo cifrado só neste aparelho · sem senha do banco',
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
              TextField(
                key: const Key('local_bank_name_field'),
                controller: _bankController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome do banco ou instituição',
                  hintText: 'Ex.: Banco do Bairro, Cooperativa Sol',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              Text(
                'Tipo de conta',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              Wrap(
                spacing: GranaSpacing.sm,
                runSpacing: GranaSpacing.sm,
                children: [
                  for (final kind in AccountKind.values)
                    ChoiceChip(
                      key: Key('local_account_kind_${kind.name}'),
                      label: Text(kind.label),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: GranaSpacing.md),
              TextField(
                key: const Key('local_account_name_field'),
                controller: _accountController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nome da conta ou cartão (opcional)',
                  hintText: 'Ex.: ${_kind.label}',
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              if (_kind == AccountKind.creditCard) ...[
                TextField(
                  key: const Key('local_last_four_field'),
                  controller: _lastFourController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Últimos 4 dígitos do cartão (opcional)',
                    hintText: 'Ex.: 4821',
                    prefixIcon: Icon(Icons.credit_card_outlined),
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
              ] else ...[
                TextField(
                  key: const Key('local_opening_balance_field'),
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Saldo inicial (opcional, R\$)',
                    prefixText: 'R\$ ',
                    hintText: 'Ex.: 1.500,00',
                  ),
                ),
              ],
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
                key: const Key('local_account_save_button'),
                onPressed: _saving ? null : () => _submit(state),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Adicionar conta'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
