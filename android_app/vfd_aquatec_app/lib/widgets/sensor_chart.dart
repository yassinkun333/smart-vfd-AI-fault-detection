import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/vfd_data.dart';
import '../theme/app_theme.dart';

class SensorLineChart extends StatelessWidget {
  final List<ChartPoint> points;
  final String  label;
  final String  unit;
  final Color   color;
  final double  minY;
  final double  maxY;

  const SensorLineChart({
    super.key,
    required this.points,
    required this.label,
    required this.unit,
    required this.color,
    this.minY = 0,
    this.maxY = 100,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: const Text('En attente de données...',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      );
    }

    final spots = <FlSpot>[];
    final t0    = points.first.time.millisecondsSinceEpoch.toDouble();
    for (final p in points) {
      final x = (p.time.millisecondsSinceEpoch - t0) / 1000.0;
      spots.add(FlSpot(x, p.value));
    }

    final last = points.last.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label,
            style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 13,
              fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${last.toStringAsFixed(1)} $unit',
            style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: LineChart(
            LineChartData(
              minY: minY, maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                  FlLine(color: AppTheme.border, strokeWidth: 0.8),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 38,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 10),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.surface,
                  getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(1)} $unit',
                    TextStyle(color: color, fontWeight: FontWeight.bold),
                  )).toList(),
                ),
              ),
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
                      colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
