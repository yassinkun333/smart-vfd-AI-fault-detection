import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vfd_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/sensor_chart.dart';

class ChartsScreen extends StatelessWidget {
  const ChartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vfd = context.watch<VfdProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('HISTORIQUE EN TEMPS RÉEL'),
          const SizedBox(height: 4),
          const Text('Mise à jour toutes les 2 secondes  •  60 points max',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 20),

          // Temperature
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: SensorLineChart(
              points: vfd.tempHistory,
              label: 'TEMPÉRATURE',
              unit:  '°C',
              color: const Color(0xFFFF6B6B),
              minY:  15, maxY: 80,
            ),
          )),
          const SizedBox(height: 12),

          // Pressure
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: SensorLineChart(
              points: vfd.presHistory,
              label: 'PRESSION',
              unit:  'bar',
              color: AppTheme.info,
              minY:  0, maxY: 4,
            ),
          )),
          const SizedBox(height: 12),

          // Flow
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: SensorLineChart(
              points: vfd.flowHistory,
              label: 'DÉBIT',
              unit:  'L/min',
              color: AppTheme.accent,
              minY:  0, maxY: 20,
            ),
          )),
          const SizedBox(height: 12),

          // Summary row
          Row(children: [
            Expanded(child: _MiniStat(
              label: 'Temp max',
              value: vfd.tempHistory.isEmpty ? '--'
                : vfd.tempHistory.map((p)=>p.value).reduce((a,b)=>a>b?a:b).toStringAsFixed(1),
              unit: '°C',
              color: const Color(0xFFFF6B6B),
            )),
            const SizedBox(width: 12),
            Expanded(child: _MiniStat(
              label: 'Pres max',
              value: vfd.presHistory.isEmpty ? '--'
                : vfd.presHistory.map((p)=>p.value).reduce((a,b)=>a>b?a:b).toStringAsFixed(2),
              unit: 'bar',
              color: AppTheme.info,
            )),
            const SizedBox(width: 12),
            Expanded(child: _MiniStat(
              label: 'Débit max',
              value: vfd.flowHistory.isEmpty ? '--'
                : vfd.flowHistory.map((p)=>p.value).reduce((a,b)=>a>b?a:b).toStringAsFixed(1),
              unit: 'L/min',
              color: AppTheme.accent,
            )),
          ]),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value, unit;
  final Color  color;
  const _MiniStat({required this.label, required this.value,
                   required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(children: [
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 10,
          fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Text('$value $unit',
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center),
      ]),
    );
  }
}
