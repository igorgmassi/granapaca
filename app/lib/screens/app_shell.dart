import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'alerts_screen.dart';
import 'assistant_screen.dart';
import 'cash_entry_sheet.dart';
import 'connections_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'local_account_sheet.dart';
import 'onboarding_screen.dart';
import 'receipts_export_screen.dart';
import 'review_queue_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';
import 'spending_screen.dart';

/// Responsive application shell with DemoBanner / OfflineBanner,
/// NavigationBar / NavigationRail (`Início`, `Extrato`, `Gastos`, `Paçoca`,
/// `Ajustes`), hide-values toggle, quick actions sheet, and alerts badge.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _titles = [
    'GranaPaCá',
    'Extrato',
    'Gastos',
    'Paçoca',
    'Configurações',
  ];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Início',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: 'Extrato',
    ),
    NavigationDestination(
      icon: Icon(Icons.pie_chart_outline_rounded),
      selectedIcon: Icon(Icons.pie_chart_rounded),
      label: 'Gastos',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: 'Paçoca',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Ajustes',
    ),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: Text('Início'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long_rounded),
      label: Text('Extrato'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.pie_chart_outline_rounded),
      selectedIcon: Icon(Icons.pie_chart_rounded),
      label: Text('Gastos'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome_rounded),
      label: Text('Paçoca'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('Ajustes'),
    ),
  ];

  Widget _tabBody(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const HistoryScreen();
      case 2:
        return const SpendingScreen();
      case 3:
        return const AssistantScreen();
      case 4:
        return const SettingsScreen();
      default:
        return const HomeScreen();
    }
  }

  Future<void> _showQuickActions(BuildContext context, AppState state) {
    final pendingGroups = state.reviewQueueGroups.length;
    final pendingOutbox = state.pendingOutboxCount;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Ações rápidas',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            key: const Key('quick_action_cash_entry'),
            leading: const Icon(Icons.payments_outlined),
            title: Text(
              state.isLocalDeviceMode
                  ? 'Lançar gasto ou receita'
                  : 'Lançar gasto em dinheiro',
            ),
            subtitle: Text(
              state.isLocalDeviceMode
                  ? 'Dinheiro, Pix, débito, crédito ou boleto em qualquer conta local'
                  : pendingOutbox > 0
                  ? '$pendingOutbox lançamento(s) na fila offline'
                  : 'Registro rápido em dinheiro físico (funciona offline)',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showCashEntrySheet(context);
            },
          ),
          if (state.isLocalDeviceMode)
            ListTile(
              key: const Key('quick_action_add_local_account'),
              leading: const Icon(Icons.add_card_outlined),
              title: const Text('Adicionar banco, conta ou cartão'),
              subtitle: const Text(
                'Cadastre bancos e cartões em 2 toques (salvo cifrado)',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showAddLocalAccountSheet(context);
              },
            ),
          ListTile(
            key: const Key('quick_action_nfce'),
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: const Text('Ler nota fiscal (NFC-e)'),
            subtitle: const Text(
              'Colar XML ou QR Code da SEFAZ para dividir itens',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReceiptsExportScreen(),
                ),
              );
            },
          ),
          ListTile(
            key: const Key('quick_action_review_queue'),
            leading: const Icon(Icons.pending_actions_outlined),
            title: const Text('A revisar'),
            subtitle: Text(
              pendingGroups == 0
                  ? 'Tudo classificado'
                  : '$pendingGroups estabelecimento(s) sem categoria',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ReviewQueueScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Configurar perfil e regras iniciais'),
            subtitle: const Text('Ocupação, casa e transporte'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScreen(profileOnly: true),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.rule_outlined),
            title: const Text('Gerenciar regras'),
            subtitle: const Text('Ativar, desativar ou excluir regras'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RulesScreen()),
              );
            },
          ),
          ListTile(
            key: const Key('quick_action_connections'),
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(
              state.isLocalDeviceMode
                  ? 'Contas locais e Open Finance'
                  : 'Conexões bancárias (Meu Pluggy)',
            ),
            subtitle: Text(
              state.isDemoMode
                  ? 'Ver status e passo a passo de conexão'
                  : state.isLocalDeviceMode
                  ? 'Gerenciar contas locais ou importar extratos'
                  : 'Gerenciar bancos, status e sincronização',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConnectionsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final selected = state.selectedTab.clamp(0, _titles.length - 1);
    final unread = state.unreadAlertCount;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final isWide = constraints.maxWidth >= 1000;

        final bodyContent = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: GranaSpacing.maxContentWidth,
            ),
            child: _tabBody(selected),
          ),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[selected]),
            actions: [
              IconButton(
                key: const Key('toggle_hide_values'),
                onPressed: state.toggleHideValues,
                tooltip: state.hideValues
                    ? 'Mostrar valores'
                    : 'Esconder valores',
                icon: Icon(
                  state.hideValues
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              IconButton(
                key: const Key('alerts_button'),
                tooltip: unread > 0
                    ? 'Alertas ($unread não lidos)'
                    : 'Alertas',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
                ),
                icon: Badge.count(
                  count: unread,
                  isLabelVisible: unread > 0,
                  child: const Icon(Icons.notifications_outlined),
                ),
              ),
              const SizedBox(width: GranaSpacing.xs),
            ],
          ),
          body: Column(
            children: [
              if (state.isDemoMode)
                DemoBanner(
                  onExploreGuide: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const OnboardingScreen(profileOnly: false),
                    ),
                  ),
                )
              else if (state.isServerMode && state.isOffline)
                OfflineBanner(
                  lastSyncedAt: state.lastSyncedAt,
                  onRetry: state.syncFromServer,
                ),
              if (state.sessionClearedNotice != null)
                Material(
                  key: const Key('shell_lockout_notice'),
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GranaSpacing.lg,
                      vertical: GranaSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: GranaSpacing.sm),
                        Expanded(
                          child: Text(
                            state.sessionClearedNotice!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar aviso',
                          onPressed: state.clearSessionClearedNotice,
                          icon: Icon(
                            Icons.close,
                            size: 18,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: isCompact
                    ? bodyContent
                    : Row(
                        children: [
                          NavigationRail(
                            extended: isWide,
                            labelType: isWide
                                ? NavigationRailLabelType.none
                                : NavigationRailLabelType.all,
                            selectedIndex: selected,
                            onDestinationSelected: state.selectTab,
                            leading: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: GranaSpacing.sm,
                              ),
                              child: FloatingActionButton.small(
                                heroTag: 'rail_quick_actions',
                                tooltip: 'Ações rápidas',
                                onPressed: () =>
                                    _showQuickActions(context, state),
                                child: const Icon(Icons.add_rounded),
                              ),
                            ),
                            destinations: _railDestinations,
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: bodyContent),
                        ],
                      ),
              ),
            ],
          ),
          floatingActionButton: isCompact
              ? FloatingActionButton(
                  heroTag: 'compact_quick_actions',
                  tooltip: 'Ações rápidas',
                  onPressed: () => _showQuickActions(context, state),
                  child: const Icon(Icons.add_rounded),
                )
              : null,
          bottomNavigationBar: isCompact
              ? NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: state.selectTab,
                  destinations: _destinations,
                )
              : null,
        );
      },
    );
  }
}
