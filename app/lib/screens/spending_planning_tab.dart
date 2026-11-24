import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/planning_queries.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

/// Planejamento tab inside Gastos: End-of-Month Projection (excluding
/// atypical expenses), Monthly Category Budgets, Financial Goals with
/// contribution dialog, Detected Subscriptions, and Natural-Language Custom
/// Spending Alerts.
class SpendingPlanningTab extends StatefulWidget {
  const SpendingPlanningTab({super.key});

  @override
  State<SpendingPlanningTab> createState() => _SpendingPlanningTabState();
}

class _SpendingPlanningTabState extends State<SpendingPlanningTab> {
  final TextEditingController _alertInputController = TextEditingController();
  String? _alertInputError;

  @override
  void dispose() {
    _alertInputController.dispose();
    super.dispose();
  }

  Future<void> _showAddBudgetDialog(BuildContext context, AppState state) =>
      showDialog<void>(
        context: context,
        builder: (_) => _AddBudgetDialog(state: state),
      );

  Future<void> _showAddGoalDialog(BuildContext context, AppState state) =>
      showDialog<void>(
        context: context,
        builder: (_) => _AddGoalDialog(state: state),
      );

  Future<void> _showContributeGoalDialog(
    BuildContext context,
    AppState state,
    Goal goal,
  ) => showDialog<void>(
    context: context,
    builder: (_) => _ContributeGoalDialog(state: state, goal: goal),
  );

  void _addCustomAlertRule(AppState state) {
    final created = state.addSpendingAlertRuleFromText(
      _alertInputController.text,
    );
    if (created == null) {
      setState(() {
        _alertInputError =
            'Informe um valor e alvo claros (ex.: "me avise quando delivery '
            'passar de R\$ 300").';
      });
      return;
    }
    setState(() {
      _alertInputError = null;
      _alertInputController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Alerta criado: ${created.label}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final data = state.effectiveDataset;
    final month = state.spendingMonth;
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    final (from, to) = monthRange(month);
    final monthSpendingTxs = data.transactions
        .where(
          (t) =>
              isSpending(t) &&
              !t.date.isBefore(from) &&
              t.date.isBefore(to),
        )
        .toList(growable: false);
    final ranking = categoryRanking(monthSpendingTxs);
    final spentByCat = {for (final c in ranking) c.category: c.cents};

    final projection = projectMonthEndSpending(
      data.transactions,
      month,
      data.today,
    );
    final subscriptions = detectSubscriptions(data.transactions);
    final subsTotalMonthly = subscriptions.fold(
      0,
      (sum, s) => sum + s.averageCents,
    );

    return ListView(
      padding: const EdgeInsets.all(GranaSpacing.lg),
      children: [
        // Month selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, m) in state.availableMonths.indexed) ...[
                if (i > 0) const SizedBox(width: GranaSpacing.sm),
                ChoiceChip(
                  key: Key('planning_month_${m.year}_${m.month}'),
                  label: Text(formatShortMonth(m)),
                  selected: m.year == month.year && m.month == month.month,
                  onSelected: (_) => state.setSpendingFilters(month: m),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: GranaSpacing.lg),

        // 1. End-of-Month Projection (excluding atypical expenses)
        Card(
          key: const Key('planning_projection_card'),
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.trending_up_rounded, color: scheme.primary),
                    const SizedBox(width: GranaSpacing.sm),
                    Expanded(
                      child: Text(
                        'Projeção de fim do mês',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'Dia ${projection.elapsedDays} de ${projection.totalDays}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.sm),
                Text(
                  'Calculada sobre o ritmo diário de gastos regulares, '
                  'sem distorção por despesas atípicas.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: GranaSpacing.md),
                Wrap(
                  spacing: GranaSpacing.xl,
                  runSpacing: GranaSpacing.md,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Projeção regular (${formatShortMonth(month)})',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MoneyText(
                          key: const Key('planning_projected_regular'),
                          cents: projection.projectedRegularCents,
                          hideValues: state.hideValues,
                          style: tokens.valorGrande,
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gasto regular acumulado',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MoneyText(
                          cents: projection.regularSpentCents,
                          hideValues: state.hideValues,
                          style: tokens.valorLinha,
                        ),
                      ],
                    ),
                  ],
                ),
                if (projection.atypicalCount > 0) ...[
                  const SizedBox(height: GranaSpacing.md),
                  Container(
                    key: const Key('planning_atypical_exclusion_note'),
                    padding: const EdgeInsets.all(GranaSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(GranaRadius.chip),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: GranaSpacing.sm),
                        Expanded(
                          child: Text(
                            '${projection.atypicalCount} despesa(s) atípica(s) '
                            'excluída(s) da projeção diária.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                        MoneyText(
                          cents: projection.atypicalSpentCents,
                          hideValues: state.hideValues,
                          style: tokens.valorLinha.copyWith(
                            fontSize: 13,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.lg),

        // 2. Monthly Category Budgets
        Card(
          key: const Key('planning_budgets_card'),
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Orçamentos mensais',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('add_budget_button'),
                      onPressed: () => _showAddBudgetDialog(context, state),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Novo'),
                    ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.sm),
                if (state.budgets.isEmpty)
                  Text(
                    'Nenhum orçamento definido. Crie limites mensais por '
                    'categoria para acompanhar seu ritmo.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                else
                  for (final budget in state.budgets) ...[
                    () {
                      final spent = spentByCat[budget.category] ?? 0;
                      final ratio = budget.limitCents <= 0
                          ? 0.0
                          : spent / budget.limitCents;
                      final exceeded = spent > budget.limitCents;
                      final nearAlert =
                          !exceeded && ratio >= budget.alertThreshold;
                      final barColor = exceeded
                          ? scheme.error
                          : (nearAlert
                                ? tokens.milho
                                : tokens.colorForCategory(budget.category));

                      return Padding(
                        padding: const EdgeInsets.only(bottom: GranaSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  iconForCategory(budget.category),
                                  size: 18,
                                  color: tokens.colorForCategory(
                                    budget.category,
                                  ),
                                ),
                                const SizedBox(width: GranaSpacing.sm),
                                Expanded(
                                  child: Text(
                                    budget.category.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (exceeded || nearAlert)
                                  Container(
                                    margin: const EdgeInsets.only(
                                      right: GranaSpacing.sm,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: exceeded
                                          ? scheme.errorContainer
                                          : tokens.milho.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(
                                        GranaRadius.chip,
                                      ),
                                    ),
                                    child: Text(
                                      exceeded ? 'Acima' : 'Atenção',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: exceeded
                                            ? scheme.onErrorContainer
                                            : tokens.sobreMilho,
                                      ),
                                    ),
                                  ),
                                Text(
                                  formatPercent(ratio, decimals: 0),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: GranaTokens.tabularFeatures,
                                  ),
                                ),
                                IconButton(
                                  key: Key('delete_budget_${budget.id}'),
                                  tooltip: 'Excluir orçamento',
                                  onPressed: () =>
                                      state.deleteBudget(budget.id),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                MoneyText(
                                  cents: spent,
                                  hideValues: state.hideValues,
                                  style: tokens.valorLinha.copyWith(
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  ' de ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                MoneyText(
                                  cents: budget.limitCents,
                                  hideValues: state.hideValues,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant,
                                    fontFeatures: GranaTokens.tabularFeatures,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final alertX =
                                    constraints.maxWidth *
                                    budget.alertThreshold.clamp(0.1, 0.98);
                                return Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        GranaRadius.pill,
                                      ),
                                      child: Container(
                                        height: 10,
                                        color: scheme.surfaceContainerHighest,
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: ratio.clamp(0.0, 1.0),
                                          child: Container(color: barColor),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: alertX,
                                      child: Container(
                                        width: 2,
                                        height: 14,
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }(),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.lg),

        // 3. Financial Goals
        Card(
          key: const Key('planning_goals_card'),
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Metas financeiras',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('add_goal_button'),
                      onPressed: () => _showAddGoalDialog(context, state),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nova'),
                    ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.sm),
                if (state.goals.isEmpty)
                  Text(
                    'Nenhuma meta criada ainda. Cadastre reservas ou objetivos '
                    'para acompanhar cada aporte.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                else
                  for (final goal in state.goals) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: GranaSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  goal.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (goal.isCompleted)
                                Container(
                                  margin: const EdgeInsets.only(
                                    right: GranaSpacing.sm,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tokens.mata.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(
                                      GranaRadius.chip,
                                    ),
                                  ),
                                  child: Text(
                                    'Concluída',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: tokens.mata,
                                    ),
                                  ),
                                ),
                              TextButton(
                                key: Key('goal_contribute_${goal.id}'),
                                onPressed: () => _showContributeGoalDialog(
                                  context,
                                  state,
                                  goal,
                                ),
                                child: const Text('Aportar'),
                              ),
                              IconButton(
                                tooltip: 'Excluir meta',
                                onPressed: () => state.deleteGoal(goal.id),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              MoneyText(
                                cents: goal.currentCents,
                                hideValues: state.hideValues,
                                style: tokens.valorLinha.copyWith(fontSize: 13),
                              ),
                              Text(
                                ' de ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              MoneyText(
                                cents: goal.targetCents,
                                hideValues: state.hideValues,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontFeatures: GranaTokens.tabularFeatures,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatPercent(goal.progress, decimals: 0),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.mata,
                                  fontFeatures: GranaTokens.tabularFeatures,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              GranaRadius.pill,
                            ),
                            child: LinearProgressIndicator(
                              value: goal.progress,
                              minHeight: 10,
                              color: tokens.mata,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.lg),

        // 4. Detected Recurring Subscriptions
        Card(
          key: const Key('planning_subscriptions_card'),
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Assinaturas e recorrências detectadas',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (subscriptions.isNotEmpty)
                      MoneyText(
                        cents: subsTotalMonthly,
                        hideValues: state.hideValues,
                        style: tokens.valorLinha,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Cobranças identificadas automaticamente em 2 ou mais meses.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: GranaSpacing.md),
                if (subscriptions.isEmpty)
                  Text(
                    'Nenhuma recorrência detectada ainda.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                else
                  for (final sub in subscriptions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        iconForOptionalCategory(sub.category),
                        color: tokens.colorForOptionalCategory(sub.category),
                      ),
                      title: Text(
                        sub.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Dia típico ${sub.typicalDayOfMonth} · '
                        '${sub.monthsCount} meses detectados',
                      ),
                      trailing: MoneyText(
                        cents: sub.averageCents,
                        hideValues: state.hideValues,
                        style: tokens.valorLinha.copyWith(fontSize: 14),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: GranaSpacing.lg),

        // 5. Custom Natural-Language Spending Alerts
        Card(
          key: const Key('planning_alert_rules_card'),
          child: Padding(
            padding: const EdgeInsets.all(GranaSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Alertas de gasto personalizados',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Escreva em português natural — quando o limite for '
                  'ultrapassado no mês, um alerta entra na sua caixa de entrada.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: GranaSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('spending_alert_input'),
                        controller: _alertInputController,
                        onSubmitted: (_) => _addCustomAlertRule(state),
                        decoration: InputDecoration(
                          labelText: 'Regra em linguagem natural',
                          hintText:
                              'Ex.: me avise quando delivery passar de R\$ 300',
                          errorText: _alertInputError,
                        ),
                      ),
                    ),
                    const SizedBox(width: GranaSpacing.sm),
                    FilledButton(
                      key: const Key('add_spending_alert_button'),
                      onPressed: () => _addCustomAlertRule(state),
                      child: const Text('Criar alerta'),
                    ),
                  ],
                ),
                const SizedBox(height: GranaSpacing.md),
                for (final rule in state.spendingAlertRules) ...[
                  () {
                    final eval = evaluateSpendingAlertRule(
                      rule,
                      data.transactions,
                      month,
                    );
                    return ListTile(
                      key: Key('spending_alert_tile_${rule.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              rule.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (eval.triggered)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(
                                  GranaRadius.chip,
                                ),
                              ),
                              child: Text(
                                'Disparado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '"${rule.rawExpression}" · '
                        '${state.hideValues ? r'R$ •••' : formatPercent(eval.ratio, decimals: 0)} do limite',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: rule.isActive,
                            onChanged: (v) =>
                                state.toggleSpendingAlertRule(rule.id, v),
                          ),
                          IconButton(
                            tooltip: 'Excluir alerta',
                            onPressed: () =>
                                state.deleteSpendingAlertRule(rule.id),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    );
                  }(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AddBudgetDialog extends StatefulWidget {
  const _AddBudgetDialog({required this.state});

  final AppState state;

  @override
  State<_AddBudgetDialog> createState() => _AddBudgetDialogState();
}

class _AddBudgetDialogState extends State<_AddBudgetDialog> {
  SpendingCategory _selectedCategory = SpendingCategory.leisure;
  final TextEditingController _limitController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo orçamento mensal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<SpendingCategory>(
            key: const Key('budget_category_dropdown'),
            initialValue: _selectedCategory,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              for (final c in SpendingCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedCategory = val);
              }
            },
          ),
          const SizedBox(height: GranaSpacing.md),
          TextField(
            key: const Key('budget_limit_field'),
            controller: _limitController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Limite mensal (R\$)',
              prefixText: 'R\$ ',
              hintText: 'Ex.: 500,00',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: GranaSpacing.sm),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('budget_save_button'),
          onPressed: () {
            final cents = parseBrlToCents(_limitController.text);
            if (cents == null || cents <= 0) {
              setState(() {
                _error = 'Informe um limite válido maior que zero.';
              });
              return;
            }
            widget.state.upsertBudget(
              category: _selectedCategory,
              limitCents: cents,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _AddGoalDialog extends StatefulWidget {
  const _AddGoalDialog({required this.state});

  final AppState state;

  @override
  State<_AddGoalDialog> createState() => _AddGoalDialogState();
}

class _AddGoalDialogState extends State<_AddGoalDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _currentController = TextEditingController(
    text: '0,00',
  );
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _currentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova meta financeira'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('goal_name_field'),
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nome da meta',
              hintText: 'Ex.: Trocar bicicleta',
            ),
          ),
          const SizedBox(height: GranaSpacing.md),
          TextField(
            key: const Key('goal_target_field'),
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor alvo (R\$)',
              prefixText: 'R\$ ',
              hintText: 'Ex.: 3.000,00',
            ),
          ),
          const SizedBox(height: GranaSpacing.md),
          TextField(
            key: const Key('goal_current_field'),
            controller: _currentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor já guardado (R\$)',
              prefixText: 'R\$ ',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: GranaSpacing.sm),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('goal_save_button'),
          onPressed: () {
            final name = _nameController.text.trim();
            final targetCents = parseBrlToCents(_targetController.text);
            final currentCents = parseBrlToCents(_currentController.text) ?? 0;
            if (name.isEmpty) {
              setState(() => _error = 'Informe o nome da meta.');
              return;
            }
            if (targetCents == null || targetCents <= 0) {
              setState(() => _error = 'Informe um valor alvo maior que zero.');
              return;
            }
            widget.state.addGoal(
              name: name,
              targetCents: targetCents,
              currentCents: currentCents < 0 ? 0 : currentCents,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Criar meta'),
        ),
      ],
    );
  }
}

class _ContributeGoalDialog extends StatefulWidget {
  const _ContributeGoalDialog({required this.state, required this.goal});

  final AppState state;
  final Goal goal;

  @override
  State<_ContributeGoalDialog> createState() => _ContributeGoalDialogState();
}

class _ContributeGoalDialogState extends State<_ContributeGoalDialog> {
  final TextEditingController _amountController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Aportar em "${widget.goal.name}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('goal_contribution_field'),
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor do aporte (R\$)',
              prefixText: 'R\$ ',
              hintText: 'Ex.: 500,00',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: GranaSpacing.sm),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('goal_contribution_save_button'),
          onPressed: () {
            final cents = parseBrlToCents(_amountController.text);
            if (cents == null || cents <= 0) {
              setState(() {
                _error = 'Informe um valor válido maior que zero.';
              });
              return;
            }
            widget.state.contributeToGoal(widget.goal.id, cents);
            Navigator.of(context).pop();
          },
          child: const Text('Registrar aporte'),
        ),
      ],
    );
  }
}
