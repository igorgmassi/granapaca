import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/pacoca_mascot.dart';
import '../widgets/totp_qr_code.dart';
import 'app_shell.dart';

enum _AuthFlowStep { server, ownerSetup, login, totpSetup, recoveryCodes }

enum _ModeFocus { localDevice, server, demo }

/// Real self-hosted server validation, initial owner creation, login,
/// mandatory TOTP 2FA enrollment, recovery codes confirmation, and zero-server
/// encrypted local mode entry — styled in Toca Editorial with interactive
/// Paçoca mascot animations (RF-01, RF-02, RF-03, ADR-030).
class ServerAuthScreen extends StatefulWidget {
  const ServerAuthScreen({
    super.key,
    this.initialServerUrl,
    this.onAuthenticated,
    this.onExploreDemo,
  });

  final String? initialServerUrl;
  final VoidCallback? onAuthenticated;
  final VoidCallback? onExploreDemo;

  @override
  State<ServerAuthScreen> createState() => _ServerAuthScreenState();
}

class _ServerAuthScreenState extends State<ServerAuthScreen> {
  _AuthFlowStep _step = _AuthFlowStep.server;
  _ModeFocus _focusedMode = _ModeFocus.localDevice;
  bool _busy = false;
  String? _errorMessage;
  String? _infoMessage;
  int _errorSignal = 0;

  late final TextEditingController _serverUrlController;
  final _ownerNameController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _ownerConfirmPasswordController = TextEditingController();

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _loginSecondFactorController = TextEditingController();
  bool _useRecoveryCode = false;
  bool _showOwnerPassword = false;
  bool _showLoginPassword = false;

  // Focus nodes driving Paçoca's real-time eye tracking, eye covering, and shield poses.
  final _serverUrlFocus = FocusNode();
  final _ownerNameFocus = FocusNode();
  final _ownerEmailFocus = FocusNode();
  final _ownerPasswordFocus = FocusNode();
  final _ownerConfirmPasswordFocus = FocusNode();
  final _loginEmailFocus = FocusNode();
  final _loginPasswordFocus = FocusNode();
  final _loginSecondFactorFocus = FocusNode();
  final _totpConfirmFocus = FocusNode();

  String? _pendingTotpToken;
  TotpSetupData? _totpSetupData;
  final _totpConfirmCodeController = TextEditingController();
  List<String> _recoveryCodes = const [];
  bool _savedRecoveryCodes = false;
  bool _initialized = false;

  final Map<TextEditingController, String> _lastControllerText = {};
  final Map<TextEditingController, VoidCallback> _controllerListeners = {};

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(
      text: widget.initialServerUrl ?? '',
    );
    for (final node in _allFocusNodes) {
      node.addListener(_onFieldStateChanged);
    }
    for (final controller in _trackedTextControllers) {
      _lastControllerText[controller] = controller.text;
      void listener() => _onTextControllerChanged(controller);
      _controllerListeners[controller] = listener;
      controller.addListener(listener);
    }
  }

  List<FocusNode> get _allFocusNodes => [
    _serverUrlFocus,
    _ownerNameFocus,
    _ownerEmailFocus,
    _ownerPasswordFocus,
    _ownerConfirmPasswordFocus,
    _loginEmailFocus,
    _loginPasswordFocus,
    _loginSecondFactorFocus,
    _totpConfirmFocus,
  ];

  List<TextEditingController> get _trackedTextControllers => [
    _serverUrlController,
    _ownerNameController,
    _ownerEmailController,
    _ownerPasswordController,
    _ownerConfirmPasswordController,
    _loginEmailController,
    _loginPasswordController,
    _loginSecondFactorController,
    _totpConfirmCodeController,
  ];

  void _onFieldStateChanged() {
    if (!mounted) return;
    if (_serverUrlFocus.hasFocus) {
      _focusedMode = _ModeFocus.server;
    }
    setState(() {});
  }

  void _onTextControllerChanged(TextEditingController controller) {
    final current = controller.text;
    final textChanged = _lastControllerText[controller] != current;
    _lastControllerText[controller] = current;
    if (!mounted) return;
    if (textChanged && _errorMessage != null) {
      _errorMessage = null;
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final state = AppScope.of(context);
      if (_serverUrlController.text.isEmpty && state.serverUrl != null) {
        _serverUrlController.text = state.serverUrl!;
        _lastControllerText[_serverUrlController] = _serverUrlController.text;
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    for (final node in _allFocusNodes) {
      node.removeListener(_onFieldStateChanged);
      node.dispose();
    }
    for (final entry in _controllerListeners.entries) {
      entry.key.removeListener(entry.value);
    }
    _controllerListeners.clear();
    _lastControllerText.clear();
    _serverUrlController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    _ownerPasswordController.dispose();
    _ownerConfirmPasswordController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _loginSecondFactorController.dispose();
    _totpConfirmCodeController.dispose();
    super.dispose();
  }

  void _setError(String message) {
    setState(() {
      _errorMessage = message;
      _errorSignal++;
    });
  }

  int get _stepIndex {
    switch (_step) {
      case _AuthFlowStep.server:
        return 0;
      case _AuthFlowStep.ownerSetup:
        return 1;
      case _AuthFlowStep.login:
        return 2;
      case _AuthFlowStep.totpSetup:
        return 3;
      case _AuthFlowStep.recoveryCodes:
        return 4;
    }
  }

  ({
    PacocaMood mood,
    double gazeX,
    double gazeY,
    double securityProgress,
  })
  get _mascotPose {
    if (_errorMessage != null) {
      return (
        mood: PacocaMood.calmError,
        gazeX: 0.0,
        gazeY: 0.1,
        securityProgress: 0.0,
      );
    }

    final isPasswordFocused =
        _ownerPasswordFocus.hasFocus ||
        _ownerConfirmPasswordFocus.hasFocus ||
        _loginPasswordFocus.hasFocus;
    final isPasswordRevealed =
        ((_ownerPasswordFocus.hasFocus ||
                _ownerConfirmPasswordFocus.hasFocus) &&
            _showOwnerPassword) ||
        (_loginPasswordFocus.hasFocus && _showLoginPassword);

    if (isPasswordFocused) {
      return (
        mood: isPasswordRevealed
            ? PacocaMood.peekingPassword
            : PacocaMood.coveringEyes,
        gazeX: 0.0,
        gazeY: 0.25,
        securityProgress: 0.0,
      );
    }

    if (_loginSecondFactorFocus.hasFocus) {
      final progress = (_loginSecondFactorController.text.trim().length / 6.0)
          .clamp(0.0, 1.0);
      return (
        mood: PacocaMood.securityShield,
        gazeX: 0.0,
        gazeY: 0.15,
        securityProgress: progress,
      );
    }

    switch (_step) {
      case _AuthFlowStep.server:
        if (_serverUrlFocus.hasFocus) {
          return (
            mood: PacocaMood.trackingInput,
            gazeX: _textGazeX(_serverUrlController.text),
            gazeY: 0.45,
            securityProgress: 0.0,
          );
        }
        final modeGaze = switch (_focusedMode) {
          _ModeFocus.localDevice => -0.55,
          _ModeFocus.server => 0.0,
          _ModeFocus.demo => 0.55,
        };
        return (
          mood: PacocaMood.welcome,
          gazeX: modeGaze,
          gazeY: 0.25,
          securityProgress: 0.0,
        );

      case _AuthFlowStep.ownerSetup:
        if (_ownerNameFocus.hasFocus) {
          return (
            mood: PacocaMood.trackingInput,
            gazeX: _textGazeX(_ownerNameController.text),
            gazeY: 0.4,
            securityProgress: 0.0,
          );
        }
        if (_ownerEmailFocus.hasFocus) {
          return (
            mood: PacocaMood.trackingInput,
            gazeX: _textGazeX(_ownerEmailController.text),
            gazeY: 0.5,
            securityProgress: 0.0,
          );
        }
        return (
          mood: PacocaMood.trackingInput,
          gazeX: _textGazeX(
            _ownerEmailController.text.isNotEmpty
                ? _ownerEmailController.text
                : _ownerNameController.text,
          ),
          gazeY: 0.35,
          securityProgress: 0.0,
        );

      case _AuthFlowStep.login:
        return (
          mood: PacocaMood.trackingInput,
          gazeX: _textGazeX(_loginEmailController.text),
          gazeY: 0.45,
          securityProgress: 0.0,
        );

      case _AuthFlowStep.totpSetup:
        final progress = (_totpConfirmCodeController.text.trim().length / 6.0)
            .clamp(0.0, 1.0);
        return (
          mood: PacocaMood.securityShield,
          gazeX: 0.0,
          gazeY: 0.15,
          securityProgress: progress,
        );

      case _AuthFlowStep.recoveryCodes:
        return (
          mood: PacocaMood.celebrating,
          gazeX: 0.0,
          gazeY: 0.0,
          securityProgress: 1.0,
        );
    }
  }

  static double _textGazeX(String text) {
    if (text.isEmpty) return -0.35;
    final ratio = (text.length / 26.0).clamp(0.0, 1.0);
    return -0.75 + ratio * 1.5;
  }

  void _finishIntoApp() {
    if (widget.onAuthenticated != null) {
      widget.onAuthenticated!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
      );
    }
  }

  Future<void> _startLocalDevice(AppState state) async {
    setState(() {
      _focusedMode = _ModeFocus.localDevice;
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await state.startLocalDeviceMode();
      if (!mounted) return;
      _finishIntoApp();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _exploreDemo(AppState state) {
    setState(() => _focusedMode = _ModeFocus.demo);
    state.enterDemoMode();
    if (widget.onExploreDemo != null) {
      widget.onExploreDemo!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
      );
    }
  }

  Future<void> _validateServer(AppState state) async {
    setState(() {
      _focusedMode = _ModeFocus.server;
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      final info = await state.validateAndConnectServer(
        _serverUrlController.text,
      );
      if (!mounted) return;
      setState(() {
        _step = info.ownerConfigured
            ? _AuthFlowStep.login
            : _AuthFlowStep.ownerSetup;
        _infoMessage = info.ownerConfigured
            ? 'Servidor validado (v${info.version}). Entre com sua conta.'
            : 'Servidor validado (v${info.version}). Crie a conta proprietária para começar.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      _setError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOwnerSetup(AppState state) async {
    final name = _ownerNameController.text.trim();
    final email = _ownerEmailController.text.trim();
    final password = _ownerPasswordController.text;
    final confirm = _ownerConfirmPasswordController.text;

    if (name.isEmpty) {
      _setError('Informe como você prefere ser chamado.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _setError('Informe um endereço de e-mail válido.');
      return;
    }
    if (!_passwordMeetsPolicy(password)) {
      _setError(
        'A senha precisa atender a todos os critérios de segurança abaixo.',
      );
      return;
    }
    if (password != confirm) {
      _setError('As duas senhas precisam ser iguais.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await state.setupOwner(
        email: email,
        displayName: name,
        password: password,
      );
      if (!mounted) return;
      _loginEmailController.text = email;
      _loginPasswordController.text = password;
      setState(() {
        _step = _AuthFlowStep.login;
        _infoMessage =
            'Conta criada com sucesso. Entre para ativar seu autenticador (2FA).';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      _setError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitLogin(AppState state) async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;
    final secondFactor = _loginSecondFactorController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _setError('Informe seu e-mail e sua senha.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      final result = await state.login(
        email: email,
        password: password,
        totpCode: _useRecoveryCode ? null : secondFactor,
        recoveryCode: _useRecoveryCode ? secondFactor : null,
      );
      if (!mounted) return;

      if (result.isTotpSetupRequired && result.pendingToken != null) {
        final setup = await state.beginTotpSetup(result.pendingToken!);
        if (!mounted) return;
        setState(() {
          _pendingTotpToken = result.pendingToken;
          _totpSetupData = setup;
          _step = _AuthFlowStep.totpSetup;
          _infoMessage =
              'Ative o segundo fator (2FA) no seu aplicativo autenticador para '
              'concluir o primeiro acesso.';
        });
        return;
      }

      try {
        await state.syncFromServer();
      } catch (_) {
        // Offline or initial empty sync should not block entering the app.
      }
      if (!mounted) return;
      _finishIntoApp();
    } on ApiException catch (error) {
      if (!mounted) return;
      _setError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmTotp(AppState state) async {
    final pending = _pendingTotpToken;
    final code = _totpConfirmCodeController.text.trim();
    if (pending == null || code.length < 6) {
      _setError('Digite o código de 6 dígitos do autenticador.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      final confirmed = await state.confirmTotp(pending, code);
      if (!mounted) return;
      setState(() {
        _recoveryCodes = confirmed.recoveryCodes;
        _savedRecoveryCodes = false;
        _step = _AuthFlowStep.recoveryCodes;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      _setError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyText(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copiado.')));
  }

  static bool _hasLower(String v) => RegExp(r'[a-z]').hasMatch(v);
  static bool _hasUpper(String v) => RegExp(r'[A-Z]').hasMatch(v);
  static bool _hasDigit(String v) => RegExp(r'\d').hasMatch(v);
  static bool _hasSpecial(String v) =>
      RegExp(r'[^a-zA-Z0-9]').hasMatch(v);

  static bool _passwordMeetsPolicy(String v) =>
      v.length >= 12 &&
      _hasLower(v) &&
      _hasUpper(v) &&
      _hasDigit(v) &&
      _hasSpecial(v);

  String get _title {
    switch (_step) {
      case _AuthFlowStep.server:
        return 'Como deseja usar o GranaPaCá';
      case _AuthFlowStep.ownerSetup:
        return 'Criar conta proprietária';
      case _AuthFlowStep.login:
        return 'Entrar na instância';
      case _AuthFlowStep.totpSetup:
        return 'Ativar autenticador (2FA)';
      case _AuthFlowStep.recoveryCodes:
        return 'Códigos de recuperação';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pose = _mascotPose;
    final compact = MediaQuery.sizeOf(context).height < 680;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compact ? 44 : null,
        title: Text(_title),
        actions: compact
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: GranaSpacing.md),
                  child: EditorialStepDots(total: 5, currentIndex: _stepIndex),
                ),
              ]
            : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            GranaSpacing.md,
            compact ? 2 : GranaSpacing.sm,
            GranaSpacing.md,
            GranaSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  Center(
                    child: Column(
                      children: [
                        const GranaPacaLogo(compact: true),
                        const SizedBox(height: GranaSpacing.sm),
                        EditorialStepDots(total: 5, currentIndex: _stepIndex),
                      ],
                    ),
                  ),
                  const SizedBox(height: GranaSpacing.xs),
                ],

                // Paçoca perched cleanly right on the top edge of the form card
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (compact) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8, right: 12),
                          child: GranaPacaLogo(compact: true),
                        ),
                      ],
                      AnimatedPacocaMascot(
                        key: const Key('auth_pacoca_mascot'),
                        mood: pose.mood,
                        gazeX: pose.gazeX,
                        gazeY: pose.gazeY,
                        securityProgress: pose.securityProgress,
                        errorSignal: _errorSignal,
                        size: compact ? 74 : 112,
                      ),
                    ],
                  ),
                ),

                Card(
                  child: Padding(
                    padding: EdgeInsets.all(
                      compact ? GranaSpacing.md : GranaSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.sessionClearedNotice != null) ...[
                          Card(
                            key: const Key('session_cleared_notice'),
                            color: scheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(GranaSpacing.md),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    color: scheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: GranaSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      state.sessionClearedNotice!,
                                      style: TextStyle(
                                        color: scheme.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: GranaSpacing.sm),
                        ],
                        if (_infoMessage != null) ...[
                          Card(
                            color: scheme.secondaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(GranaSpacing.md),
                              child: Text(
                                _infoMessage!,
                                style: TextStyle(
                                  color: scheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: GranaSpacing.sm),
                        ],
                        if (_errorMessage != null) ...[
                          Card(
                            key: const Key('auth_error_banner'),
                            color: scheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(GranaSpacing.md),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: scheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: GranaSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: scheme.onErrorContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: GranaSpacing.sm),
                        ],

                        switch (_step) {
                          _AuthFlowStep.server => _buildServerStep(
                            state,
                            scheme,
                            textTheme,
                          ),
                          _AuthFlowStep.ownerSetup => _buildOwnerSetupStep(
                            state,
                            scheme,
                            textTheme,
                          ),
                          _AuthFlowStep.login => _buildLoginStep(
                            state,
                            scheme,
                            textTheme,
                          ),
                          _AuthFlowStep.totpSetup => _buildTotpSetupStep(
                            state,
                            scheme,
                            textTheme,
                          ),
                          _AuthFlowStep.recoveryCodes =>
                            _buildRecoveryCodesStep(state, scheme, textTheme),
                        },
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerStep(
    AppState state,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final tokens = GranaTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Path 1: Zero-server encrypted local device mode (recommended for beginners)
        MouseRegion(
          onEnter: (_) => setState(() => _focusedMode = _ModeFocus.localDevice),
          child: Card(
            key: const Key('mode_local_device_card'),
            color: _focusedMode == _ModeFocus.localDevice
                ? scheme.secondaryContainer
                : scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GranaRadius.card),
              side: BorderSide(
                color: _focusedMode == _ModeFocus.localDevice
                    ? scheme.primary
                    : scheme.outlineVariant,
                width: _focusedMode == _ModeFocus.localDevice ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(GranaRadius.card),
              onTap: () =>
                  setState(() => _focusedMode = _ModeFocus.localDevice),
              child: Padding(
                padding: const EdgeInsets.all(GranaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: GranaSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          Icons.smartphone_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                        Text(
                          'Usar só neste aparelho',
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
                            color: tokens.mata.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(
                              GranaRadius.chip,
                            ),
                          ),
                          child: Text(
                            'Recomendado para começar',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tokens.mata,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sem servidor, sem Docker e sem mensalidade. Seus dados ficam '
                      'cifrados só no celular; importe extratos OFX/CSV ou lance '
                      'gastos na hora.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    FilledButton.icon(
                      key: const Key('start_local_device_button'),
                      onPressed: _busy ? null : () => _startLocalDevice(state),
                      icon: const Icon(Icons.lock_outline_rounded, size: 18),
                      label: const Text('Começar só neste aparelho'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.sm),

        // Path 2: Connect to self-hosted server (inline URL field + validate CTA)
        MouseRegion(
          onEnter: (_) => setState(() => _focusedMode = _ModeFocus.server),
          child: Card(
            key: const Key('mode_server_card'),
            color: _focusedMode == _ModeFocus.server
                ? scheme.secondaryContainer
                : scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GranaRadius.card),
              side: BorderSide(
                color: _focusedMode == _ModeFocus.server
                    ? scheme.primary
                    : scheme.outlineVariant,
                width: _focusedMode == _ModeFocus.server ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(GranaRadius.card),
              onTap: () => setState(() => _focusedMode = _ModeFocus.server),
              child: Padding(
                padding: const EdgeInsets.all(GranaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: GranaSpacing.sm),
                        Expanded(
                          child: Text(
                            'Conectar ao meu servidor',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Para quem já roda sua instância com sincronização '
                      'automática via Open Finance.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    TextField(
                      key: const Key('server_url_field'),
                      controller: _serverUrlController,
                      focusNode: _serverUrlFocus,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Endereço do servidor',
                        hintText: 'https://financas.minha-rede.ts.net',
                        prefixIcon: Icon(Icons.dns_outlined),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    FilledButton.icon(
                      key: const Key('server_validate_button'),
                      onPressed: _busy ? null : () => _validateServer(state),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline, size: 18),
                      label: Text(
                        _busy ? 'Validando servidor...' : 'Validar e continuar',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.sm),

        // Path 3: Explore deterministic demo
        MouseRegion(
          onEnter: (_) => setState(() => _focusedMode = _ModeFocus.demo),
          child: Card(
            key: const Key('mode_demo_card'),
            color: _focusedMode == _ModeFocus.demo
                ? scheme.secondaryContainer
                : scheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GranaRadius.card),
              side: BorderSide(
                color: _focusedMode == _ModeFocus.demo
                    ? scheme.primary
                    : scheme.outlineVariant,
                width: _focusedMode == _ModeFocus.demo ? 1.5 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(GranaRadius.card),
              onTap: () => setState(() => _focusedMode = _ModeFocus.demo),
              child: Padding(
                padding: const EdgeInsets.all(GranaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: GranaSpacing.sm),
                        Expanded(
                          child: Text(
                            'Explorar a demonstração',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Teste com dados fictícios antes de colocar os seus.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    OutlinedButton.icon(
                      key: const Key('server_explore_demo_button'),
                      onPressed: _busy ? null : () => _exploreDemo(state),
                      icon: const Icon(Icons.science_outlined, size: 18),
                      label: const Text('Explorar a demonstração'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerSetupStep(
    AppState state,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final pwd = _ownerPasswordController.text;
    final checks = [
      ('Pelo menos 12 caracteres', pwd.length >= 12),
      ('Letra minúscula (a-z)', _hasLower(pwd)),
      ('Letra maiúscula (A-Z)', _hasUpper(pwd)),
      ('Número (0-9)', _hasDigit(pwd)),
      ('Caractere especial (!@#\$%...)', _hasSpecial(pwd)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Primeiro acesso da instância',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.xs),
        Text(
          'Servidor: ${state.serverUrl ?? ''}',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: GranaSpacing.lg),
        TextField(
          key: const Key('setup_name_field'),
          controller: _ownerNameController,
          focusNode: _ownerNameFocus,
          decoration: const InputDecoration(
            labelText: 'Seu nome',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        TextField(
          key: const Key('setup_email_field'),
          controller: _ownerEmailController,
          focusNode: _ownerEmailFocus,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        TextField(
          key: const Key('setup_password_field'),
          controller: _ownerPasswordController,
          focusNode: _ownerPasswordFocus,
          obscureText: !_showOwnerPassword,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Senha forte',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              key: const Key('setup_password_visibility_toggle'),
              tooltip: _showOwnerPassword ? 'Ocultar senha' : 'Mostrar senha',
              onPressed: () =>
                  setState(() => _showOwnerPassword = !_showOwnerPassword),
              icon: Icon(
                _showOwnerPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Card(
          color: scheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Requisitos da senha:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final (label, ok) in checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          ok
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: ok
                              ? GranaTokens.of(context).mata
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              color: ok
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        TextField(
          key: const Key('setup_confirm_password_field'),
          controller: _ownerConfirmPasswordController,
          focusNode: _ownerConfirmPasswordFocus,
          obscureText: !_showOwnerPassword,
          decoration: const InputDecoration(
            labelText: 'Confirmar senha',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              'Seus dados ficam só com você',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: GranaSpacing.lg),
        FilledButton(
          key: const Key('setup_owner_submit_button'),
          onPressed: _busy ? null : () => _submitOwnerSetup(state),
          child: Text(_busy ? 'Criando conta...' : 'Criar conta proprietária'),
        ),
        const SizedBox(height: GranaSpacing.sm),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _errorMessage = null;
                  _step = _AuthFlowStep.server;
                }),
          child: const Text('Trocar servidor'),
        ),
      ],
    );
  }

  Widget _buildLoginStep(
    AppState state,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Entrar na sua instância',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Servidor: ${state.serverUrl ?? ''}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              key: const Key('login_change_server_button'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _errorMessage = null;
                      _step = _AuthFlowStep.server;
                    }),
              child: const Text('Trocar servidor'),
            ),
          ],
        ),
        const SizedBox(height: GranaSpacing.md),
        TextField(
          key: const Key('login_email_field'),
          controller: _loginEmailController,
          focusNode: _loginEmailFocus,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            prefixIcon: Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        TextField(
          key: const Key('login_password_field'),
          controller: _loginPasswordController,
          focusNode: _loginPasswordFocus,
          obscureText: !_showLoginPassword,
          decoration: InputDecoration(
            labelText: 'Senha',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              key: const Key('login_password_visibility_toggle'),
              tooltip: _showLoginPassword ? 'Ocultar senha' : 'Mostrar senha',
              onPressed: () =>
                  setState(() => _showLoginPassword = !_showLoginPassword),
              icon: Icon(
                _showLoginPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        TextField(
          key: Key(
            _useRecoveryCode ? 'login_recovery_field' : 'login_totp_field',
          ),
          controller: _loginSecondFactorController,
          focusNode: _loginSecondFactorFocus,
          keyboardType: _useRecoveryCode
              ? TextInputType.text
              : TextInputType.number,
          decoration: InputDecoration(
            labelText: _useRecoveryCode
                ? 'Código de recuperação'
                : 'Código do autenticador (2FA)',
            hintText: _useRecoveryCode
                ? 'Ex.: ABCD-EFGH'
                : '6 dígitos (dispensado no primeiro acesso)',
            prefixIcon: Icon(
              _useRecoveryCode
                  ? Icons.vpn_key_outlined
                  : Icons.verified_user_outlined,
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('login_use_recovery_toggle'),
            onPressed: () => setState(() {
              _useRecoveryCode = !_useRecoveryCode;
              _loginSecondFactorController.clear();
            }),
            child: Text(
              _useRecoveryCode
                  ? 'Voltar para código do autenticador'
                  : 'Usar código de recuperação',
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        FilledButton(
          key: const Key('login_submit_button'),
          onPressed: _busy ? null : () => _submitLogin(state),
          child: Text(_busy ? 'Entrando...' : 'Entrar'),
        ),
      ],
    );
  }

  Widget _buildTotpSetupStep(
    AppState state,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final setup = _totpSetupData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ative o autenticador (2FA obrigatório)',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Text(
          'Adicione esta chave no seu aplicativo autenticador (como Aegis, '
          'Ente Auth ou FreeOTP) e confirme digitando o código de 6 dígitos.',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: GranaSpacing.lg),
        if (setup != null) ...[
          Card(
            color: scheme.surfaceContainer,
            child: Padding(
              padding: const EdgeInsets.all(GranaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Escaneie o QR Code no seu autenticador',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: GranaSpacing.sm),
                  Center(
                    child: TotpQrCodeView(
                      key: const Key('totp_qr_code'),
                      data: setup.otpauthUri,
                      size: 168,
                    ),
                  ),
                  const SizedBox(height: GranaSpacing.md),
                  const Text(
                    'Chave manual (Base32)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    setup.manualKey,
                    key: const Key('totp_manual_key_text'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: GranaSpacing.sm),
                  Wrap(
                    spacing: GranaSpacing.sm,
                    runSpacing: GranaSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('totp_copy_key_button'),
                        onPressed: () =>
                            _copyText('Chave manual', setup.manualKey),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copiar chave'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('totp_copy_uri_button'),
                        onPressed: () =>
                            _copyText('Link otpauth://', setup.otpauthUri),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('Copiar link otpauth://'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: GranaSpacing.lg),
        ],
        TextField(
          key: const Key('totp_confirm_code_field'),
          controller: _totpConfirmCodeController,
          focusNode: _totpConfirmFocus,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Código de 6 dígitos do autenticador',
            prefixIcon: Icon(Icons.verified_user_outlined),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        FilledButton(
          key: const Key('totp_confirm_button'),
          onPressed: _busy ? null : () => _confirmTotp(state),
          child: Text(_busy ? 'Confirmando...' : 'Confirmar e ativar 2FA'),
        ),
      ],
    );
  }

  Widget _buildRecoveryCodesStep(
    AppState state,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Guarde seus códigos de recuperação',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Text(
          'Cada código abaixo funciona uma única vez caso você perca acesso ao '
          'seu autenticador. Anote ou salve em um gerenciador de senhas agora — '
          'eles não serão exibidos novamente.',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: GranaSpacing.lg),
        Card(
          color: scheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.lg),
            child: Wrap(
              spacing: GranaSpacing.md,
              runSpacing: GranaSpacing.sm,
              children: [
                for (final code in _recoveryCodes)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(GranaRadius.chip),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: SelectableText(
                      code,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.sm),
        OutlinedButton.icon(
          key: const Key('recovery_codes_copy_all'),
          onPressed: () => _copyText(
            'Códigos de recuperação',
            _recoveryCodes.join('\n'),
          ),
          icon: const Icon(Icons.copy_all_rounded),
          label: const Text('Copiar todos os códigos'),
        ),
        const SizedBox(height: GranaSpacing.md),
        CheckboxListTile(
          key: const Key('recovery_codes_saved_checkbox'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _savedRecoveryCodes,
          onChanged: (v) => setState(() => _savedRecoveryCodes = v ?? false),
          title: const Text('Já guardei meus códigos em um lugar seguro'),
        ),
        const SizedBox(height: GranaSpacing.md),
        FilledButton(
          key: const Key('recovery_codes_continue_button'),
          onPressed: _savedRecoveryCodes
              ? () async {
                  try {
                    await state.syncFromServer();
                  } catch (_) {
                    // Proceed even if initial sync returns empty/offline.
                  }
                  if (!mounted) return;
                  _finishIntoApp();
                }
              : null,
          child: const Text('Entrar no GranaPaCá'),
        ),
      ],
    );
  }
}
