import 'package:material_ui/material_ui.dart';

import '../api/api_models.dart';
import '../finance/model.dart';
import '../finance/queries.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';

/// Paçoca (Assistente) 4th navigation tab: read-only financial chat citing
/// exact periods & numbers, low-confidence suggestion confirmation cards, and
/// BYOK AI provider configuration sheet.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  static const _quickPrompts = [
    (key: 'assistant_quick_leftover', text: 'Quanto sobrou este mês?'),
    (key: 'assistant_quick_top_category', text: 'Qual categoria pesou mais?'),
    (key: 'assistant_quick_503020', text: 'Como está meu 50/30/20?'),
    (key: 'assistant_quick_subscriptions', text: 'Quais assinaturas tenho?'),
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _maskIfHidden(String text, bool hideValues) {
    if (!hideValues) return text;
    return text.replaceAll(
      RegExp(r'[-−+]?R\$\s*\d{1,3}(?:\.\d{3})*(?:,\d{2})?'),
      r'R$ •••',
    );
  }

  Future<void> _send(AppState state, String rawQuestion) async {
    final question = rawQuestion.trim();
    if (question.isEmpty || state.isAssistantLoading) return;
    _inputController.clear();
    await state.askAssistant(question, month: state.selectedMonth);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: GranaMotion.duration(context),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showProviderConfigSheet(
    BuildContext context,
    AppState state,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _AiProviderConfigSheet(state: state, messenger: messenger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final pendingSuggestions = state.pendingAssistantSuggestions;

    return Column(
      children: [
        // Top info bar with active period + BYOK config action
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: GranaSpacing.lg,
            vertical: GranaSpacing.sm,
          ),
          color: scheme.surfaceContainer,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: GranaSpacing.sm,
            runSpacing: GranaSpacing.xs,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: GranaSpacing.sm),
                  Text(
                    'Pergunte à Paçoca · ${formatMonthYear(state.selectedMonth)}',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                key: const Key('assistant_provider_config_button'),
                onPressed: () => _showProviderConfigSheet(context, state),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(
                  state.isDemoMode
                      ? 'Provedor de IA'
                      : state.aiProviderConfig.provider.label,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Chat & suggestions list
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(GranaSpacing.lg),
            children: [
              // Quick question chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, prompt) in _quickPrompts.indexed) ...[
                      if (i > 0) const SizedBox(width: GranaSpacing.sm),
                      ActionChip(
                        key: Key(prompt.key),
                        avatar: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: Text(prompt.text),
                        onPressed: () => _send(state, prompt.text),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: GranaSpacing.lg),

              // Low-confidence AI categorization suggestions requiring confirmation
              if (pendingSuggestions.isNotEmpty) ...[
                Text(
                  'Sugestões aguardando sua confirmação',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
                for (final sugg in pendingSuggestions) ...[
                  Card(
                    key: Key('suggestion_card_${sugg.id}'),
                    color: scheme.secondaryContainer.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.all(GranaSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sugg.merchantDisplay,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.milho.withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(
                                    GranaRadius.chip,
                                  ),
                                ),
                                child: Text(
                                  'Confiança ${formatPercent(sugg.confidence, decimals: 0)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: tokens.sobreMilho,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${sugg.suggestedCategory.label} · '
                            '${sugg.suggestedEssentiality.label}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sugg.explanation,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: GranaSpacing.sm),
                          Wrap(
                            spacing: GranaSpacing.sm,
                            runSpacing: GranaSpacing.xs,
                            children: [
                              FilledButton.tonalIcon(
                                key: Key('confirm_suggestion_${sugg.id}'),
                                onPressed: () {
                                  final created = state
                                      .confirmAssistantSuggestion(sugg.id);
                                  if (created != null && mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Regra criada para '
                                          '"${sugg.merchantDisplay}".',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Confirmar e criar regra'),
                              ),
                              TextButton(
                                key: Key('dismiss_suggestion_${sugg.id}'),
                                onPressed: () =>
                                    state.dismissAssistantSuggestion(sugg.id),
                                child: const Text('Descartar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: GranaSpacing.sm),
                ],
                const SizedBox(height: GranaSpacing.md),
              ],

              // Chat messages
              for (final msg in state.assistantMessages) ...[
                Align(
                  alignment: msg.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Card(
                      key: Key('assistant_msg_${msg.id}'),
                      color: msg.isUser
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.all(GranaSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!msg.isUser) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Paçoca',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  if (msg.periodLabel != null) ...[
                                    const SizedBox(width: GranaSpacing.sm),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(
                                          GranaRadius.chip,
                                        ),
                                      ),
                                      child: Text(
                                        'Período: ${msg.periodLabel}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: GranaSpacing.xs),
                            ],
                            Text(
                              _maskIfHidden(msg.text, state.hideValues),
                              style: TextStyle(
                                color: msg.isUser
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurface,
                              ),
                            ),
                            if (msg.citedFigures.isNotEmpty) ...[
                              const SizedBox(height: GranaSpacing.sm),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final fig in msg.citedFigures)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(
                                          GranaRadius.chip,
                                        ),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      child: Text(
                                        _maskIfHidden(fig, state.hideValues),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface,
                                          fontFeatures:
                                              GranaTokens.tabularFeatures,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: GranaSpacing.sm),
              ],
            ],
          ),
        ),

        // Bottom composer
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('assistant_input_field'),
                    controller: _inputController,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (value) => _send(state, value),
                    decoration: const InputDecoration(
                      hintText: 'Pergunte sobre seus gastos, saldo ou metas...',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: GranaSpacing.sm),
                FilledButton(
                  key: const Key('assistant_send_button'),
                  onPressed: state.isAssistantLoading
                      ? null
                      : () => _send(state, _inputController.text),
                  child: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AiProviderConfigSheet extends StatefulWidget {
  const _AiProviderConfigSheet({required this.state, required this.messenger});

  final AppState state;
  final ScaffoldMessengerState messenger;

  @override
  State<_AiProviderConfigSheet> createState() => _AiProviderConfigSheetState();
}

class _AiProviderConfigSheetState extends State<_AiProviderConfigSheet> {
  late AiProviderKind _selectedProvider;
  late TextEditingController _modelController;
  late TextEditingController _endpointController;
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.state.aiProviderConfig.provider;
    _modelController = TextEditingController(
      text: widget.state.aiProviderConfig.model,
    );
    _endpointController = TextEditingController(
      text: widget.state.aiProviderConfig.endpointUrl,
    );
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tokens = GranaTokens.of(context);
    final state = widget.state;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        GranaSpacing.lg,
        0,
        GranaSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + GranaSpacing.xl,
      ),
      child: SingleChildScrollView(
        key: const Key('assistant_provider_sheet_scroll'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Provedor de IA (BYOK)',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: GranaSpacing.xs),
            Text(
              'A Paçoca é estritamente somente leitura: responde perguntas '
              'sobre seus dados sem nunca movimentar dinheiro ou alterar '
              'classificações sem confirmação.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: GranaSpacing.md),
            if (state.isDemoMode) ...[
              Card(
                key: const Key('assistant_byok_demo_notice'),
                color: tokens.milho.withValues(alpha: 0.25),
                child: Padding(
                  padding: const EdgeInsets.all(GranaSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.dns_outlined, color: tokens.sobreMilho),
                      const SizedBox(width: GranaSpacing.sm),
                      Expanded(
                        child: Text(
                          'Provedores de IA externos (OpenAI, Anthropic, '
                          'Google Gemini ou Ollama) só podem ser configurados '
                          'na sua instância self-hosted. No modo demonstração, '
                          'a Paçoca responde localmente com cálculos exatos '
                          'sobre os dados fictícios, sem enviar nada para fora.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tokens.sobreMilho,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: GranaSpacing.md),
              for (final kind in AiProviderKind.values)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    kind == AiProviderKind.none
                        ? Icons.check_circle_rounded
                        : Icons.lock_outline_rounded,
                    color: kind == AiProviderKind.none
                        ? tokens.mata
                        : scheme.onSurfaceVariant,
                  ),
                  title: Text(kind.label),
                  subtitle: Text(
                    kind == AiProviderKind.none
                        ? 'Ativo na demonstração'
                        : 'Disponível na instância própria',
                  ),
                ),
              const SizedBox(height: GranaSpacing.md),
              FilledButton(
                key: const Key('assistant_byok_close_button'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendi'),
              ),
            ] else ...[
              Wrap(
                spacing: GranaSpacing.sm,
                runSpacing: GranaSpacing.sm,
                children: [
                  for (final kind in AiProviderKind.values)
                    ChoiceChip(
                      key: Key('ai_provider_${kind.name}'),
                      label: Text(kind.label),
                      selected: _selectedProvider == kind,
                      onSelected: (_) => setState(() {
                        final changed = _selectedProvider != kind;
                        _selectedProvider = kind;
                        if (changed) {
                          _apiKeyController.clear();
                          if (kind != AiProviderKind.ollama) {
                            _endpointController.clear();
                          }
                          if (kind == AiProviderKind.none) {
                            _modelController.clear();
                          }
                        }
                      }),
                    ),
                ],
              ),
              if (_selectedProvider != AiProviderKind.none) ...[
                const SizedBox(height: GranaSpacing.md),
                TextField(
                  key: const Key('ai_provider_model_field'),
                  controller: _modelController,
                  decoration: InputDecoration(
                    labelText: 'Modelo',
                    hintText: _selectedProvider == AiProviderKind.ollama
                        ? 'Ex.: llama3.1:8b'
                        : 'Ex.: gpt-4o-mini',
                  ),
                ),
                if (_selectedProvider == AiProviderKind.ollama) ...[
                  const SizedBox(height: GranaSpacing.md),
                  TextField(
                    key: const Key('ai_provider_endpoint_field'),
                    controller: _endpointController,
                    decoration: const InputDecoration(
                      labelText: 'Endereço do servidor Ollama',
                      hintText: 'http://ollama:11434',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: GranaSpacing.md),
                  TextField(
                    key: const Key('ai_provider_key_field'),
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText:
                          _selectedProvider == state.aiProviderConfig.provider &&
                              state.aiProviderConfig.hasApiKey
                          ? 'Nova chave de API (opcional, já salva)'
                          : 'Chave de API (cifrada no servidor)',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: GranaSpacing.lg),
              FilledButton.icon(
                key: const Key('ai_provider_save_button'),
                onPressed: () async {
                  final sameProvider =
                      _selectedProvider == state.aiProviderConfig.provider;
                  final enteredKey = _apiKeyController.text.trim();
                  final shouldClearKey =
                      _selectedProvider == AiProviderKind.none ||
                      (!sameProvider && enteredKey.isEmpty);
                  try {
                    await state.updateAiProviderConfig(
                      AiProviderConfig(
                        provider: _selectedProvider,
                        model: _selectedProvider == AiProviderKind.none
                            ? ''
                            : _modelController.text.trim(),
                        endpointUrl: _selectedProvider == AiProviderKind.ollama
                            ? _endpointController.text.trim()
                            : '',
                        hasApiKey: sameProvider &&
                            state.aiProviderConfig.hasApiKey &&
                            !shouldClearKey,
                      ),
                      apiKey: enteredKey.isEmpty ? null : enteredKey,
                      clearApiKey: shouldClearKey,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    widget.messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Configuração da Paçoca atualizada.'),
                      ),
                    );
                  } on ApiException catch (error) {
                    widget.messenger.showSnackBar(
                      SnackBar(content: Text(error.message)),
                    );
                  }
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Salvar configuração'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
