import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'bank_detail_screen.dart';

/// Alerts list screen with unread indicator and contextual navigation (RF-56).
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: GranaSpacing.maxContentWidth,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  itemCount: state.alerts.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: GranaSpacing.sm),
                  itemBuilder: (context, index) {
                    final alert = state.alerts[index];
                    return Card(
                      color: alert.isRead
                          ? scheme.surfaceContainerLow
                          : scheme.primaryContainer.withValues(alpha: 0.3),
                      child: ListTile(
                        key: Key('alert_tile_${alert.id}'),
                        contentPadding: const EdgeInsets.all(GranaSpacing.lg),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: alert.isRead
                                ? scheme.surfaceContainerHighest
                                : scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            alert.isRead
                                ? Icons.notifications_none_rounded
                                : Icons.notifications_active_outlined,
                            color: alert.isRead
                                ? scheme.onSurfaceVariant
                                : scheme.onPrimaryContainer,
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                alert.title,
                                style: TextStyle(
                                  fontWeight: alert.isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                              ),
                            ),
                            if (!alert.isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(alert.body),
                              const SizedBox(height: 6),
                              Text(
                                '${alert.dateLabel} · '
                                '${alert.isRead ? 'Lido' : 'Não lido'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          state.markAlertRead(alert.id);
                          switch (alert.target) {
                            case AlertTarget.bankAurora:
                            case AlertTarget.connections:
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const BankDetailScreen(
                                    initialBankId: 'aurora',
                                  ),
                                ),
                              );
                            case AlertTarget.spending:
                              state.selectTab(2);
                              Navigator.of(context).pop();
                            case AlertTarget.settings:
                              state.selectTab(4);
                              Navigator.of(context).pop();
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
