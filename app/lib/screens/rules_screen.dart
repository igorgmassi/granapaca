import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'onboarding_screen.dart';

/// Rule management screen for user-created and profile rules (RF-27).
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final userRules = state.rules
        .where((r) => r.layer == RuleLayer.user)
        .toList(growable: false);
    final profileRules = state.rules
        .where((r) => r.layer == RuleLayer.profile)
        .toList(growable: false);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Regras de classificação')),
      body: Column(
        children: [
          if (state.isDemoMode)
            const DemoBanner()
          else if (state.isServerMode && state.isOffline)
            OfflineBanner(
              lastSyncedAt: state.lastSyncedAt,
              onRetry: state.syncFromServer,
            ),
          Expanded(
            child: state.rules.isEmpty
                ? EmptyStateView(
                    icon: Icons.rule_outlined,
                    title: 'Nenhuma regra personalizada ainda',
                    subtitle:
                        'Crie regras ao corrigir uma transação no extrato ou '
                        'execute o guia de perfil para gerar regras iniciais.',
                    actionLabel: 'Abrir guia de perfil',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const OnboardingScreen(profileOnly: true),
                      ),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: GranaSpacing.maxContentWidth,
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(GranaSpacing.lg),
                        children: [
                          if (userRules.isNotEmpty) ...[
                            Text(
                              'Minhas regras',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: GranaSpacing.sm),
                            for (final r in userRules) ...[
                              _RuleCard(rule: r, state: state),
                              const SizedBox(height: GranaSpacing.sm),
                            ],
                            const SizedBox(height: GranaSpacing.lg),
                          ],
                          if (profileRules.isNotEmpty) ...[
                            Text(
                              'Regras do perfil',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: GranaSpacing.sm),
                            for (final r in profileRules) ...[
                              _RuleCard(rule: r, state: state),
                              const SizedBox(height: GranaSpacing.sm),
                            ],
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
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.state});

  final UserRule rule;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matchCount = state.ruleMatchCount(rule);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rule.explanation,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: Key('rule_switch_${rule.id}'),
                  value: rule.isActive,
                  onChanged: (v) => state.toggleRuleActive(rule.id, v),
                ),
                IconButton(
                  key: Key('rule_delete_${rule.id}'),
                  tooltip: 'Excluir regra',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: () => state.deleteRule(rule.id),
                ),
              ],
            ),
            const SizedBox(height: GranaSpacing.sm),
            Wrap(
              spacing: GranaSpacing.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (rule.category != null)
                  Chip(
                    label: Text(rule.category!.label),
                    visualDensity: VisualDensity.compact,
                  ),
                if (rule.essentiality != null)
                  EssentialityBadge(essentiality: rule.essentiality!),
                if (rule.kind != null) TxKindBadge(kind: rule.kind!),
                Text(
                  'Aplica-se a $matchCount transação(ões)',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
