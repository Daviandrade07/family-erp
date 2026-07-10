import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

final _categorySpendProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(analyticsRepositoryProvider).monthSpendByCategory());

final _heatmapProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(analyticsRepositoryProvider).weekdayHeatmap());

final _flow90Provider = FutureProvider.autoDispose(
    (ref) => ref.watch(analyticsRepositoryProvider).dailyCashFlow(daysBack: 90));

final _flow30Provider = FutureProvider.autoDispose(
    (ref) => ref.watch(analyticsRepositoryProvider).dailyCashFlow(daysBack: 30));

/// Advanced analytics: cash flow, pie, net-worth evolution line, weekday
/// heatmap and category treemap.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(_categorySpendProvider);
    final heatmap = ref.watch(_heatmapProvider);
    final flow = ref.watch(_flow90Provider);
    final flow30 = ref.watch(_flow30Provider);

    return Scaffold(
      appBar: AppBar(title: const Text('Análises e gráficos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader('Fluxo de caixa — 30 dias'),
          flow30.when(
            loading: () => const SizedBox(
                height: 220, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorRetry(
                message: '$e', onRetry: () => ref.invalidate(_flow30Provider)),
            data: (days) => _CashFlowChart(days: days),
          ),
          const SectionHeader('Gastos por categoria (mês)'),
          categories.when(
            loading: () => const SizedBox(
                height: 200, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorRetry(
                message: '$e',
                onRetry: () => ref.invalidate(_categorySpendProvider)),
            data: (data) => data.isEmpty
                ? const AppCard(
                    child: SizedBox(
                        height: 120,
                        child: Center(child: Text('Sem despesas no mês.'))))
                : Column(children: [
                    _CategoryPie(data: data),
                    const SizedBox(height: 12),
                    _Treemap(data: data),
                  ]),
          ),
          const SectionHeader('Evolução acumulada (90 dias)'),
          flow.when(
            loading: () => const SizedBox(
                height: 200, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorRetry(
                message: '$e', onRetry: () => ref.invalidate(_flow90Provider)),
            data: (days) => _EvolutionChart(days: days),
          ),
          const SectionHeader('Heatmap por dia da semana'),
          heatmap.when(
            loading: () => const SizedBox(
                height: 120, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorRetry(
                message: '$e', onRetry: () => ref.invalidate(_heatmapProvider)),
            data: (map) => _WeekdayHeatmap(totals: map),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart({required this.days});

  final List<DailyFlow> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const AppCard(
          child: SizedBox(
              height: 180,
              child: Center(child: Text('Sem movimentações ainda.'))));
    }

    List<FlSpot> spots(double Function(DailyFlow) pick) => [
          for (var i = 0; i < days.length; i++)
            FlSpot(i.toDouble(), pick(days[i])),
        ];

    LineChartBarData line(List<FlSpot> s, Color color) => LineChartBarData(
          spots: s,
          isCurved: true,
          curveSmoothness: 0.3,
          color: color,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withOpacity(0.25), color.withOpacity(0)],
            ),
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Legend(color: AppColors.neonGreen, label: 'Receitas'),
              const SizedBox(width: 16),
              _Legend(color: AppColors.red, label: 'Despesas'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color:
                        Theme.of(context).colorScheme.outline.withOpacity(0.4),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (v, _) => Text(v.brlCompact,
                          style: Theme.of(context).textTheme.labelSmall),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: (days.length / 4).ceilToDouble(),
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= days.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(days[i].day.dayMonth,
                              style: Theme.of(context).textTheme.labelSmall),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${days[s.x.toInt()].day.dayMonth}\n${s.y.brl}',
                              TextStyle(
                                  color: s.bar.color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  line(spots((d) => d.revenue), AppColors.neonGreen),
                  line(spots((d) => d.expense), AppColors.red),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CategoryPie extends StatelessWidget {
  const _CategoryPie({required this.data});

  final List<CategorySpend> data;

  @override
  Widget build(BuildContext context) {
    final total = data.fold<double>(0, (s, c) => s + c.total);

    return AppCard(
      child: SizedBox(
        height: 240,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 3,
                  centerSpaceRadius: 44,
                  sections: [
                    for (final c in data)
                      PieChartSectionData(
                        value: c.total,
                        color: AppColors.categoryColor(c.category),
                        radius: 56,
                        title: total == 0
                            ? ''
                            : '${(c.total / total * 100).toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  for (final c in data.take(8))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.categoryColor(c.category),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(c.category,
                                style:
                                    Theme.of(context).textTheme.labelSmall,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text(c.total.brlCompact,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Squarified-ish treemap (slice-and-dice alternating orientation).
class _Treemap extends StatelessWidget {
  const _Treemap({required this.data});

  final List<CategorySpend> data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 200,
        child: LayoutBuilder(
          builder: (context, constraints) => CustomMultiChildLayout(
            delegate: _TreemapDelegate(data),
            children: [
              for (var i = 0; i < data.length; i++)
                LayoutId(
                  id: i,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.categoryColor(data[i].category)
                          .withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data[i].category,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                          Text(data[i].total.brlCompact,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TreemapDelegate extends MultiChildLayoutDelegate {
  _TreemapDelegate(this.data);

  final List<CategorySpend> data;

  @override
  void performLayout(Size size) {
    final total = data.fold<double>(0, (s, c) => s + c.total);
    var rect = Offset.zero & size;
    var remaining = total;

    for (var i = 0; i < data.length; i++) {
      final frac = remaining <= 0 ? 0.0 : data[i].total / remaining;
      Size cell;
      Offset origin = rect.topLeft;

      if (i == data.length - 1) {
        cell = rect.size;
      } else if (rect.width >= rect.height) {
        cell = Size(rect.width * frac, rect.height);
        rect = Rect.fromLTRB(
            rect.left + cell.width, rect.top, rect.right, rect.bottom);
      } else {
        cell = Size(rect.width, rect.height * frac);
        rect = Rect.fromLTRB(
            rect.left, rect.top + cell.height, rect.right, rect.bottom);
      }

      layoutChild(i, BoxConstraints.tight(cell));
      positionChild(i, origin);
      remaining -= data[i].total;
    }
  }

  @override
  bool shouldRelayout(covariant _TreemapDelegate oldDelegate) =>
      oldDelegate.data != data;
}

class _EvolutionChart extends StatelessWidget {
  const _EvolutionChart({required this.days});

  final List<DailyFlow> days;

  @override
  Widget build(BuildContext context) {
    var running = 0.0;
    final spots = <FlSpot>[];
    for (var i = 0; i < days.length; i++) {
      running += days[i].revenue - days[i].expense;
      spots.add(FlSpot(i.toDouble(), running));
    }
    final positive = running >= 0;
    final color = positive ? AppColors.neonGreen : AppColors.red;

    return AppCard(
      child: SizedBox(
        height: 200,
        child: spots.isEmpty
            ? const Center(child: Text('Sem dados.'))
            : LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        getTitlesWidget: (v, _) => Text(v.brlCompact,
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withOpacity(0.25),
                            color.withOpacity(0)
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _WeekdayHeatmap extends StatelessWidget {
  const _WeekdayHeatmap({required this.totals});

  final Map<int, double> totals;

  @override
  Widget build(BuildContext context) {
    final max = totals.values.isEmpty
        ? 1.0
        : totals.values.reduce((a, b) => a > b ? a : b);

    return AppCard(
      child: Row(
        children: [
          for (var d = 1; d <= 7; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(
                            0.08 + 0.72 * ((totals[d] ?? 0) / max)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (totals[d] ?? 0).brlCompact,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(weekdayLabelsPt[d - 1],
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
