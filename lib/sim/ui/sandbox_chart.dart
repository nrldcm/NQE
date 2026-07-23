// A lightweight live price line-chart for the Sandbox, built on fl_chart.
// Fed a rolling window of prices from the SandboxScreen (which appends a point
// each engine tick), so it animates in real time as the market moves.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../sim_models.dart';
import 'sandbox_common.dart';

class SandboxChart extends StatelessWidget {
  final List<double> history; // oldest → newest
  final SimMarket market;
  final double height;
  const SandboxChart({
    super.key,
    required this.history,
    required this.market,
    this.height = 190,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    if (history.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Collecting live prices…',
              style: TextStyle(color: pal.textLo, fontSize: 12)),
        ),
      );
    }

    final up = history.last >= history.first;
    final line = up ? NqeColors.gain : NqeColors.loss;
    var lo = history.reduce((a, b) => a < b ? a : b);
    var hi = history.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo).abs() < 1e-9 ? (hi.abs() * 0.001 + 1) : (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;

    final spots = <FlSpot>[
      for (var i = 0; i < history.length; i++) FlSpot(i.toDouble(), history[i]),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (history.length - 1).toDouble(),
          minY: lo,
          maxY: hi,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (hi - lo) / 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: pal.line.withOpacity(0.5), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: (hi - lo) / 2,
                getTitlesWidget: (v, meta) {
                  if (v <= meta.min || v >= meta.max) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(fmtPrice(v, market),
                        style: TextStyle(color: pal.textLo, fontSize: 9)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: line,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [line.withOpacity(0.22), line.withOpacity(0.0)],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 180),
      ),
    );
  }
}
