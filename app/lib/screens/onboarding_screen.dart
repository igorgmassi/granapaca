import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../state/app_state.dart';
import '../state/demo_profiles.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

enum _OnboardingStep {
  welcome,
  server,
  login,
  authenticator,
  occupation,
  home,
  transport,
  reviewRules,
  connectBanks,
}

/// First-access trail ("Trilha até a toca") and reusable profile guide
/// (RF-08, RF-63).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.profileOnly = false});

  final bool profileOnly;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final List<_OnboardingStep> _steps;
  int _index = 0;

  late Set<ProfileOccupation> _occupations;
  late Set<HomeTrait> _homeTraits;
  late Set<TransportMode> _transportModes;
  final Set<String> _deselectedRuleIds = {};
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _steps = widget.profileOnly
        ? const [
            _OnboardingStep.occupation,
            _OnboardingStep.home,
            _OnboardingStep.transport,
            _OnboardingStep.reviewRules,
          ]
        : _OnboardingStep.values;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final existing = AppScope.of(context).profileAnswers;
      _occupations = {...existing.occupations};
      _homeTraits = {...existing.homeTraits};
      _transportModes = {...existing.transportModes};
      _initialized = true;
    }
  }

  _OnboardingStep get _currentStep => _steps[_index];

  ProfileAnswers get _answers => ProfileAnswers(
    occupations: _occupations,
    homeTraits: _homeTraits,
    transportModes: _transportModes,
  );

  List<UserRule> get _candidateRules => buildRulesFromProfile(_answers);

  void _next() {
    if (_index < _steps.length - 1) {
      setState(() => _index++);
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _skipReviewRules() {
    if (widget.profileOnly) {
      Navigator.of(context).pop();
    } else {
      _next();
    }
  }

  void _applyRulesAndContinue(AppState state) {
    final selected = _candidateRules
        .where((r) => !_deselectedRuleIds.contains(r.id))
        .toList(growable: false);
    state.applyProfileRules(_answers, selected);

    if (widget.profileOnly) {
      Navigator.of(context).pop();
    } else {
      _next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stepNumber = _index + 1;
    final totalSteps = _steps.length;
    final progress = stepNumber / totalSteps;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _back,
          tooltip: _index == 0 ? 'Fechar' : 'Voltar',
          icon: Icon(_index == 0 ? Icons.close : Icons.arrow_back),
        ),
        title: Text(
          widget.profileOnly ? 'Guia de perfil' : 'Trilha até a toca',
        ),
        actions: [
          if (_index > 0)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Fechar',
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: Column(
        children: [
          const DemoBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GranaSpacing.lg,
              GranaSpacing.md,
              GranaSpacing.lg,
              GranaSpacing.sm,
            ),
            child: Semantics(
              label: 'Etapa $stepNumber de $totalSteps',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Etapa $stepNumber de $totalSteps',
                    key: const Key('onboarding_step_label'),
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(GranaRadius.pill),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  children: [_buildStepContent(context, state)],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(GranaSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _buildFooter(context, state),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent(BuildContext context, AppState state) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    switch (_currentStep) {
      case _OnboardingStep.welcome:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(GranaRadius.card),
              ),
              child: Icon(
                Icons.savings_outlined,
                size: 34,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: GranaSpacing.xl),
            Text(
              'Boas-vindas ao GranaPaCá',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: GranaSpacing.md),
            Text(
              'Todas as suas contas num só lugar, na sua própria máquina, '
              'sempre em modo somente leitura.',
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),
            Card(
              color: scheme.surfaceContainer,
              child: const Padding(
                padding: EdgeInsets.all(GranaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Neste tour do modo demonstração:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Etapas de servidor e login vêm preenchidas e travadas.\n'
                      '• Você pode experimentar o guia de perfil e ver as regras '
                      'geradas com explicação.\n'
                      '• Todos os valores e contas são 100% fictícios.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

      case _OnboardingStep.server:
        return _LockedDemoStep(
          title: 'Endereço do servidor',
          subtitle:
              'Na sua instância própria, você aponta o app para o endereço '
              'privado (como Tailscale) onde o GranaPaCá está rodando.',
          fields: const [
            _LockedField(
              label: 'URL da instância',
              value: 'https://demo.granapaca.local',
              icon: Icons.dns_outlined,
            ),
          ],
        );

      case _OnboardingStep.login:
        return _LockedDemoStep(
          title: 'Entrar na instância',
          subtitle:
              'A senha fica apenas na sua instância self-hosted, protegida '
              'sem credenciais padrão.',
          fields: const [
            _LockedField(
              label: 'E-mail',
              value: 'bia@demo.local',
              icon: Icons.person_outline,
            ),
            _LockedField(
              label: 'Senha',
              value: '••••••••••••',
              icon: Icons.lock_outline,
            ),
          ],
        );

      case _OnboardingStep.authenticator:
        return _LockedDemoStep(
          title: 'Autenticador (2FA)',
          subtitle:
              'O segundo fator protege o acesso à sua instância contra '
              'entradas não autorizadas.',
          fields: const [
            _LockedField(
              label: 'Código temporário',
              value: '123 456',
              icon: Icons.verified_user_outlined,
            ),
          ],
        );

      case _OnboardingStep.occupation:
        return _MultiSelectStep<ProfileOccupation>(
          title: 'Qual é a sua ocupação?',
          subtitle:
              'Você pode marcar mais de uma opção ou pular. Isso ajuda a '
              'identificar o que é ferramenta de trabalho sem julgamentos.',
          items: ProfileOccupation.values,
          selected: _occupations,
          labelOf: (item) => item.label,
          descriptionOf: (item) => item.description,
          onToggle: (item) {
            setState(() {
              if (!_occupations.remove(item)) {
                _occupations.add(item);
              }
            });
          },
        );

      case _OnboardingStep.home:
        return _MultiSelectStep<HomeTrait>(
          title: 'Como é a sua casa?',
          subtitle:
              'Selecione todas as opções que combinam com a sua rotina '
              'doméstica.',
          items: HomeTrait.values,
          selected: _homeTraits,
          labelOf: (item) => item.label,
          descriptionOf: (item) => item.description,
          onToggle: (item) {
            setState(() {
              if (!_homeTraits.remove(item)) {
                _homeTraits.add(item);
              }
            });
          },
        );

      case _OnboardingStep.transport:
        return _MultiSelectStep<TransportMode>(
          title: 'Como você costuma se deslocar?',
          subtitle:
              'Escolha um ou mais meios de transporte para calibrar a '
              'essencialidade dos gastos de mobilidade.',
          items: TransportMode.values,
          selected: _transportModes,
          labelOf: (item) => item.label,
          descriptionOf: (item) => item.description,
          onToggle: (item) {
            setState(() {
              if (!_transportModes.remove(item)) {
                _transportModes.add(item);
              }
            });
          },
        );

      case _OnboardingStep.reviewRules:
        final rules = _candidateRules;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Revisão das regras',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: GranaSpacing.sm),
            Text(
              'Desmarque qualquer regra que não faça sentido para você. '
              'Ajustes manuais já feitos nas transações nunca são alterados.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),
            if (rules.isEmpty)
              Card(
                color: scheme.surfaceContainer,
                child: const Padding(
                  padding: EdgeInsets.all(GranaSpacing.lg),
                  child: Text(
                    'Nenhuma opção de perfil marcada. O app continuará usando '
                    'as classificações padrão e você pode criar regras a '
                    'qualquer momento.',
                  ),
                ),
              )
            else
              for (final rule in rules) ...[
                Card(
                  child: CheckboxListTile(
                    key: Key('review_rule_${rule.id}'),
                    value: !_deselectedRuleIds.contains(rule.id),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _deselectedRuleIds.remove(rule.id);
                        } else {
                          _deselectedRuleIds.add(rule.id);
                        }
                      });
                    },
                    title: Wrap(
                      spacing: GranaSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          rule.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (rule.essentiality != null)
                          EssentialityBadge(essentiality: rule.essentiality!),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rule.explanation),
                          const SizedBox(height: 4),
                          Text(
                            'Corresponde a ${state.ruleMatchCount(rule)} '
                            'transação(ões) na demo',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
              ],
          ],
        );

      case _OnboardingStep.connectBanks:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(GranaRadius.card),
              ),
              child: Icon(
                Icons.account_balance_outlined,
                size: 32,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: GranaSpacing.xl),
            Text(
              'Conectar bancos',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: GranaSpacing.md),
            Text(
              'Na sua instância self-hosted, você conecta suas contas pelo '
              'Meu Pluggy (Open Finance somente leitura).',
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),
            Card(
              color: scheme.surfaceContainer,
              child: const Padding(
                padding: EdgeInsets.all(GranaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contas fictícias já carregadas na demo:',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Banco Aurora (Conta corrente, Poupança e Cartão •••• 4821)\n'
                      '• Banco Siriema (Conta corrente)',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildFooter(BuildContext context, AppState state) {
    final step = _currentStep;
    final canSkip =
        step == _OnboardingStep.occupation ||
        step == _OnboardingStep.home ||
        step == _OnboardingStep.transport;

    if (step == _OnboardingStep.reviewRules) {
      return SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: GranaSpacing.sm,
          runSpacing: GranaSpacing.sm,
          children: [
            OutlinedButton(onPressed: _back, child: const Text('Voltar')),
            Wrap(
              spacing: GranaSpacing.sm,
              runSpacing: GranaSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  key: const Key('onboarding_skip_button'),
                  onPressed: _skipReviewRules,
                  child: const Text('Pular por agora'),
                ),
                FilledButton.icon(
                  key: const Key('onboarding_apply_rules'),
                  onPressed: () => _applyRulesAndContinue(state),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aplicar regras'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (step == _OnboardingStep.connectBanks) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton(
            onPressed: () =>
                showServerOnlyDialog(context, 'Conectar banco via Meu Pluggy'),
            child: const Text('Como conectar'),
          ),
          FilledButton(
            key: const Key('onboarding_finish_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entrar no app'),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (canSkip)
          TextButton(
            key: const Key('onboarding_skip_button'),
            onPressed: _next,
            child: const Text('Pular por agora'),
          )
        else if (_index > 0)
          OutlinedButton(onPressed: _back, child: const Text('Voltar'))
        else
          const SizedBox.shrink(),
        FilledButton(
          key: const Key('onboarding_continue_button'),
          onPressed: _next,
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _LockedField {
  const _LockedField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _LockedDemoStep extends StatelessWidget {
  const _LockedDemoStep({
    required this.title,
    required this.subtitle,
    required this.fields,
  });

  final String title;
  final String subtitle;
  final List<_LockedField> fields;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(GranaRadius.chip),
          ),
          child: Text(
            'Preenchido na demo · somente leitura',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onTertiaryContainer,
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.md),
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: GranaSpacing.xl),
        for (final field in fields) ...[
          TextFormField(
            key: ValueKey('${field.label}_${field.value}'),
            initialValue: field.value,
            readOnly: true,
            enabled: false,
            decoration: InputDecoration(
              labelText: field.label,
              prefixIcon: Icon(field.icon),
              suffixIcon: const Icon(Icons.lock_outline, size: 18),
            ),
          ),
          const SizedBox(height: GranaSpacing.md),
        ],
      ],
    );
  }
}

class _MultiSelectStep<T> extends StatelessWidget {
  const _MultiSelectStep({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.descriptionOf,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final List<T> items;
  final Set<T> selected;
  final String Function(T) labelOf;
  final String Function(T) descriptionOf;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: GranaSpacing.lg),
        for (final item in items) ...[
          () {
            final isSelected = selected.contains(item);
            return Card(
              color: isSelected
                  ? scheme.primaryContainer.withValues(alpha: 0.45)
                  : scheme.surfaceContainerLow,
              child: CheckboxListTile(
                value: isSelected,
                onChanged: (_) => onToggle(item),
                title: Text(
                  labelOf(item),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(descriptionOf(item)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            );
          }(),
          const SizedBox(height: GranaSpacing.sm),
        ],
      ],
    );
  }
}
