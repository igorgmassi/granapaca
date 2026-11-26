import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'alerts_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';
import 'spending_screen.dart';

/// Responsive application shell with fixed DemoBanner, NavigationBar /
/// NavigationRail, hide-values toggle, quick actions sheet, and alerts badge.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _titles = ['GranaPaCá', 'Extrato', 'Gastos', 'Configurações'];

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
        return const SettingsScreen();
      default:
        return const HomeScreen();
    }
  }

  Future<void> _showQuickActions(BuildContext context) {
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
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Conectar banco via Meu Pluggy'),
            subtitle: const Text('Disponível na instância self-hosted'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showServerOnlyDialog(context, 'Conectar banco via Meu Pluggy');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final selected = state.selectedTab;
    final unread = state.unreadAlertCount;

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
              DemoBanner(
                onExploreGuide: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OnboardingScreen(profileOnly: false),
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
                                onPressed: () => _showQuickActions(context),
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
                  onPressed: () => _showQuickActions(context),
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
