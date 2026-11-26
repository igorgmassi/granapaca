import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/planning_queries.dart';
import '../finance/queries.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

/// Receipts / NFC-e item parser & transaction splitter (RN-24), RFC 4180 CSV &
/// full JSON backup export, and OFX/CSV statement import screen.
class ReceiptsExportScreen extends StatefulWidget {
  const ReceiptsExportScreen({super.key, this.targetTransactionId});

  /// Optional preselected transaction ID when opened from
  /// [TransactionDetailSheet].
  final int? targetTransactionId;

  @override
  State<ReceiptsExportScreen> createState() => _ReceiptsExportScreenState();
}

class _ReceiptsExportScreenState extends State<ReceiptsExportScreen> {
  static const String _sampleNfceXml = '''
<NFe>
  <infNFe Id="NFe32260300000000000000650010000001231000000123">
    <ide><dhEmi>2026-03-27T10:15:00-03:00</dhEmi></ide>
    <emit><xNome>Supermercado Bom Preco Ficticio LTDA</xNome></emit>
    <det nItem="1"><prod><xProd>Arroz Integral 5kg</xProd><qCom>1.00</qCom><vProd>28.90</vProd></prod></det>
    <det nItem="2"><prod><xProd>Detergente Neutro 500ml</xProd><qCom>2.00</qCom><vProd>7.50</vProd></prod></det>
    <det nItem="3"><prod><xProd>Chocolate Amargo 100g</xProd><qCom>1.00</qCom><vProd>12.60</vProd></prod></det>
    <total><ICMSTot><vNF>49.00</vNF></ICMSTot></total>
  </infNFe>
</NFe>''';

  final TextEditingController _nfceController = TextEditingController();
  ReceiptParseResult? _parsedReceipt;
  String? _nfceError;
  int? _selectedTxId;
  bool _submittingServer = false;

  String? _exportFormatLabel;
  String? _exportPreview;

  @override
  void initState() {
    super.initState();
    _selectedTxId = widget.targetTransactionId;
  }

  @override
  void dispose() {
    _nfceController.dispose();
    super.dispose();
  }

  Future<void> _parseNfce(AppState state) async {
    if (!state.receiptConsentAccepted) {
      setState(() {
        _nfceError =
            'Confirme primeiro o consentimento acima para ler e armazenar '
            'itens detalhados de notas fiscais.';
      });
      return;
    }

    try {
      final result = parseNfceInput(_nfceController.text);
      setState(() {
        _parsedReceipt = result;
        _nfceError = null;
      });

      if (state.isServerMode && !state.isOffline && state.isAuthenticated) {
        setState(() => _submittingServer = true);
        try {
          final serverTxUuid = _selectedTxId != null
              ? state.transactionUuidFor(_selectedTxId!)
              : null;
          await state.apiClient.submitNfceReceipt(
            rawInput: _nfceController.text.trim(),
            transactionId: serverTxUuid,
          );
        } on ApiException catch (error) {
          if (mounted) {
            setState(() => _nfceError = error.message);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        } finally {
          if (mounted) setState(() => _submittingServer = false);
        }
      }
    } on FormatException catch (error) {
      setState(() {
        _parsedReceipt = null;
        _nfceError = error.message;
      });
    }
  }

  void _applyReceiptAsSplits(AppState state) {
    final receipt = _parsedReceipt;
    if (receipt == null) return;

    final spendingTxs = state.effectiveTransactions
        .where((t) => isSpendingKind(t.kind))
        .toList(growable: false);
    if (spendingTxs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma transação de gasto disponível para dividir.'),
        ),
      );
      return;
    }

    final targetId = _selectedTxId ?? spendingTxs.first.id;
    final targetTx = state.effectiveById(targetId);
    final splits = receiptItemsToSplits(receipt.items, targetTx.amountCents);
    final ok = state.replaceSplits(targetTx.id, splits);

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível aplicar a divisão. Verifique a conexão e os '
            'valores dos itens.',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${splits.length} item(ns) aplicados como divisão em '
          '"${targetTx.description}" (soma exata em centavos).',
        ),
      ),
    );
  }

  Future<void> _generateCsv(AppState state) async {
    String csv;
    if (state.isServerMode && !state.isOffline && state.isAuthenticated) {
      try {
        csv = await state.apiClient.exportTransactionsCsv();
      } on ApiException {
        csv = buildTransactionsCsv(
          state.effectiveTransactions,
          state.effectiveDataset,
        );
      }
    } else {
      csv = buildTransactionsCsv(
        state.effectiveTransactions,
        state.effectiveDataset,
      );
    }
    if (!mounted) return;
    setState(() {
      _exportFormatLabel = 'CSV (RFC 4180)';
      _exportPreview = csv;
    });
  }

  Future<void> _generateJson(AppState state) async {
    String jsonText;
    if (state.isServerMode && !state.isOffline && state.isAuthenticated) {
      try {
        jsonText = await state.apiClient.exportBackupJson();
      } on ApiException {
        jsonText = buildBackupJson(
          dataset: state.effectiveDataset,
          rules: state.rules,
          adjustments: state.adjustments,
          budgets: state.budgets,
          goals: state.goals,
          alertRules: state.spendingAlertRules,
          modeLabel: state.mode.name,
        );
      }
    } else {
      jsonText = buildBackupJson(
        dataset: state.effectiveDataset,
        rules: state.rules,
        adjustments: state.adjustments,
        budgets: state.budgets,
        goals: state.goals,
        alertRules: state.spendingAlertRules,
        modeLabel: state.mode.name,
      );
    }
    if (!mounted) return;
    setState(() {
      _exportFormatLabel = 'Backup JSON completo';
      _exportPreview = jsonText;
    });
  }

  Future<void> _openImportDialog(BuildContext context, AppState state) {
    final messenger = ScaffoldMessenger.of(context);
    return showDialog<void>(
      context: context,
      builder: (_) =>
          _StatementImportDialog(state: state, messenger: messenger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    final spendingTxs = state.effectiveTransactions
        .where((t) => isSpendingKind(t.kind))
        .toList(growable: false);
    final effectiveSelectedTxId =
        spendingTxs.any((t) => t.id == _selectedTxId)
        ? _selectedTxId
        : (spendingTxs.isNotEmpty ? spendingTxs.first.id : null);

    return Scaffold(
      appBar: AppBar(title: const Text('Comprovantes, NFC-e e Exportação')),
      body: Column(
        children: [
          if (state.isDemoMode)
            const DemoBanner()
          else if (state.isOffline)
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
                child: ListView(
                  padding: const EdgeInsets.all(GranaSpacing.lg),
                  children: [
                    // First-time dietary / item-level consent prompt (#17)
                    if (!state.receiptConsentAccepted)
                      Card(
                        key: const Key('receipt_consent_card'),
                        color: scheme.tertiaryContainer.withValues(alpha: 0.65),
                        child: Padding(
                          padding: const EdgeInsets.all(GranaSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.privacy_tip_outlined,
                                    color: scheme.onTertiaryContainer,
                                  ),
                                  const SizedBox(width: GranaSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      'Consentimento para leitura de itens da nota',
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: GranaSpacing.sm),
                              Text(
                                'Ao ler uma NFC-e, o app extrai os produtos da '
                                'compra (como alimentos, bebidas ou itens de '
                                'farmácia) para sugerir divisões por categoria. '
                                'Esses detalhes ficam somente no seu dispositivo '
                                'ou na sua própria instância self-hosted.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onTertiaryContainer,
                                ),
                              ),
                              const SizedBox(height: GranaSpacing.md),
                              FilledButton.icon(
                                key: const Key('receipt_consent_accept_button'),
                                onPressed: state.acceptReceiptConsent,
                                icon: const Icon(Icons.verified_user_outlined),
                                label: const Text(
                                  'Entendi e autorizo ler itens',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        color: tokens.mata.withValues(alpha: 0.12),
                        child: ListTile(
                          leading: Icon(
                            Icons.verified_user_outlined,
                            color: tokens.mata,
                          ),
                          title: const Text(
                            'Leitura de itens de NFC-e autorizada',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Dados permanecem apenas na sua instância.',
                          ),
                          trailing: TextButton(
                            onPressed: state.revokeReceiptConsent,
                            child: const Text('Revogar'),
                          ),
                        ),
                      ),
                    const SizedBox(height: GranaSpacing.xl),

                    // NFC-e XML / QR URL section
                    Text(
                      'Ler nota fiscal (NFC-e)',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(GranaSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Cole o XML completo da NFC-e ou a URL do QR Code '
                              'da SEFAZ (ex.: sefaz.es.gov.br) para extrair os '
                              'itens e dividir uma transação em centavos exatos.',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: GranaSpacing.md),
                            TextField(
                              key: const Key('nfce_input_field'),
                              controller: _nfceController,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'XML da NFC-e ou URL do QR Code',
                                hintText:
                                    'https://app.sefaz.es.gov.br/ConsultaNFCe/?p=...',
                              ),
                            ),
                            const SizedBox(height: GranaSpacing.md),
                            Wrap(
                              spacing: GranaSpacing.sm,
                              runSpacing: GranaSpacing.sm,
                              children: [
                                FilledButton.icon(
                                  key: const Key('nfce_parse_button'),
                                  onPressed: _submittingServer
                                      ? null
                                      : () => _parseNfce(state),
                                  icon: const Icon(
                                    Icons.document_scanner_outlined,
                                  ),
                                  label: const Text('Analisar nota'),
                                ),
                                OutlinedButton.icon(
                                  key: const Key('nfce_load_sample_button'),
                                  onPressed: () {
                                    _nfceController.text = _sampleNfceXml;
                                  },
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text(
                                    'Carregar exemplo fictício',
                                  ),
                                ),
                              ],
                            ),
                            if (_nfceError != null) ...[
                              const SizedBox(height: GranaSpacing.md),
                              Text(
                                _nfceError!,
                                key: const Key('nfce_error_text'),
                                style: TextStyle(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    if (_parsedReceipt != null) ...[
                      const SizedBox(height: GranaSpacing.lg),
                      Card(
                        key: const Key('nfce_preview_card'),
                        child: Padding(
                          padding: const EdgeInsets.all(GranaSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _parsedReceipt!.issuerName,
                                          style: textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (_parsedReceipt!.accessKey != null)
                                          Text(
                                            'Chave: ${_parsedReceipt!.accessKey}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (_parsedReceipt!.totalCents > 0)
                                    MoneyText(
                                      cents: _parsedReceipt!.totalCents,
                                      hideValues: state.hideValues,
                                      style: tokens.valorGrande,
                                    ),
                                ],
                              ),
                              const SizedBox(height: GranaSpacing.md),
                              if (_parsedReceipt!.items.isEmpty)
                                Text(
                                  'Chave da NFC-e identificada. Na instância '
                                  'self-hosted o servidor consulta os itens '
                                  'detalhados na SEFAZ.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                for (final item in _parsedReceipt!.items)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(item.description),
                                    subtitle: Text(
                                      '${spendingCategoryLabel(item.suggestedCategory)} · '
                                      '${item.suggestedEssentiality?.label ?? 'Automático'}',
                                    ),
                                    trailing: MoneyText(
                                      cents: item.amountCents,
                                      hideValues: state.hideValues,
                                    ),
                                  ),
                              if (spendingTxs.isNotEmpty) ...[
                                const Divider(height: 24),
                                Text(
                                  'Transação de destino para divisão (RN-24)',
                                  style: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: GranaSpacing.sm),
                                DropdownButtonFormField<int>(
                                  key: const Key('nfce_target_tx_dropdown'),
                                  initialValue: effectiveSelectedTxId,
                                  isExpanded: true,
                                  items: [
                                    for (final tx in spendingTxs.take(20))
                                      DropdownMenuItem(
                                        value: tx.id,
                                        child: Text(
                                          '${formatShortDate(tx.date)} · '
                                          '${tx.description} '
                                          '(${state.hideValues ? r'R$ •••' : formatBrl(tx.amountCents.abs())})',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (val) =>
                                      setState(() => _selectedTxId = val),
                                ),
                                const SizedBox(height: GranaSpacing.md),
                                FilledButton.icon(
                                  key: const Key('nfce_apply_splits_button'),
                                  onPressed: () => _applyReceiptAsSplits(state),
                                  icon: const Icon(Icons.call_split_rounded),
                                  label: const Text(
                                    'Aplicar como divisão na transação',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: GranaSpacing.xl),

                    // Export & Import section
                    Text(
                      'Exportação e importação',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: GranaSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(GranaSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Seus dados pertencem a você. Exporte o extrato '
                              'em CSV padrão RFC 4180 ou faça um backup completo '
                              'em JSON, ou importe arquivos OFX/CSV do seu banco.',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: GranaSpacing.md),
                            Wrap(
                              spacing: GranaSpacing.sm,
                              runSpacing: GranaSpacing.sm,
                              children: [
                                FilledButton.tonalIcon(
                                  key: const Key('export_csv_button'),
                                  onPressed: () => _generateCsv(state),
                                  icon: const Icon(Icons.table_chart_outlined),
                                  label: const Text('Gerar CSV (RFC 4180)'),
                                ),
                                FilledButton.tonalIcon(
                                  key: const Key('export_json_button'),
                                  onPressed: () => _generateJson(state),
                                  icon: const Icon(Icons.data_object_rounded),
                                  label: const Text('Gerar Backup JSON'),
                                ),
                                OutlinedButton.icon(
                                  key: const Key('import_statement_button'),
                                  onPressed: () =>
                                      _openImportDialog(context, state),
                                  icon: const Icon(Icons.file_upload_outlined),
                                  label: const Text('Importar OFX / CSV'),
                                ),
                              ],
                            ),
                            if (_exportPreview != null) ...[
                              const SizedBox(height: GranaSpacing.lg),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Prévia: $_exportFormatLabel',
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextButton.icon(
                                    key: const Key('export_copy_button'),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: _exportPreview!),
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '$_exportFormatLabel copiado para a '
                                            'área de transferência.',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded),
                                    label: const Text('Copiar'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: GranaSpacing.xs),
                              Container(
                                padding: const EdgeInsets.all(GranaSpacing.md),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainer,
                                  borderRadius: BorderRadius.circular(
                                    GranaRadius.field,
                                  ),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  maxHeight: 240,
                                ),
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    _exportPreview!,
                                    key: const Key('export_preview_text'),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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

class _StatementImportDialog extends StatefulWidget {
  const _StatementImportDialog({required this.state, required this.messenger});

  final AppState state;
  final ScaffoldMessengerState messenger;

  @override
  State<_StatementImportDialog> createState() => _StatementImportDialogState();
}

class _StatementImportDialogState extends State<_StatementImportDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Transaction> _preview = const [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final accounts = state.originalDataset.accounts;
    final defaultAccountId = accounts.isNotEmpty
        ? accounts.first.id
        : AppState.cashAccountId;

    return AlertDialog(
      title: const Text('Importar extrato (OFX ou CSV)'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                state.isDemoMode
                    ? 'Cole um trecho OFX (<STMTTRN>) ou CSV '
                          '(data,descrição,valor) para pré-visualizar e '
                          'importar localmente na demonstração.'
                    : 'Cole um trecho OFX ou CSV para importar na sua '
                          'instância self-hosted.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: GranaSpacing.md),
              TextField(
                key: const Key('import_statement_field'),
                controller: _controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Conteúdo OFX ou CSV',
                  hintText:
                      '2026-03-26,Mercado Bairro,-45.90\n'
                      '2026-03-27,Padaria Central,-18.50',
                ),
              ),
              const SizedBox(height: GranaSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('import_statement_preview_button'),
                  onPressed: () {
                    final parsed = parseStatementImport(
                      _controller.text,
                      accountId: defaultAccountId,
                    );
                    setState(() {
                      _preview = parsed;
                      _error = parsed.isEmpty
                          ? 'Nenhuma transação reconhecida. Confira o '
                                'formato OFX ou CSV (data,descrição,valor).'
                          : null;
                    });
                  },
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Pré-visualizar'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: GranaSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_preview.isNotEmpty) ...[
                const SizedBox(height: GranaSpacing.md),
                Text(
                  '${_preview.length} transação(ões) pronta(s) para importar:',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: GranaSpacing.xs),
                for (final tx in _preview.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tx.description),
                    subtitle: Text(formatFullDate(tx.date)),
                    trailing: MoneyText(
                      cents: tx.amountCents,
                      hideValues: state.hideValues,
                      useUnicodeMinus: true,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('import_statement_confirm_button'),
          onPressed: _preview.isEmpty
              ? null
              : () async {
                  final raw = _controller.text.trim();
                  final isOfx = raw.toUpperCase().contains('<STMTTRN>');
                  if (state.isServerMode &&
                      !state.isOffline &&
                      state.isAuthenticated) {
                    final targetAccount = accounts.isNotEmpty
                        ? accounts.first
                        : null;
                    final targetBank = targetAccount != null
                        ? state.originalDataset.banks
                              .where((b) => b.id == targetAccount.bankId)
                              .firstOrNull
                        : null;
                    try {
                      final res = await state.apiClient.importStatement(
                        format: isOfx ? 'ofx' : 'csv',
                        content: raw,
                        institutionName:
                            targetBank?.name ?? 'Instituição importada',
                        accountName: targetAccount?.name ?? 'Conta importada',
                        accountKind:
                            targetAccount?.kind ?? AccountKind.checking,
                      );
                      await state.syncFromServer(triggerBankSync: false);
                      final inserted =
                          (res['inserted'] as num?)?.toInt() ?? _preview.length;
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      widget.messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            '$inserted transação(ões) importada(s) no servidor '
                            'com sucesso.',
                          ),
                        ),
                      );
                    } on ApiException catch (error) {
                      if (!mounted) return;
                      setState(() => _error = error.message);
                      widget.messenger.showSnackBar(
                        SnackBar(content: Text(error.message)),
                      );
                    }
                    return;
                  }
                  final count = state.importStatementTransactions(_preview);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  widget.messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '$count transação(ões) importada(s) com sucesso.',
                      ),
                    ),
                  );
                },
          child: const Text('Importar transações'),
        ),
      ],
    );
  }
}
