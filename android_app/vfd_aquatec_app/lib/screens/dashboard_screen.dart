import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vfd_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/freq_gauge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vfd = context.watch<VfdProvider>();
    final d   = vfd.data;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status banner ──────────────────────────────────────────────
          _StatusBanner(vfd: vfd),
          const SizedBox(height: 20),

          // ── Frequency gauge ────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SectionTitle('FRÉQUENCE MOTEUR'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: FreqGauge(
                      current: vfd.displayFreq,
                      target:  d.targetFrequency,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Metrics grid ───────────────────────────────────────────────
          const SectionTitle('PARAMÈTRES EN TEMPS RÉEL'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.3,
            children: [
              MetricCard(
                label: 'TEMPÉRATURE',
                value: d.temperature.toStringAsFixed(1),
                unit:  '°C',
                icon:  Icons.thermostat,
                color: _tempColor(d.temperature),
                progress: (d.temperature - 20) / 60,
              ),
              MetricCard(
                label: 'PRESSION',
                value: d.pressure.toStringAsFixed(2),
                unit:  'bar',
                icon:  Icons.speed,
                color: AppTheme.info,
                progress: d.pressure / 4.0,
              ),
              MetricCard(
                label: 'DÉBIT',
                value: d.flowRate.toStringAsFixed(1),
                unit:  'L/min',
                icon:  Icons.water,
                color: AppTheme.accent,
                progress: d.flowRate / 18.0,
              ),
              MetricCard(
                label: 'PUISSANCE',
                value: (d.power / 1000).toStringAsFixed(2),
                unit:  'kW',
                icon:  Icons.bolt,
                color: AppTheme.warning,
                progress: d.power / 3000,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Quick controls ─────────────────────────────────────────────
          _QuickControls(vfd: vfd),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Color _tempColor(double t) {
    if (t < 35) return AppTheme.running;
    if (t < 55) return AppTheme.warning;
    return AppTheme.stopped;
  }
}

// ── Status Banner ──────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final VfdProvider vfd;
  const _StatusBanner({required this.vfd});

  @override
  Widget build(BuildContext context) {
    final running = vfd.data.motorRunning;
    final modeStr = ['—','AUTO','MANUEL','SÉQUENCE'][vfd.currentMode.clamp(0,3)];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: running
            ? [AppTheme.running.withOpacity(0.2), AppTheme.running.withOpacity(0.05)]
            : [AppTheme.stopped.withOpacity(0.2), AppTheme.stopped.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: running ? AppTheme.running : AppTheme.stopped,
          width: 1.5,
        ),
      ),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 14, height: 14,
          decoration: BoxDecoration(
            color: running ? AppTheme.running : AppTheme.stopped,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (running ? AppTheme.running : AppTheme.stopped).withOpacity(0.6),
                blurRadius: 8, spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            running ? 'POMPE EN MARCHE' : 'POMPE ARRÊTÉE',
            style: TextStyle(
              color: running ? AppTheme.running : AppTheme.stopped,
              fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5,
            ),
          ),
          Text('Mode : $modeStr  |  ${vfd.simMode ? "SIMULATION" : "BLE"}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ]),
        const Spacer(),
        Icon(
          running ? Icons.play_circle : Icons.stop_circle,
          color: running ? AppTheme.running : AppTheme.stopped,
          size: 36,
        ),
      ]),
    );
  }
}

// ── Quick Controls ─────────────────────────────────────────────────────────
class _QuickControls extends StatelessWidget {
  final VfdProvider vfd;
  const _QuickControls({required this.vfd});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('CONTRÔLE RAPIDE'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: vfd.data.motorRunning ? null : vfd.motorStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('START'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.running,
                    disabledBackgroundColor: AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: vfd.data.motorRunning ? vfd.motorStop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('STOP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.stopped,
                    disabledBackgroundColor: AppTheme.textMuted,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            _FreqSlider(vfd: vfd),
          ],
        ),
      ),
    );
  }
}

class _FreqSlider extends StatefulWidget {
  final VfdProvider vfd;
  const _FreqSlider({required this.vfd});
  @override
  State<_FreqSlider> createState() => _FreqSliderState();
}

class _FreqSliderState extends State<_FreqSlider> {
  double _val = 25.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _val = widget.vfd.data.targetFrequency.clamp(5.0, 50.0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Fréquence cible',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text('${_val.toStringAsFixed(1)} Hz',
            style: const TextStyle(
              color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.border,
            thumbColor: AppTheme.primary,
            overlayColor: AppTheme.primary.withOpacity(0.2),
          ),
          child: Slider(
            value: _val, min: 5, max: 50, divisions: 45,
            onChanged: (v) => setState(() => _val = v),
            onChangeEnd: (v) => widget.vfd.setFrequency(v),
          ),
        ),
      ],
    );
  }
}
