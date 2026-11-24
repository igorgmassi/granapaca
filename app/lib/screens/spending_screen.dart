import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../finance/model.dart';
import '../finance/queries.dart';
import '../finance/taxonomy.dart';
import '../state/app_state.dart';
import '../theme/grana_theme.dart';
import '../theme/grana_widgets.dart';

/// Gastos screen with interactive Donut chart (RF-34), full horizontal bar
/// ranking (RF-35), and period/bank/account filters aligned with Extrato
/// (RF-36, RF-05).
class SpendingScreen extends StatelessWidget {
  const SpendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final data = state.effectiveDataset;
    final month = state.spendingMonth;
    final (from, to) = monthRange(month);
    final filter = spendingFilter(
      from,
      to,
      bankId: state.spendingBankId,
      accountId: state.spendingAccountId,
    );
    final h = history(data, filter);
    final ranking = categoryRanking(h.items);
    final donut = categoryDonut(ranking);
    final totalSpentCents = -h.totalCents;

    final availableAccounts = data.accounts
        .where(
          (a) =>
              state.spendingBankId == null || a.bankId == state.spendingBankId,
        )
        .toList(growable: false);

    void openCategoryInHistory(SpendingCategory? category) {
      state.openHistoryWithFilter(
        TxFilter(
          from: from,
          to: to,
          bankId: state.spendingBankId,
          accountId: state.spendingAccountId,
          category: category,
          spendingOnly: true,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 840;

        final filterBar = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, m) in state.availableMonths.indexed) ...[
                    if (i > 0) const SizedBox(width: GranaSpacing.sm),
                    ChoiceChip(
                      key: Key('spending_month_${m.year}_${m.month}'),
                      label: Text(formatShortMonth(m)),
                      selected: m.year == month.year && m.month == month.month,
                      onSelected: (_) => state.setSpendingFilters(month: m),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: GranaSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    key: const Key('spending_bank_all'),
                    label: const Text('Todos os bancos'),
                    selected: state.spendingBankId == null,
                    onSelected: (_) => state.setSpendingFilters(
                      clearBank: true,
                      clearAccount: true,
                    ),
                  ),
                  for (final b in data.banks) ...[
                    const SizedBox(width: GranaSpacing.sm),
                    ChoiceChip(
                      key: Key('spending_bank_${b.id}'),
                      label: Text(b.name),
                      selected: state.spendingBankId == b.id,
                      onSelected: (_) => state.setSpendingFilters(bankId: b.id),
                    ),
                  ],
                  const SizedBox(width: GranaSpacing.md),
                  FilterChip(
                    key: const Key('spending_account_picker'),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.spendingAccountId == null
                              ? 'Todas as contas'
                              : data.account(state.spendingAccountId!).name,
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down_rounded, size: 18),
                      ],
                    ),
                    selected: state.spendingAccountId != null,
                    showCheckmark: false,
                    onSelected: (_) => _pickAccount(
                      context,
                      state,
                      availableAccounts,
                      data,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (ranking.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(GranaSpacing.lg),
            children: [
              filterBar,
              const SizedBox(height: GranaSpacing.xl),
              EmptyStateView(
                icon: Icons.pie_chart_outline_rounded,
                title: 'Sem gastos neste período',
                subtitle:
                    'Não há despesas registradas para os filtros selecionados.',
                actionLabel: 'Voltar para março/2026',
                onAction: () => state.setSpendingFilters(
                  month: DateTime(data.today.year, data.today.month),
                  clearBank: true,
                  clearAccount: true,
                ),
              ),
            ],
          );
        }

        final donutCard = DonutChartWidget(
          donut: donut,
          totalCents: totalSpentCents,
          hideValues: state.hideValues,
          onSelectCategory: openCategoryInHistory,
        );

        final rankingCard = CategoryRankingWidget(
          ranking: ranking,
          hideValues: state.hideValues,
          onSelectCategory: openCategoryInHistory,
        );

        return ListView(
          padding: const EdgeInsets.all(GranaSpacing.lg),
          children: [
            filterBar,
            const SizedBox(height: GranaSpacing.lg),
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: donutCard),
                  const SizedBox(width: GranaSpacing.lg),
                  Expanded(child: rankingCard),
                ],
              )
            else ...[
              donutCard,
              const SizedBox(height: GranaSpacing.lg),
              rankingCard,
            ],
          ],
        );
      },
    );
  }

  Future<void> _pickAccount(
    BuildContext context,
    AppState state,
    List<Account> accounts,
    Dataset data,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: GranaSpacing.lg),
        children: [
          const ListTile(
            title: Text(
              'Filtrar gastos por conta',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            title: const Text('Todas as contas'),
            trailing: state.spendingAccountId == null
                ? const Icon(Icons.check)
                : null,
            onTap: () {
              state.setSpendingFilters(clearAccount: true);
              Navigator.of(sheetContext).pop();
            },
          ),
          for (final a in accounts)
            ListTile(
              title: Text('${a.name} (${data.bank(a.bankId).name})'),
              trailing: state.spendingAccountId == a.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                state.setSpendingFilters(accountId: a.id);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _DonutSegment {
  const _DonutSegment({
    required this.label,
    required this.color,
    required this.cents,
    required this.share,
    this.category,
  });

  final String label;
  final Color color;
  final int cents;
  final double share;
  final SpendingCategory? category;
}

/// Interactive Donut chart (RF-34) with hit-testing and accessible legend.
class DonutChartWidget extends StatelessWidget {
  const DonutChartWidget({
    super.key,
    required this.donut,
    required this.totalCents,
    required this.hideValues,
    required this.onSelectCategory,
  });

  final Donut donut;
  final int totalCents;
  final bool hideValues;
  final ValueChanged<SpendingCategory?> onSelectCategory;

  List<_DonutSegment> _segments(BuildContext context) {
    final tokens = GranaTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final s in donut.slices)
        _DonutSegment(
          label: s.category.label,
          color: tokens.colorForCategory(s.category),
          cents: s.cents,
          share: s.share,
          category: s.category,
        ),
      if (donut.restCents > 0)
        _DonutSegment(
          label: 'Demais categorias',
          color: scheme.outline,
          cents: donut.restCents,
          share: donut.restShare,
        ),
    ];
  }

  void _handleTap(
    TapUpDetails details,
    double size,
    List<_DonutSegment> segments,
  ) {
    final center = Offset(size / 2, size / 2);
    final dx = details.localPosition.dx - center.dx;
    final dy = details.localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final outerRadius = size / 2 - 6;
    final innerRadius = outerRadius - 32;
    if (distance < innerRadius - 8 || distance > outerRadius + 8) {
      return;
    }

    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    var start = 0.0;
    for (final seg in segments) {
      final sweep = seg.share * 2 * math.pi;
      if (angle >= start && angle <= start + sweep) {
        onSelectCategory(seg.category);
        return;
      }
      start += sweep;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final segments = _segments(context);
    const chartSize = 220.0;

    final semanticSummary = segments
        .map((s) => '${s.label}: ${formatPercent(s.share)}')
        .join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Distribuição por categoria',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Toque em uma fatia ou item da legenda para abrir no extrato',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: GranaSpacing.lg),
            Center(
              child: Semantics(
                label: 'Gráfico de rosca de gastos. $semanticSummary',
                child: GestureDetector(
                  key: const Key('spending_donut_canvas'),
                  onTapUp: (details) =>
                      _handleTap(details, chartSize, segments),
                  child: SizedBox(
                    width: chartSize,
                    height: chartSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size.square(chartSize),
                          painter: _DonutPainter(
                            segments: segments,
                            gapColor: scheme.surfaceContainerLow,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              MoneyText(
                                key: const Key('spending_donut_total'),
                                cents: totalCents,
                                hideValues: hideValues,
                                style: tokens.valorGrande.copyWith(
                                  fontSize: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: GranaSpacing.lg),
            for (final seg in segments)
              InkWell(
                key: Key(
                  seg.category != null
                      ? 'donut_legend_${seg.category!.name}'
                      : 'donut_legend_rest',
                ),
                onTap: () => onSelectCategory(seg.category),
                borderRadius: BorderRadius.circular(GranaRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GranaSpacing.sm,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: seg.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: GranaSpacing.md),
                      Expanded(
                        child: Text(
                          seg.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (!hideValues) ...[
                        MoneyText(
                          cents: seg.cents,
                          hideValues: false,
                          style: tokens.valorLinha.copyWith(fontSize: 14),
                        ),
                        const SizedBox(width: GranaSpacing.md),
                      ],
                      SizedBox(
                        width: 48,
                        child: Text(
                          formatPercent(seg.share),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: GranaTokens.tabularFeatures,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.segments, required this.gapColor});

  final List<_DonutSegment> segments;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 28.0;
    final radius = size.width / 2 - strokeWidth / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 2px visual gap converted to radians along the midline circumference.
    final gapRadians = segments.length > 1 ? 2.0 / radius : 0.0;
    var startAngle = -math.pi / 2;

    for (final seg in segments) {
      final rawSweep = seg.share * 2 * math.pi;
      final sweep = math.max(0.01, rawSweep - gapRadians);
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle + gapRadians / 2, sweep, false, paint);
      startAngle += rawSweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.gapColor != gapColor;
}

/// Horizontal bar ranking showing ALL categories in descending order (RF-35).
class CategoryRankingWidget extends StatelessWidget {
  const CategoryRankingWidget({
    super.key,
    required this.ranking,
    required this.hideValues,
    required this.onSelectCategory,
  });

  final List<CategoryShare> ranking;
  final bool hideValues;
  final ValueChanged<SpendingCategory> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = GranaTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final maxCents = ranking.first.cents;
    final animDuration = GranaMotion.duration(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(GranaSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ranking de categorias',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Todas as categorias com gastos no período, da maior para a menor',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: GranaSpacing.lg),
            for (final item in ranking) ...[
              InkWell(
                key: Key('ranking_row_${item.category.name}'),
                onTap: () => onSelectCategory(item.category),
                borderRadius: BorderRadius.circular(GranaRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GranaSpacing.sm,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            iconForCategory(item.category),
                            size: 18,
                            color: tokens.colorForCategory(item.category),
                          ),
                          const SizedBox(width: GranaSpacing.sm),
                          Expanded(
                            child: Text(
                              item.category.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!hideValues) ...[
                            MoneyText(
                              cents: item.cents,
                              hideValues: false,
                              style: tokens.valorLinha.copyWith(fontSize: 14),
                            ),
                            const SizedBox(width: GranaSpacing.md),
                          ],
                          SizedBox(
                            width: 48,
                            child: Text(
                              formatPercent(item.share),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant,
                                fontFeatures: GranaTokens.tabularFeatures,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(GranaRadius.pill),
                        child: Container(
                          height: 10,
                          color: scheme.surfaceContainerHighest,
                          alignment: Alignment.centerLeft,
                          child: TweenAnimationBuilder<double>(
                            duration: animDuration,
                            tween: Tween<double>(
                              begin: 0,
                              end: maxCents > 0 ? item.cents / maxCents : 0,
                            ),
                            builder: (context, value, _) =>
                                FractionallySizedBox(
                                  widthFactor: value.clamp(0.02, 1.0),
                                  child: Container(
                                    color: tokens.colorForCategory(
                                      item.category,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: GranaSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }
}
