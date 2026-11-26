import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../finance/queries.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';
import 'bank_detail_screen.dart';
import 'local_account_sheet.dart';
import 'receipts_export_screen.dart';

/// Bank connections screen showing connection health (`Em dia`, `Atrasada`,
/// `Com erro`, `Vencida`), consent expiry warnings (`<= 30 days`), preserved
/// data notices, pull-to-refresh sync, and guided 3-step Meu Pluggy connection
/// flow (RF-12, RF-13, RF-14).
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key, this.clock});

  /// Injectable reference clock for deterministic expiry-warning tests.
  final DateTime Function()? clock;

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _itemIdController = TextEditingController();
  final _institutionController = TextEditingController();
  bool _syncing = false;
  bool _showEmptyChecklist = false;
  String? _feedbackMessage;

  @override
  void dispose() {
    _itemIdController.dispose();
    _institutionController.dispose();
    super.dispose();
  }

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  Future<void> _handleRefresh(AppState state) async {
    if (state.isDemoMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Modo demonstração: na sua instância, arrastar atualiza os bancos '
            'conectados (que costumam atualizar 1x por dia).',
          ),
        ),
      );
      return;
    }
    if (state.isLocalDeviceMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Modo local: suas contas ficam salvas cifradas só neste aparelho. '
            'Adicione novas contas ou importe extratos OFX/CSV.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _syncing = true;
      _feedbackMessage = null;
    });
    try {
      await state.syncFromServer(triggerBankSync: true);
      await state.refreshConnections();
      if (!mounted) return;
      setState(() {
        _feedbackMessage = state.isOffline
            ? 'Sem conexão com o servidor. Mantendo os últimos dados salvos.'
            : 'Conexões atualizadas com sucesso.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _feedbackMessage = error.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _handleAlreadyConnected(AppState state) async {
    if (state.isDemoMode || state.isLocalDeviceMode) {
      await showServerOnlyDialog(context, 'Conectar bancos pelo Meu Pluggy');
      return;
    }

    setState(() {
      _syncing = true;
      _feedbackMessage = null;
      _showEmptyChecklist = false;
    });
    try {
      final result = await state.connectPluggyAndSync(
        externalItemId: _itemIdController.text.trim().isEmpty
            ? null
            : _itemIdController.text.trim(),
        institutionName: _institutionController.text.trim().isEmpty
            ? null
            : _institutionController.text.trim(),
      );
      await state.syncFromServer();
      if (!mounted) return;
      if (result.foundNoConnections && state.connections.isEmpty) {
        setState(() {
          _showEmptyChecklist = true;
          _feedbackMessage = null;
        });
      } else {
        _itemIdController.clear();
        _institutionController.clear();
        setState(() {
          _showEmptyChecklist = false;
          _feedbackMessage = result.message;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _feedbackMessage = error.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final connections = state.connections;
    final now = _now;
    final expiring = connections
        .where((c) => c.needsRenewalWarning(now))
        .toList(growable: false);
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state.isLocalDeviceMode
              ? 'Contas locais e Open Finance'
              : 'Conexões bancárias',
        ),
        actions: [
          if (state.isLocalDeviceMode)
            IconButton(
              tooltip: 'Adicionar conta local',
              onPressed: () => showAddLocalAccountSheet(context),
              icon: const Icon(Icons.add_card_outlined),
            )
          else
            IconButton(
              key: const Key('connections_sync_button'),
              tooltip: 'Sincronizar agora',
              onPressed: _syncing ? null : () => _handleRefresh(state),
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          if (state.isDemoMode)
            const DemoBanner()
          else if (state.isServerMode && state.isOffline)
            OfflineBanner(
              lastSyncedAt: state.lastSyncedAt,
              onRetry: () => _handleRefresh(state),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _handleRefresh(state),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: GranaSpacing.maxContentWidth,
                  ),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(GranaSpacing.lg),
                    children: [
                      // Prominent renewal warning when any consent expires <= 30d or is expired (RF-14)
                      if (expiring.isNotEmpty) ...[
                        Card(
                          key: const Key('connections_expiry_warning_banner'),
                          color: tokens.milho.withValues(alpha: 0.24),
                          child: Padding(
                            padding: const EdgeInsets.all(GranaSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: tokens.sobreMilho,
                                    ),
                                    const SizedBox(width: GranaSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        'Atenção à validade das autorizações',
                                        style: textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: tokens.sobreMilho,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: GranaSpacing.sm),
                                for (final conn in expiring)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      _expiryWarningLine(conn, now),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.sobreMilho,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: GranaSpacing.xs),
                                Text(
                                  'Os dados já sincronizados continuam '
                                  'visíveis com a data da última atualização. '
                                  'Renove a permissão somente leitura pelo '
                                  'Meu Pluggy para manter o extrato em dia.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: tokens.sobreMilho,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: GranaSpacing.lg),
                      ],

                      if (_feedbackMessage != null) ...[
                        Card(
                          color: scheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(GranaSpacing.md),
                            child: Text(
                              _feedbackMessage!,
                              style: TextStyle(
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: GranaSpacing.lg),
                      ],

                      if (state.isLocalDeviceMode) ...[
                        Card(
                          key: const Key('connections_local_mode_card'),
                          color: scheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(GranaSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Contas salvas neste aparelho',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No modo local você não precisa de servidor '
                                  'nem Open Finance: cadastre seus bancos ou '
                                  'importe extratos OFX/CSV.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: GranaSpacing.md),
                                for (final bank in state.originalDataset.banks)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Color(bank.colorValue),
                                      child: Icon(
                                        Icons.account_balance_outlined,
                                        size: 16,
                                        color: scheme.onPrimary,
                                      ),
                                    ),
                                    title: Text(
                                      bank.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${state.originalDataset.accounts.where((a) => a.bankId == bank.id).length} conta(s) · ${bank.lastSyncedLabel}',
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => BankDetailScreen(
                                          initialBankId: bank.id,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: GranaSpacing.md),
                                Wrap(
                                  spacing: GranaSpacing.sm,
                                  runSpacing: GranaSpacing.sm,
                                  children: [
                                    FilledButton.icon(
                                      key: const Key(
                                        'connections_add_local_account_button',
                                      ),
                                      onPressed: () =>
                                          showAddLocalAccountSheet(context),
                                      icon: const Icon(
                                        Icons.add_card_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Adicionar banco ou cartão',
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const ReceiptsExportScreen(),
                                            ),
                                          ),
                                      icon: const Icon(
                                        Icons.file_upload_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Importar OFX / CSV'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: GranaSpacing.xl),
                      ],

                      Text(
                        'Bancos conectados',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A sincronização automática acontece diariamente; '
                        'arraste para baixo para atualizar manualmente.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: GranaSpacing.md),

                      if (connections.isEmpty)
                        Card(
                          color: scheme.surfaceContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(GranaSpacing.lg),
                            child: Text(
                              state.isLocalDeviceMode
                                  ? 'Você está no modo local. Se quiser '
                                        'sincronização automática via Open '
                                        'Finance no futuro, basta migrar para '
                                        'um servidor próprio em Ajustes.'
                                  : 'Nenhum banco conectado ainda. Siga os 3 '
                                        'passos abaixo para conectar suas '
                                        'contas pelo Meu Pluggy.',
                            ),
                          ),
                        )
                      else
                        for (final conn in connections) ...[
                          _ConnectionCard(
                            connection: conn,
                            now: now,
                            onTap: () {
                              final existsInDataset = state
                                  .originalDataset
                                  .banks
                                  .any((b) => b.id == conn.id);
                              if (!existsInDataset) return;
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      BankDetailScreen(initialBankId: conn.id),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: GranaSpacing.sm),
                        ],

                      const SizedBox(height: GranaSpacing.xl),

                      // Guided 3-step Meu Pluggy flow (RF-12)
                      Card(
                        key: const Key('meu_pluggy_guided_card'),
                        child: Padding(
                          padding: const EdgeInsets.all(GranaSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_outlined,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: GranaSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      'Conectar bancos pelo Meu Pluggy',
                                      style: textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: GranaSpacing.sm),
                              Text(
                                'Conexão 100% somente leitura via Open Finance. '
                                'O GranaPaCá nunca pede a senha do seu banco '
                                'nem tokens bancários.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: GranaSpacing.lg),
                              const _GuidedStepTile(
                                number: '1',
                                title: 'Conecte seus bancos em meu.pluggy.ai',
                                description:
                                    'Acesse meu.pluggy.ai no navegador e '
                                    'selecione os bancos que deseja acompanhar '
                                    'em modo somente leitura.',
                              ),
                              const SizedBox(height: GranaSpacing.md),
                              const _GuidedStepTile(
                                number: '2',
                                title:
                                    'Autorize a sua instância a ler o Meu Pluggy',
                                description:
                                    'Garanta que a sua instância tenha acesso '
                                    'de leitura ao Meu Pluggy. Se quiser, '
                                    'informe abaixo o ID do item para vincular '
                                    'na hora.',
                              ),
                              const SizedBox(height: GranaSpacing.md),
                              TextField(
                                key: const Key('pluggy_item_id_field'),
                                controller: _itemIdController,
                                decoration: const InputDecoration(
                                  labelText: 'ID do item Pluggy (opcional)',
                                  hintText: 'Ex.: item-aurora-001',
                                  prefixIcon: Icon(Icons.tag_rounded),
                                ),
                              ),
                              const SizedBox(height: GranaSpacing.sm),
                              TextField(
                                key: const Key('pluggy_institution_field'),
                                controller: _institutionController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Nome da instituição (opcional)',
                                  hintText: 'Ex.: Banco Aurora',
                                  prefixIcon: Icon(
                                    Icons.account_balance_outlined,
                                  ),
                                ),
                              ),
                              const SizedBox(height: GranaSpacing.md),
                              const _GuidedStepTile(
                                number: '3',
                                title: 'Volte aqui e toque em "Já conectei"',
                                description:
                                    'O servidor busca as contas, saldos e '
                                    'transações automaticamente.',
                              ),
                              const SizedBox(height: GranaSpacing.lg),
                              FilledButton.icon(
                                key: const Key(
                                  'connections_already_connected_button',
                                ),
                                onPressed: _syncing
                                    ? null
                                    : () => _handleAlreadyConnected(state),
                                icon: const Icon(Icons.check_rounded),
                                label: Text(
                                  _syncing
                                      ? 'Verificando conexões...'
                                      : 'Já conectei',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_showEmptyChecklist) ...[
                        const SizedBox(height: GranaSpacing.lg),
                        Card(
                          key: const Key('empty_sync_checklist'),
                          color: scheme.surfaceContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(GranaSpacing.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ainda não encontramos bancos novos',
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: GranaSpacing.sm),
                                const Text(
                                  '• Confira se você concluiu a autorização no '
                                  'site meu.pluggy.ai.\n'
                                  '• Verifique se a permissão de leitura da '
                                  'sua instância está ativa no Meu Pluggy.\n'
                                  '• Alguns bancos levam alguns minutos após a '
                                  'primeira conexão — tente tocar em '
                                  '"Já conectei" novamente.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _expiryWarningLine(BankConnectionInfo conn, DateTime now) {
    final days = conn.daysUntilExpiry(now);
    if (conn.status == BankConnectionStatus.expired ||
        (days != null && days <= 0)) {
      return '• ${conn.institutionName}: autorização vencida — renove no Meu Pluggy.';
    }
    if (days != null) {
      return '• ${conn.institutionName}: autorização vence em $days '
          '${days == 1 ? 'dia' : 'dias'}.';
    }
    return '• ${conn.institutionName}: autorização próxima do vencimento.';
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.now,
    required this.onTap,
  });

  final BankConnectionInfo connection;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    final (Color badgeBg, Color badgeFg, IconData badgeIcon) =
        switch (connection.status) {
          BankConnectionStatus.upToDate => (
            tokens.mata.withValues(alpha: 0.14),
            tokens.mata,
            Icons.check_circle_outline_rounded,
          ),
          BankConnectionStatus.delayed => (
            tokens.milho.withValues(alpha: 0.25),
            tokens.sobreMilho,
            Icons.schedule_rounded,
          ),
          BankConnectionStatus.error => (
            scheme.errorContainer,
            scheme.onErrorContainer,
            Icons.error_outline_rounded,
          ),
          BankConnectionStatus.expired => (
            scheme.errorContainer,
            scheme.onErrorContainer,
            Icons.event_busy_outlined,
          ),
        };

    final syncText = connection.lastSyncedAt == null
        ? 'Ainda não sincronizado'
        : 'Última sincronização: ${formatFullDateTime(connection.lastSyncedAt!)}';

    final days = connection.daysUntilExpiry(now);
    final String? consentText;
    if (connection.consentExpiresAt == null) {
      consentText = null;
    } else if (connection.status == BankConnectionStatus.expired ||
        (days != null && days <= 0)) {
      consentText =
          'Autorização vencida em ${formatFullDate(connection.consentExpiresAt!)} '
          '· dados anteriores preservados';
    } else if (days != null && days <= 30) {
      consentText =
          'Autorização vence em $days ${days == 1 ? 'dia' : 'dias'} '
          '(${formatFullDate(connection.consentExpiresAt!)})';
    } else {
      consentText =
          'Autorização válida até ${formatFullDate(connection.consentExpiresAt!)}';
    }

    return Card(
      key: Key('connection_card_${connection.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(GranaRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(GranaSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 54,
                decoration: BoxDecoration(
                  color: Color(connection.colorValue),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: GranaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: GranaSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          connection.institutionName,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(
                              GranaRadius.chip,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(badgeIcon, size: 14, color: badgeFg),
                              const SizedBox(width: 4),
                              Text(
                                connection.status.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: badgeFg,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      syncText,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (consentText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        consentText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: connection.needsRenewalWarning(now)
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: connection.needsRenewalWarning(now)
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (connection.status == BankConnectionStatus.error) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Os dados sincronizados anteriormente continuam '
                        'disponíveis. Tente sincronizar novamente ou reconectar '
                        'pelo Meu Pluggy.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidedStepTile extends StatelessWidget {
  const _GuidedStepTile({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: GranaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
