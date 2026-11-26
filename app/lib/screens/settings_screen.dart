import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import 'app_lock_screen.dart';
import 'connections_screen.dart';
import 'local_account_sheet.dart';
import 'onboarding_screen.dart';
import 'receipts_export_screen.dart';
import 'review_queue_screen.dart';
import 'rules_screen.dart';
import 'server_auth_screen.dart';

/// Settings screen covering privacy, app lock, theme, rules, review queue,
/// profile guide, bank connections, server authentication, active sessions,
/// and demo controls (RF-01..05, RF-08, RF-12..14, RF-27, RF-31, RF-63).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loadingSessions = false;

  Future<void> _refreshSessions(AppState state) async {
    if (_loadingSessions) return;
    setState(() => _loadingSessions = true);
    try {
      await state.loadActiveSessions();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _revokeSession(AppState state, ActiveSession session) async {
    try {
      await state.revokeActiveSession(session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sessão "${session.deviceName}" encerrada.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _logout(AppState state) async {
    await state.logout();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerAuthScreen(initialServerUrl: state.serverUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final activeRuleCount = state.rules.where((r) => r.isActive).length;
    final reviewGroupCount = state.reviewQueueGroups.length;
    final lock = state.appLock;

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
              ListTile(
                key: const Key('settings_app_lock'),
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Bloqueio do app (PIN e biometria)'),
                subtitle: Text(
                  lock.isEnabled
                      ? 'Ativo · trava após ${lock.inactivityTimeout.inMinutes} min'
                      : 'Desativado · proteja o acesso com PIN de 6 dígitos',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showAppLockSettingsSheet(context),
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
                key: const Key('settings_review_queue'),
                leading: const Icon(Icons.pending_actions_outlined),
                title: const Text('A revisar'),
                subtitle: Text(
                  reviewGroupCount == 0
                      ? 'Tudo classificado'
                      : '$reviewGroupCount estabelecimento(s) sem categoria',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReviewQueueScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
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
              if (state.isLocalDeviceMode) ...[
                ListTile(
                  key: const Key('settings_local_mode_status'),
                  leading: Icon(
                    Icons.smartphone_outlined,
                    color: GranaTokens.of(context).mata,
                  ),
                  title: const Text(
                    'Modo local · dados cifrados só neste aparelho',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Sem servidor, sem Docker e sem mensalidade. Tudo fica '
                    'salvo em cache cifrado só no seu aparelho.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('settings_add_local_account'),
                  leading: const Icon(Icons.add_card_outlined),
                  title: const Text('Adicionar banco, conta ou cartão'),
                  subtitle: Text(
                    '${state.originalDataset.accounts.length} conta(s) '
                    'cadastrada(s) neste aparelho',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showAddLocalAccountSheet(context),
                ),
                const Divider(height: 1),
              ] else ...[
                ListTile(
                  key: const Key('settings_use_local_device'),
                  leading: Icon(
                    Icons.smartphone_outlined,
                    color: scheme.primary,
                  ),
                  title: const Text('Usar só neste aparelho (sem servidor)'),
                  subtitle: const Text(
                    'Sem Docker nem mensalidade: seus dados ficam cifrados só '
                    'no celular.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _confirmStartLocalDevice(context, state),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                key: const Key('settings_connections'),
                leading: const Icon(Icons.account_balance_outlined),
                title: Text(
                  state.isLocalDeviceMode
                      ? 'Contas locais e Open Finance'
                      : 'Conexões bancárias',
                ),
                subtitle: Text(
                  state.isDemoMode
                      ? '${state.originalDataset.banks.length} bancos fictícios conectados na demo'
                      : state.isLocalDeviceMode
                      ? '${state.originalDataset.banks.length} banco(s)/carteira salvo(s) neste aparelho'
                      : '${state.connections.length} conexão(ões) configurada(s)',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ConnectionsScreen(),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('settings_server_config'),
                leading: const Icon(Icons.dns_outlined),
                title: Text(
                  state.isLocalDeviceMode
                      ? 'Migrar para servidor próprio'
                      : 'Configurar servidor',
                ),
                subtitle: Text(
                  state.isServerMode && state.serverUrl != null
                      ? state.serverUrl!
                      : state.isLocalDeviceMode
                      ? 'Opcional: conecte depois para sincronização automática via Open Finance'
                      : 'Disponível apenas na instância própria',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: state.isDemoMode
                    ? () => _showDemoServerDialog(context)
                    : state.isLocalDeviceMode
                    ? () => _showMigrateToServerDialog(context, state)
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ServerAuthScreen(
                            initialServerUrl: state.serverUrl,
                          ),
                        ),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('settings_backup'),
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Comprovantes, NFC-e e Exportação'),
                subtitle: const Text(
                  'Ler NFC-e, exportar/restaurar backup JSON e importar extratos OFX/CSV',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReceiptsExportScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (state.isServerMode && state.isAuthenticated) ...[
          const SizedBox(height: GranaSpacing.xl),
          Text(
            'Sessão e dispositivos',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: GranaSpacing.sm),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.currentOwner != null)
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(state.currentOwner!.displayName),
                    subtitle: Text(state.currentOwner!.email),
                  ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('settings_load_sessions'),
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('Dispositivos conectados'),
                  subtitle: Text(
                    state.activeSessions.isEmpty
                        ? 'Toque para consultar sessões ativas'
                        : '${state.activeSessions.length} sessão(ões) ativa(s)',
                  ),
                  trailing: _loadingSessions
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onTap: () => _refreshSessions(state),
                ),
                for (final session in state.activeSessions) ...[
                  const Divider(height: 1),
                  ListTile(
                    key: Key('session_tile_${session.id}'),
                    title: Text(
                      session.isCurrent
                          ? '${session.deviceName} (este dispositivo)'
                          : session.deviceName,
                    ),
                    subtitle: Text(
                      'Criada em ${formatFullDateTime(session.createdAt)}',
                    ),
                    trailing: session.isCurrent
                        ? null
                        : TextButton(
                            key: Key('revoke_session_${session.id}'),
                            onPressed: () => _revokeSession(state, session),
                            child: const Text('Encerrar'),
                          ),
                  ),
                ],
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(GranaSpacing.md),
                  child: OutlinedButton.icon(
                    key: const Key('settings_logout_button'),
                    onPressed: () => _logout(state),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sair'),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: GranaSpacing.xl),

        Text(
          'Modo demonstração',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: GranaSpacing.sm),
        Card(
          child: Column(
            children: [
              if (!state.isDemoMode) ...[
                ListTile(
                  key: const Key('settings_enter_demo_mode'),
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('Explorar a demonstração'),
                  subtitle: const Text(
                    'Teste com dados fictícios (seus dados locais cifrados '
                    'continuam guardados).',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    state.enterDemoMode();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Modo demonstração ativado.'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
              ],
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
          state.isDemoMode
              ? 'GranaPaCá · Open source (AGPL-3.0) · Somente leitura · Dados 100% fictícios na demo'
              : state.isLocalDeviceMode
              ? 'GranaPaCá · Open source (AGPL-3.0) · Modo local · Dados cifrados só neste aparelho'
              : 'GranaPaCá · Open source (AGPL-3.0) · Somente leitura · Instância própria',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _confirmStartLocalDevice(
    BuildContext context,
    AppState state,
  ) async {
    final restored = await state.restoreLocalDeviceFromCache();
    if (!context.mounted) return;
    if (restored) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Modo local restaurado · dados cifrados carregados deste aparelho.',
          ),
        ),
      );
      return;
    }
    await state.startLocalDeviceMode();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Modo local ativado · dados cifrados salvos só neste aparelho.',
        ),
      ),
    );
  }

  Future<void> _showMigrateToServerDialog(
    BuildContext context,
    AppState state,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.dns_outlined,
          color: Theme.of(dialogContext).colorScheme.primary,
        ),
        title: const Text('Migrar para servidor próprio'),
        content: const Text(
          'Se quiser sincronização automática via Open Finance e acesso em '
          'vários dispositivos, você pode conectar a sua própria instância do '
          'GranaPaCá. Dica: gere um Backup JSON antes para guardar uma cópia '
          'dos seus lançamentos locais.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReceiptsExportScreen(),
                ),
              );
            },
            child: const Text('Exportar Backup JSON'),
          ),
          FilledButton(
            key: const Key('dialog_migrate_open_server_auth'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ServerAuthScreen(initialServerUrl: state.serverUrl),
                ),
              );
            },
            child: const Text('Conectar ao meu servidor'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDemoServerDialog(BuildContext context) {
    final state = AppScope.of(context);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.dns_outlined,
          color: Theme.of(dialogContext).colorScheme.primary,
        ),
        title: const Text('Configurar servidor'),
        content: const Text(
          'Este recurso só funciona na sua instância self-hosted do GranaPaCá. '
          'No modo demonstração, o app roda apenas com dados fictícios e não se '
          'conecta a bancos reais nem a servidores externos.',
        ),
        actions: [
          if (state.apiClient.isTransportSupported)
            TextButton(
              key: const Key('dialog_open_server_auth'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ServerAuthScreen(),
                  ),
                );
              },
              child: const Text('Conectar instância'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}
