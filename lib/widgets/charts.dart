// Visual charts for the ledger, built on fl_chart. Theme-aware.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../calc.dart';
import '../format.dart';
import '../theme.dart';

class ChartFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final double height;
  const ChartFrame(
      {super.key,
      required this.title,
      required this.child,
      this.height = 200});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: pal.textLo,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }
}

/// Cumulative equity over closed trades.
class EquityCurveChart extends StatelessWidget {
  final List<EquityPoint> points;
  final String currency;
  const EquityCurveChart(this.points, {super.key, this.currency = 'PHP'});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    if (points.length < 2) {
      return ChartFrame(
        title: 'Equity curve',
        child: Center(
          child: Text('Not enough closed trades yet',
              style: TextStyle(color: pal.textLo)),
        ),
      );
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i].equity));
    }
    final values = points.map((e) => e.equity).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.1).clamp(1, double.infinity);
    final up = points.last.equity >= points.first.equity;
    final color = up ? NqeColors.gain : NqeColors.loss;

    return ChartFrame(
      title: 'Equity curve',
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: pal.line, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  compactMoney(v, currency: currency),
                  style: TextStyle(color: pal.textLo, fontSize: 9),
                ),
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
              belowBarData:
                  BarAreaData(show: true, color: color.withOpacity(0.12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Monthly realised P&L bars.
class MonthlyPnlChart extends StatelessWidget {
  final List<MonthStat> stats;
  const MonthlyPnlChart(this.stats, {super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    if (stats.isEmpty) {
      return ChartFrame(
        title: 'Monthly P&L',
        child: Center(
          child:
              Text('No monthly data yet', style: TextStyle(color: pal.textLo)),
        ),
      );
    }
    final maxAbs =
        stats.map((s) => s.pnl.abs()).fold<double>(1, (a, b) => a > b ? a : b);
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < stats.length; i++) {
      final s = stats[i];
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: s.pnl,
          color: NqeColors.pnl(s.pnl),
          width: 14,
          borderRadius: BorderRadius.circular(3),
        ),
      ]));
    }
    return ChartFrame(
      title: 'Monthly P&L',
      child: BarChart(
        BarChartData(
          maxY: maxAbs * 1.2,
          minY: -maxAbs * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: pal.line, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= stats.length) return const SizedBox();
                  final parts = stats[i].label.split(' ');
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(parts.first,
                        style: TextStyle(color: pal.textLo, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          barGroups: groups,
        ),
      ),
    );
  }
}

/// Win / loss split donut.
class WinLossDonut extends StatelessWidget {
  final int wins;
  final int losses;
  const WinLossDonut({super.key, required this.wins, required this.losses});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final total = wins + losses;
    if (total == 0) {
      return ChartFrame(
        title: 'Win / loss',
        height: 160,
        child: Center(
          child: Text('No closed trades yet',
              style: TextStyle(color: pal.textLo)),
        ),
      );
    }
    return ChartFrame(
      title: 'Win / loss',
      height: 160,
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 34,
                sections: [
                  PieChartSectionData(
                    value: wins.toDouble(),
                    color: NqeColors.gain,
                    title: '$wins',
                    radius: 26,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                  PieChartSectionData(
                    value: losses.toDouble(),
                    color: NqeColors.loss,
                    title: '$losses',
                    radius: 26,
                    titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${((wins / total) * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: pal.textHi,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
              Text('win rate', style: TextStyle(color: pal.textLo, fontSize: 12)),
              const SizedBox(height: 10),
              _legend(NqeColors.gain, 'Wins  $wins', pal.textLo),
              _legend(NqeColors.loss, 'Losses  $losses', pal.textLo),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _legend(Color c, String t, Color textColor) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(color: textColor, fontSize: 12)),
        ]),
      );
}

/// AUM allocation across accounts.
class AllocationDonut extends StatelessWidget {
  final List<AccountMetrics> metrics;
  const AllocationDonut(this.metrics, {super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final positive = metrics.where((m) => m.equityPhp > 0).toList();
    if (positive.isEmpty) {
      return ChartFrame(
        title: 'Allocation',
        height: 170,
        child:
            Center(child: Text('No balances yet', style: TextStyle(color: pal.textLo))),
      );
    }
    final total = positive.fold<double>(0, (a, m) => a + m.equityPhp);
    return ChartFrame(
      title: 'Allocation (PHP)',
      height: 170,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                sections: [
                  for (final m in positive)
                    PieChartSectionData(
                      value: m.equityPhp,
                      color: Color(m.account.color),
                      title:
                          '${((m.equityPhp / total) * 100).toStringAsFixed(0)}%',
                      radius: 28,
                      titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in positive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: Color(m.account.color),
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(m.account.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: pal.textHi, fontSize: 12)),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
