import 'package:material_ui/material_ui.dart';

import '../security/app_lock.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';

/// Full-screen local app lock with 6-digit PIN keypad, optional biometric
/// prompt, remaining attempts feedback, and 5-attempt lockout protection
/// (RF-04, RNF-10).
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    required this.controller,
    this.onUnlocked,
  });

  final AppLockController controller;
  final VoidCallback? onUnlocked;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _digits = '';
  String? _errorMessage;
  bool _biometricBusy = false;

  bool get _isLocalOnlyMode =>
      widget.controller.isLocalOnlyMode?.call() ?? false;

  void _appendDigit(String digit) {
    if (widget.controller.isInCooldown) return;
    if (_digits.length >= AppLockController.pinLength) return;
    setState(() {
      _digits += digit;
      _errorMessage = null;
    });
    if (_digits.length == AppLockController.pinLength) {
      _submitPin(_digits);
    }
  }

  void _backspace() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _errorMessage = null;
    });
  }

  void _submitPin(String pin) {
    final ok = widget.controller.verifyPin(pin);
    if (ok) {
      setState(() {
        _digits = '';
        _errorMessage = null;
      });
      widget.onUnlocked?.call();
      return;
    }

    if (widget.controller.isInCooldown) {
      final secs = widget.controller.remainingCooldown.inSeconds.clamp(1, 3600);
      setState(() {
        _digits = '';
        _errorMessage =
            'Muitas tentativas incorretas. Aguarde ${secs}s para tentar '
            'novamente. Seus dados locais permanecem cifrados e protegidos.';
      });
      return;
    }

    if (widget.controller.lockedOut) {
      setState(() {
        _digits = '';
        _errorMessage =
            'Limite de tentativas atingido. Sua sessão foi encerrada por '
            'segurança.';
      });
      return;
    }

    final remaining = widget.controller.remainingAttempts;
    setState(() {
      _digits = '';
      _errorMessage = _isLocalOnlyMode
          ? 'PIN incorreto. Restam $remaining '
                '${remaining == 1 ? 'tentativa' : 'tentativas'} antes da '
                'pausa de segurança.'
          : 'PIN incorreto. Restam $remaining '
                '${remaining == 1 ? 'tentativa' : 'tentativas'} antes de '
                'encerrar a sessão.';
    });
  }

  Future<void> _showDoubleConfirmResetDialog(
    BuildContext context,
    AppState state,
  ) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (_) => const _LocalVaultResetDialog(),
    );
    if (shouldReset == true && mounted) {
      await state.resetLocalVaultAfterForgottenPin();
    }
  }

  Future<void> _tryBiometric() async {
    if (_biometricBusy) return;
    setState(() {
      _biometricBusy = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.controller.tryBiometricUnlock();
      if (!mounted) return;
      if (result == BiometricAuthResult.authenticated) {
        widget.onUnlocked?.call();
      } else if (result == BiometricAuthResult.cancelled) {
        setState(() {
          _errorMessage =
              'Biometria cancelada. Digite seu PIN de 6 dígitos para entrar.';
        });
      } else if (result == BiometricAuthResult.unavailable) {
        setState(() {
          _errorMessage =
              'Biometria indisponível neste dispositivo. Use o seu PIN.';
        });
      } else {
        setState(() {
          _errorMessage =
              'Não foi possível validar a biometria. Digite seu PIN.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _biometricBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(GranaSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 32,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.lg),
                    Text(
                      'GranaPaCá bloqueado',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.xs),
                    Text(
                      'Digite seu PIN de 6 dígitos para continuar.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.xl),

                    // 6-dot PIN indicator
                    Semantics(
                      label:
                          '${_digits.length} de ${AppLockController.pinLength} dígitos preenchidos',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < AppLockController.pinLength; i++)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _digits.length
                                    ? scheme.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: i < _digits.length
                                      ? scheme.primary
                                      : scheme.outline,
                                  width: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.lg),

                    if (_errorMessage != null) ...[
                      Container(
                        key: const Key('app_lock_error'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(GranaSpacing.md),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(GranaRadius.chip),
                        ),
                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: GranaSpacing.lg),
                    ],

                    // Numeric keypad
                    _PinKeypad(
                      onDigit: _appendDigit,
                      onBackspace: _backspace,
                      showBiometric:
                          widget.controller.canUseBiometrics &&
                          !widget.controller.isInCooldown,
                      onBiometric: _tryBiometric,
                    ),

                    if (widget.controller.canUseBiometrics &&
                        !widget.controller.isInCooldown) ...[
                      const SizedBox(height: GranaSpacing.md),
                      TextButton.icon(
                        key: const Key('pin_biometric_button'),
                        onPressed: _biometricBusy ? null : _tryBiometric,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Desbloquear com biometria'),
                      ),
                    ],

                    if (_isLocalOnlyMode && widget.controller.lockedOut) ...[
                      const SizedBox(height: GranaSpacing.lg),
                      Builder(
                        builder: (innerContext) {
                          final scope = innerContext
                              .dependOnInheritedWidgetOfExactType<AppScope>();
                          final state = scope?.notifier;
                          if (state == null) return const SizedBox.shrink();
                          return TextButton.icon(
                            key: const Key('local_forgot_pin_reset_button'),
                            onPressed: () => _showDoubleConfirmResetDialog(
                              innerContext,
                              state,
                            ),
                            icon: Icon(
                              Icons.delete_forever_outlined,
                              color: scheme.error,
                            ),
                            label: Text(
                              'Esqueci o PIN (apagar cofre local)',
                              style: TextStyle(color: scheme.error),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalVaultResetDialog extends StatefulWidget {
  const _LocalVaultResetDialog();

  @override
  State<_LocalVaultResetDialog> createState() => _LocalVaultResetDialogState();
}

class _LocalVaultResetDialogState extends State<_LocalVaultResetDialog> {
  final TextEditingController _confirmController = TextEditingController();
  bool _confirmedCheckbox = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm =
        _confirmedCheckbox &&
        _confirmController.text.trim().toUpperCase() == 'APAGAR';
    return AlertDialog(
      title: const Text('Apagar cofre local?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No modo "Só neste aparelho", não existe cópia em servidor. '
              'Esta ação apaga permanentemente todos os dados locais '
              'cifrados e remove o PIN atual. Só continue se você '
              'realmente esqueceu o PIN ou já tem um backup JSON salvo.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: GranaSpacing.md),
            CheckboxListTile(
              key: const Key('local_wipe_confirm_checkbox'),
              contentPadding: EdgeInsets.zero,
              value: _confirmedCheckbox,
              onChanged: (v) =>
                  setState(() => _confirmedCheckbox = v ?? false),
              title: const Text(
                'Entendo que os dados deste aparelho serão apagados '
                'permanentemente.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: GranaSpacing.sm),
            TextField(
              key: const Key('local_wipe_confirm_field'),
              controller: _confirmController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Digite APAGAR para confirmar',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm_local_vault_wipe_button'),
          onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Apagar e recomeçar'),
        ),
      ],
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.showBiometric,
    required this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool showBiometric;
  final VoidCallback onBiometric;

  Widget _digitButton(BuildContext context, String digit) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 56,
      child: OutlinedButton(
        key: Key('pin_key_$digit'),
        onPressed: () => onDigit(digit),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GranaRadius.card),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          backgroundColor: scheme.surfaceContainerLow,
        ),
        child: Text(
          digit,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
            fontFeatures: GranaTokens.tabularFeatures,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ]) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (i, d) in row.indexed) ...[
                if (i > 0) const SizedBox(width: GranaSpacing.md),
                _digitButton(context, d),
              ],
            ],
          ),
          const SizedBox(height: GranaSpacing.md),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 56,
              child: showBiometric
                  ? IconButton(
                      key: const Key('pin_keypad_biometric'),
                      tooltip: 'Usar biometria',
                      onPressed: onBiometric,
                      icon: Icon(
                        Icons.fingerprint_rounded,
                        color: scheme.primary,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: GranaSpacing.md),
            _digitButton(context, '0'),
            const SizedBox(width: GranaSpacing.md),
            SizedBox(
              width: 72,
              height: 56,
              child: IconButton(
                key: const Key('pin_backspace'),
                tooltip: 'Apagar dígito',
                onPressed: onBackspace,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Modal bottom sheet allowing the user to enable/disable the 6-digit PIN,
/// configure biometric unlock, and set the inactivity timeout (RF-04).
Future<void> showAppLockSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _AppLockSettingsSheet(),
  );
}

class _AppLockSettingsSheet extends StatefulWidget {
  const _AppLockSettingsSheet();

  @override
  State<_AppLockSettingsSheet> createState() => _AppLockSettingsSheetState();
}

class _AppLockSettingsSheetState extends State<_AppLockSettingsSheet> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _enableBiometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _savePin(AppLockController lock) async {
    final pin = _pinController.text.trim();
    final confirm = _confirmPinController.text.trim();
    if (!AppLockController.isValidPinFormat(pin)) {
      setState(() => _error = 'O PIN deve ter exatamente 6 números.');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Os dois campos de PIN precisam ser iguais.');
      return;
    }
    await lock.configurePin(pin, enableBiometric: _enableBiometric);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bloqueio do app ativado com sucesso.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final lock = state.appLock;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    const timeoutOptions = [
      (Duration(minutes: 1), '1 min'),
      (Duration(minutes: 2), '2 min'),
      (Duration(minutes: 5), '5 min'),
      (Duration(minutes: 15), '15 min'),
    ];

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
              'Bloqueio do app',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: GranaSpacing.xs),
            Text(
              'Proteja a abertura do app com um PIN de 6 dígitos (e biometria '
              'quando disponível). Após 5 erros seguidos, a sessão é encerrada.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),

            if (lock.isEnabled) ...[
              Card(
                color: scheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bloqueio ativo',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: GranaSpacing.sm),
                      const Text('Tempo de inatividade para travar novamente:'),
                      const SizedBox(height: GranaSpacing.sm),
                      Wrap(
                        spacing: GranaSpacing.sm,
                        children: [
                          for (final (duration, label) in timeoutOptions)
                            ChoiceChip(
                              key: Key('lock_timeout_${duration.inMinutes}'),
                              label: Text(label),
                              selected: lock.inactivityTimeout == duration,
                              onSelected: (_) =>
                                  lock.setInactivityTimeout(duration),
                            ),
                        ],
                      ),
                      if (lock.biometricAvailable) ...[
                        const SizedBox(height: GranaSpacing.sm),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Permitir desbloqueio por biometria'),
                          value: lock.biometricEnabled,
                          onChanged: lock.setBiometricEnabled,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              FilledButton.icon(
                key: const Key('app_lock_now_button'),
                onPressed: () {
                  Navigator.of(context).pop();
                  lock.lockNow();
                },
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('Bloquear agora'),
              ),
              const SizedBox(height: GranaSpacing.sm),
              OutlinedButton.icon(
                key: const Key('app_lock_disable_button'),
                onPressed: () {
                  lock.disableLock();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Desativar bloqueio'),
              ),
            ] else ...[
              TextField(
                key: const Key('setup_pin_field'),
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: AppLockController.pinLength,
                decoration: const InputDecoration(
                  labelText: 'Novo PIN (6 dígitos)',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              TextField(
                key: const Key('setup_pin_confirm_field'),
                controller: _confirmPinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: AppLockController.pinLength,
                decoration: const InputDecoration(
                  labelText: 'Confirmar PIN',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
              ),
              if (lock.biometricAvailable) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usar biometria quando disponível'),
                  value: _enableBiometric,
                  onChanged: (v) => setState(() => _enableBiometric = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: GranaSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: GranaSpacing.md),
              FilledButton.icon(
                key: const Key('setup_pin_save_button'),
                onPressed: () => _savePin(lock),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Ativar bloqueio com PIN'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
