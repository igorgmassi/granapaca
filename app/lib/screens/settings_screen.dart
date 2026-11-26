import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'bank_detail_screen.dart';
import 'onboarding_screen.dart';
import 'rules_screen.dart';

/// Settings screen covering privacy, theme, rules, profile guide, bank
/// connections, and demo controls (RF-05, RF-08, RF-27, RF-63).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final activeRuleCount = state.rules.where((r) => r.isActive).length;

    return ListView(
      padding: const EdgeInsets.all(GranaSpacing.lg),
      children: [
        Text(
          'Privacidade e aparência',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('settings_hide_values_switch'),
                secondary: Icon(
                  state.hideValues
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                title: const Text('Esconder valores'),
                subtitle: const Text(
                  'Substitui valores por R\$ ••• em todas as telas e mantém '
                  'apenas percentuais nos gráficos.',
                ),
                value: state.hideValues,
                onChanged: state.setHideValues,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(GranaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tema',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Sistema'),
                            icon: Icon(Icons.brightness_auto_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Claro'),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Escuro'),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {state.themeMode},
                        onSelectionChanged: (set) =>
                            state.setThemeMode(set.first),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GranaSpacing.xl),

        Text(
          'Classificação e perfil',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('settings_manage_rules'),
                leading: const Icon(Icons.rule_outlined),
                title: const Text('Gerenciar regras'),
                subtitle: Text(
                  activeRuleCount == 0
                      ? 'Nenhuma regra ativa'
                      : '$activeRuleCount regra(s) ativa(s)',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('settings_redo_profile_guide'),
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Refazer guia inicial'),
                subtitle: const Text(
                  'Ajuste ocupação, casa e transporte para gerar regras '
                  'de essencialidade.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen(profileOnly: true),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: GranaSpacing.xl),

        Text(
          'Instância e bancos',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('settings_connections'),
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Conexões bancárias'),
                subtitle: Text(
                  '${state.originalDataset.banks.length} bancos fictícios conectados na demo',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showConnectionsSheet(context, state),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('settings_server_config'),
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Configurar servidor'),
                subtitle: const Text('Disponível apenas na instância própria'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    showServerOnlyDialog(context, 'Configurar servidor'),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('settings_backup'),
                leading: const Icon(Icons.cloud_download_outlined),
                title: const Text('Backup e exportação'),
                subtitle: const Text('Exportar CSV, XLSX, PDF ou backup JSON'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    showServerOnlyDialog(context, 'Backup e exportação'),
              ),
            ],
          ),
        ),
        const SizedBox(height: GranaSpacing.xl),

        Text(
          'Modo demonstração',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('settings_demo_first_access'),
                leading: const Icon(Icons.route_outlined),
                title: const Text('Ver primeiro acesso da demo'),
                subtitle: const Text(
                  'Percorra a trilha completa desde servidor e login até o perfil.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen(profileOnly: false),
                  ),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const Key('settings_simulate_empty_connections'),
                secondary: const Icon(Icons.link_off_outlined),
                title: const Text('Simular sem bancos conectados'),
                subtitle: const Text(
                  'Mostra o convite inicial da tela Início em vez dos bancos fictícios.',
                ),
                value: state.simulateNoConnections,
                onChanged: state.setSimulateNoConnections,
              ),
            ],
          ),
        ),
        const SizedBox(height: GranaSpacing.lg),
        Text(
          'GranaPaCá · Open source (AGPL-3.0) · Somente leitura · Dados 100% fictícios na demo',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _showConnectionsSheet(BuildContext context, AppState state) {
    final banks = state.originalDataset.banks;
    final tokens = GranaTokens.of(context);
    final scheme = Theme.of(context).colorScheme;

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          GranaSpacing.lg,
          0,
          GranaSpacing.lg,
          GranaSpacing.xl,
        ),
        children: [
          const Text(
            'Conexões bancárias',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: GranaSpacing.md),
          for (final bank in banks) ...[
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(
                    bank.colorValue,
                  ).withValues(alpha: 0.14),
                  child: Icon(
                    Icons.account_balance_outlined,
                    color: Color(bank.colorValue),
                  ),
                ),
                title: Text(
                  bank.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${bank.connectionStatus.label} · ${bank.lastSyncedLabel}'
                  '${bank.consentDaysRemaining != null ? ' · vence em ${bank.consentDaysRemaining} dias' : ''}',
                ),
                trailing: Icon(
                  bank.connectionStatus == ConnectionStatus.expiringSoon
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: bank.connectionStatus == ConnectionStatus.expiringSoon
                      ? tokens.milho
                      : tokens.mata,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BankDetailScreen(initialBankId: bank.id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: GranaSpacing.sm),
          ],
          const SizedBox(height: GranaSpacing.sm),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(sheetContext).pop();
              showServerOnlyDialog(context, 'Conectar banco real');
            },
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('Conectar outro banco'),
          ),
          const SizedBox(height: GranaSpacing.xs),
          Text(
            'No modo demonstração não é possível conectar bancos reais.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
