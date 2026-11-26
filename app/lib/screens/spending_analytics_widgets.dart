import 'package:material_ui/material_ui.dart';

import '../demo/demo_data.dart';
import '../finance/model.dart';
import '../finance/queries.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

/// Custom calendar spending heatmap widget (ADR-006, 02-design-tokens.md):
/// - 5 Caramelo sequential shades from [GranaTokens.heatmapScale]
/// - Empty days rendered with an explicit [ColorScheme.outlineVariant] border
/// - Accessible [Semantics] label per day
/// - Strict [hideValues] masking (never leaks R$ figures in text or semantics)
class CalendarHeatmapWidget extends StatefulWidget {
  const CalendarHeatmapWidget({
    super.key,
    required this.month,
    required this.cells,
    required this.hideValues,
    this.onOpenDayInHistory,
  });

  final DateTime month;
  final List<DailySpendingCell> cells;
  final bool hideValues;
  final ValueChanged<DateTime>? onOpenDayInHistory;

  @override
  State<CalendarHeatmapWidget> createState() => _CalendarHeatmapWidgetState();
}

class _CalendarHeatmapWidgetState extends State<CalendarHeatmapWidget> {
  int? _selectedDay;

  static const _weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  @override
  void didUpdateWidget(CalendarHeatmapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) {
      _selectedDay = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final firstDay = DateTime(widget.month.year, widget.month.month, 1);
    // DateTime.weekday: Mon=1..Sun=7 -> map to Sun=0..Sat=6.
    final leadingBlanks = firstDay.weekday % 7;
    final totalSlots = leadingBlanks + widget.cells.length;
    final rowCount = (totalSlots / 7).ceil();

    final selectedCell = _selectedDay == null
        ? null
        : widget.cells
              .where((c) => c.date.day == _selectedDay)
              .firstOrNull;

    Color dayTextColor(int intensity) {
      if (intensity == 0) return scheme.onSurfaceVariant;
      if (isDark) {
        return intensity >= 4 ? scheme.onPrimary : scheme.onSurface;
      }
      return intensity >= 4 ? scheme.onPrimary : scheme.onSurface;
    }

    return Card(
      key: const Key('spending_calendar_heatmap'),
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mapa de calor de gastos',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Intensidade diária em ${formatMonthYear(widget.month)} — '
              'toque em um dia para inspecionar',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: GranaSpacing.md),

            // Weekday headers
            Row(
              children: [
                for (final wd in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        wd,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: GranaSpacing.xs),

            // Calendar rows
            for (var row = 0; row < rowCount; row++) ...[
              if (row > 0) const SizedBox(height: 6),
              Row(
                children: [
                  for (var col = 0; col < 7; col++) ...[
                    if (col > 0) const SizedBox(width: 6),
                    Expanded(
                      child: () {
                        final slotIndex = row * 7 + col;
                        final dayIndex = slotIndex - leadingBlanks;
                        if (dayIndex < 0 || dayIndex >= widget.cells.length) {
                          return const SizedBox(height: 36);
                        }
                        final cell = widget.cells[dayIndex];
                        final fillColor = tokens.colorForHeatmapIntensity(
                          cell.intensity,
                        );
                        final isSelected = _selectedDay == cell.date.day;
                        final valueDesc = cell.spentCents <= 0
                            ? 'sem gastos'
                            : (widget.hideValues
                                  ? 'valor oculto'
                                  : formatBrl(cell.spentCents));
                        final semanticLabel =
                            'Dia ${cell.date.day} de '
                            '${formatMonthYear(widget.month)}: $valueDesc';

                        return Semantics(
                          button: true,
                          label: semanticLabel,
                          excludeSemantics: true,
                          child: InkWell(
                            key: Key('heatmap_day_${cell.date.day}'),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() {
                              _selectedDay = isSelected ? null : cell.date.day;
                            }),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: fillColor ?? Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? scheme.primary
                                      : (cell.intensity == 0
                                            ? scheme.outlineVariant
                                            : Colors.transparent),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Text(
                                '${cell.date.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: cell.intensity > 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: dayTextColor(cell.intensity),
                                  fontFeatures: GranaTokens.tabularFeatures,
                                ),
                              ),
                            ),
                          ),
                        );
                      }(),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: GranaSpacing.md),

            // 5-shade Caramelo + empty border legend
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Menos',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                for (var level = 0; level <= 5; level++) ...[
                  if (level > 0) const SizedBox(width: 4),
                  Container(
                    key: Key('heatmap_legend_level_$level'),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color:
                          tokens.colorForHeatmapIntensity(level) ??
                          Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: level == 0
                          ? Border.all(color: scheme.outlineVariant)
                          : null,
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Text(
                  'Mais',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            if (selectedCell != null) ...[
              const SizedBox(height: GranaSpacing.md),
              Container(
                key: const Key('heatmap_selected_day_detail'),
                padding: const EdgeInsets.all(GranaSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(GranaRadius.chip),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: GranaSpacing.sm,
                  runSpacing: GranaSpacing.xs,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatFullDate(selectedCell.date),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          selectedCell.transactionCount == 0
                              ? 'Sem gastos neste dia'
                              : '${selectedCell.transactionCount} lançamento(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MoneyText(
                          cents: selectedCell.spentCents,
                          hideValues: widget.hideValues,
                          style: tokens.valorLinha,
                        ),
                        if (selectedCell.transactionCount > 0 &&
                            widget.onOpenDayInHistory != null) ...[
                          const SizedBox(width: GranaSpacing.sm),
                          TextButton(
                            onPressed: () =>
                                widget.onOpenDayInHistory!(selectedCell.date),
                            child: const Text('Ver no extrato'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 50/30/20 Rule Card:
/// - Necessidades = Essencial (meta 50%)
/// - Desejos = Importante + Flexível (meta 30%)
/// - Poupança = sobrou no mês (meta 20%)
class FiftyThirtyTwentyCard extends StatelessWidget {
  const FiftyThirtyTwentyCard({
    super.key,
    required this.breakdown,
    required this.hideValues,
  });

  final FiftyThirtyTwenty breakdown;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('spending_503020_card'),
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Regra 50 / 30 / 20',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Necessidades (Essencial) · Desejos (Importante + Flexível) · '
              'Poupança (sobrou)',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: GranaSpacing.lg),
            _RuleBucketRow(
              label: 'Necessidades (Essencial)',
              targetPercent: 50,
              actualShare: breakdown.needsShare,
              cents: breakdown.needsCents,
              color: tokens.essencial,
              hideValues: hideValues,
            ),
            const SizedBox(height: GranaSpacing.md),
            _RuleBucketRow(
              label: 'Desejos (Importante + Flexível)',
              targetPercent: 30,
              actualShare: breakdown.wantsShare,
              cents: breakdown.wantsCents,
              color: tokens.flexivel,
              hideValues: hideValues,
            ),
            const SizedBox(height: GranaSpacing.md),
            _RuleBucketRow(
              label: 'Poupança (sobrou no mês)',
              targetPercent: 20,
              actualShare: breakdown.savingsShare,
              cents: breakdown.savingsCents,
              color: tokens.mata,
              hideValues: hideValues,
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleBucketRow extends StatelessWidget {
  const _RuleBucketRow({
    required this.label,
    required this.targetPercent,
    required this.actualShare,
    required this.cents,
    required this.color,
    required this.hideValues,
  });

  final String label;
  final int targetPercent;
  final double actualShare;
  final int cents;
  final Color color;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!hideValues) ...[
              MoneyText(
                cents: cents,
                hideValues: false,
                style: tokens.valorLinha.copyWith(fontSize: 13),
              ),
              const SizedBox(width: GranaSpacing.sm),
            ],
            Text(
              '${formatPercent(actualShare, decimals: 0)} / $targetPercent%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
                fontFeatures: GranaTokens.tabularFeatures,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final markerX = constraints.maxWidth * (targetPercent / 100);
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(GranaRadius.pill),
                  child: Container(
                    height: 10,
                    color: scheme.surfaceContainerHighest,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: actualShare.clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ),
                ),
                Positioned(
                  left: markerX.clamp(0.0, constraints.maxWidth - 2),
                  child: Container(
                    width: 2,
                    height: 14,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Month-over-Month Comparison Card contrasting current month vs previous
/// month totals and top category variations.
class MonthComparisonCard extends StatelessWidget {
  const MonthComparisonCard({
    super.key,
    required this.comparison,
    required this.hideValues,
  });

  final MonthComparison comparison;
  final bool hideValues;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    final isIncrease = comparison.deltaCents > 0;
    final deltaColor = isIncrease ? scheme.error : tokens.mata;
    final sign = comparison.deltaCents > 0
        ? '+'
        : (comparison.deltaCents < 0 ? '−' : '');

    final currentLabel =
        '${formatShortMonth(comparison.currentMonth)}: '
        '${hideValues ? r'R$ •••' : formatBrl(comparison.currentSpentCents)}';
    final previousLabel =
        '${formatShortMonth(comparison.previousMonth)}: '
        '${hideValues ? r'R$ •••' : formatBrl(comparison.previousSpentCents)}';

    final topDeltas = comparison.categoryDeltas
        .where((d) => d.deltaCents != 0)
        .take(3)
        .toList(growable: false);

    return Card(
      key: const Key('spending_mom_card'),
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Comparação com o mês anterior',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: deltaColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(GranaRadius.chip),
                  ),
                  child: Text(
                    '$sign${formatPercent(comparison.deltaPercent.abs())}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: deltaColor,
                      fontFeatures: GranaTokens.tabularFeatures,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GranaSpacing.sm),
            Wrap(
              spacing: GranaSpacing.lg,
              runSpacing: GranaSpacing.xs,
              children: [
                Text(
                  currentLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    fontFeatures: GranaTokens.tabularFeatures,
                  ),
                ),
                Text(
                  previousLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: GranaTokens.tabularFeatures,
                  ),
                ),
                if (!hideValues)
                  Text(
                    'Variação: $sign${formatBrl(comparison.deltaCents.abs())}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: deltaColor,
                      fontFeatures: GranaTokens.tabularFeatures,
                    ),
                  ),
              ],
            ),
            if (topDeltas.isNotEmpty) ...[
              const SizedBox(height: GranaSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: GranaSpacing.sm),
              Text(
                'Maiores variações por categoria',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: GranaSpacing.xs),
              for (final item in topDeltas)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        iconForOptionalCategory(item.category),
                        size: 16,
                        color: tokens.colorForOptionalCategory(item.category),
                      ),
                      const SizedBox(width: GranaSpacing.sm),
                      Expanded(
                        child: Text(
                          spendingCategoryLabel(item.category),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        hideValues
                            ? (item.deltaCents >= 0 ? 'Subiu' : 'Caiu')
                            : '${item.deltaCents >= 0 ? '+' : '−'}'
                                  '${formatBrl(item.deltaCents.abs())}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: item.deltaCents > 0
                              ? scheme.error
                              : tokens.mata,
                          fontFeatures: GranaTokens.tabularFeatures,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
