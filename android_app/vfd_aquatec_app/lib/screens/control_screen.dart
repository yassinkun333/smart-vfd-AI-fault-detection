import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vfd_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final vfd = context.watch<VfdProvider>();

    return Column(
      children: [
        // Mode selector
        Container(
          color: AppTheme.surface,
          child: TabBar(
            controller: _tabs,
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              letterSpacing: 0.5),
            onTap: (i) => vfd.setMode(i + 1),
            tabs: const [
              Tab(text: 'MODE 1\nAUTO',    height: 48),
              Tab(text: 'MODE 2\nMANUEL',  height: 48),
              Tab(text: 'MODE 3\nSÉQUENCE',height: 48),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _Mode1Auto(vfd: vfd),
              _Mode2Manual(vfd: vfd),
              _Mode3Sequence(vfd: vfd),
            ],
          ),
        ),
      ],
    );
  }
}

// ── MODE 1 AUTO ──────────────────────────────────────────────────────────────
class _Mode1Auto extends StatelessWidget {
  final VfdProvider vfd;
  const _Mode1Auto({required this.vfd});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryDark, AppTheme.primary],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: [
            const Icon(Icons.auto_mode, size: 56, color: Colors.white),
            const SizedBox(height: 16),
            const Text('MODE AUTO', style: TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Le moteur démarre automatiquement\nà 50 Hz dès activation',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () { vfd.setMode(1); },
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text('ACTIVER MODE AUTO', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: vfd.motorStop,
                icon: const Icon(Icons.stop, color: Colors.white),
                label: const Text('STOP', style: TextStyle(color: Colors.white, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        _StatusCard(vfd: vfd),
      ]),
    );
  }
}

// ── MODE 2 MANUAL ────────────────────────────────────────────────────────────
class _Mode2Manual extends StatefulWidget {
  final VfdProvider vfd;
  const _Mode2Manual({required this.vfd});
  @override
  State<_Mode2Manual> createState() => _Mode2ManualState();
}

class _Mode2ManualState extends State<_Mode2Manual> {
  double _freq = 25.0;

  @override
  Widget build(BuildContext context) {
    final vfd = widget.vfd;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 8),
        // Freq slider card
        Card(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('FRÉQUENCE CIBLE'),
              const SizedBox(height: 20),
              Center(
                child: Text('${_freq.toStringAsFixed(1)} Hz',
                  style: const TextStyle(
                    color: AppTheme.primary, fontSize: 48,
                    fontWeight: FontWeight.w800, letterSpacing: -1,
                  )),
              ),
              Center(child: Text('≈ ${(_freq * 60).toStringAsFixed(0)} tr/min',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15))),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.primary,
                  inactiveTrackColor: AppTheme.border,
                  thumbColor: AppTheme.primary,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  trackHeight: 6,
                ),
                child: Slider(
                  value: _freq, min: 5, max: 50, divisions: 45,
                  onChanged: (v) => setState(() => _freq = v),
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('5 Hz', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  Text('50 Hz', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => vfd.setFrequency(_freq),
                  icon: const Icon(Icons.tune),
                  label: const Text('APPLIQUER FRÉQUENCE'),
                ),
              ),
            ],
          ),
        )),
        const SizedBox(height: 12),
        // Start / Stop
        Row(children: [
          Expanded(child: _BigBtn(
            label: 'START', icon: Icons.play_circle_fill,
            color: AppTheme.running,
            onTap: () { vfd.setFrequency(_freq); vfd.motorStart(); },
          )),
          const SizedBox(width: 12),
          Expanded(child: _BigBtn(
            label: 'STOP', icon: Icons.stop_circle,
            color: AppTheme.stopped,
            onTap: vfd.motorStop,
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _BigBtn(
            label: 'STATUS', icon: Icons.info_outline,
            color: AppTheme.info,
            onTap: vfd.getStatus,
          )),
          const SizedBox(width: 12),
          Expanded(child: _BigBtn(
            label: 'TELEM ON', icon: Icons.sensors,
            color: AppTheme.warning,
            onTap: vfd.telemOn,
          )),
        ]),
        const SizedBox(height: 12),
        _StatusCard(vfd: vfd),
        const SizedBox(height: 80),
      ]),
    );
  }
}

// ── MODE 3 SEQUENCE ──────────────────────────────────────────────────────────
class _Mode3Sequence extends StatefulWidget {
  final VfdProvider vfd;
  const _Mode3Sequence({required this.vfd});
  @override
  State<_Mode3Sequence> createState() => _Mode3SequenceState();
}

class _Mode3SequenceState extends State<_Mode3Sequence> {
  double _addFreq = 30.0;
  int    _addSec  = 10;

  @override
  Widget build(BuildContext context) {
    final vfd = widget.vfd;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Add step card
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('AJOUTER UNE ÉTAPE'),
                const SizedBox(height: 16),
                // Freq
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Fréquence',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  Text('${_addFreq.toStringAsFixed(1)} Hz',
                    style: const TextStyle(color: AppTheme.primary,
                      fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
                Slider(
                  value: _addFreq, min: 5, max: 50, divisions: 45,
                  activeColor: AppTheme.primary,
                  inactiveColor: AppTheme.border,
                  onChanged: (v) => setState(() => _addFreq = v),
                ),
                const SizedBox(height: 4),
                // Duration
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Durée',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  Text('$_addSec s',
                    style: const TextStyle(color: AppTheme.accent,
                      fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
                Slider(
                  value: _addSec.toDouble(), min: 1, max: 120, divisions: 119,
                  activeColor: AppTheme.accent,
                  inactiveColor: AppTheme.border,
                  onChanged: (v) => setState(() => _addSec = v.round()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      vfd.seqAdd(_addFreq, _addSec);
                      setState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: Text(
                      'AJOUTER  ${_addFreq.toStringAsFixed(1)} Hz  /  $_addSec s'),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 12),

          // Sequence list
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  SectionTitle('SÉQUENCE  (${vfd.seqSteps.length} étapes)'),
                  TextButton.icon(
                    onPressed: () { vfd.seqClear(); setState(() {}); },
                    icon: const Icon(Icons.delete_outline, size: 16,
                      color: AppTheme.stopped),
                    label: const Text('EFFACER',
                      style: TextStyle(color: AppTheme.stopped, fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 8),
                if (vfd.seqSteps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('Aucune étape.\nAjoute une étape ci-dessus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13))),
                  )
                else
                  ...vfd.seqSteps.asMap().entries.map((e) {
                    final active = vfd.seqRunning && vfd.seqCurStep == e.key;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: active
                          ? AppTheme.primary.withOpacity(0.15)
                          : AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active ? AppTheme.primary : AppTheme.border,
                          width: active ? 1.5 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: active
                              ? AppTheme.primary
                              : AppTheme.primary.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text('${e.key+1}',
                            style: TextStyle(
                              color: active ? Colors.white : AppTheme.primary,
                              fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 14),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${e.value.freqHz.toStringAsFixed(1)} Hz',
                            style: const TextStyle(color: AppTheme.textPrimary,
                              fontSize: 15, fontWeight: FontWeight.w700)),
                          Text('${e.value.durationSec} secondes',
                            style: const TextStyle(color: AppTheme.textSecondary,
                              fontSize: 12)),
                        ]),
                        const Spacer(),
                        if (active)
                          const Icon(Icons.play_arrow,
                            color: AppTheme.primary, size: 22),
                      ]),
                    );
                  }),
              ],
            ),
          )),
          const SizedBox(height: 12),

          // GO / STOP
          Row(children: [
            Expanded(child: _BigBtn(
              label: 'GO',
              icon: Icons.play_circle_fill,
              color: AppTheme.running,
              onTap: vfd.seqSteps.isEmpty ? null : vfd.seqGo,
            )),
            const SizedBox(width: 12),
            Expanded(child: _BigBtn(
              label: 'STOP',
              icon: Icons.stop_circle,
              color: AppTheme.stopped,
              onTap: vfd.seqStop,
            )),
          ]),

          if (vfd.seqRunning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.running.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.running.withOpacity(0.4)),
              ),
              child: Row(children: [
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.running),
                ),
                const SizedBox(width: 12),
                Text(
                  'Étape ${vfd.seqCurStep+1}/${vfd.seqSteps.length} en cours...',
                  style: const TextStyle(color: AppTheme.running, fontSize: 13,
                    fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────
class _BigBtn extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final VoidCallback? onTap;
  const _BigBtn({required this.label, required this.icon,
                 required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      label: Text(label, style: const TextStyle(fontSize: 15,
        fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: onTap == null ? AppTheme.textMuted : color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final VfdProvider vfd;
  const _StatusCard({required this.vfd});

  @override
  Widget build(BuildContext context) {
    final d = vfd.data;
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SectionTitle('ÉTAT SYSTÈME'),
        const SizedBox(height: 12),
        _Row('Moteur', d.motorRunning ? 'EN MARCHE' : 'ARRÊTÉ',
          d.motorRunning ? AppTheme.running : AppTheme.stopped),
        _Row('Fréquence réelle', '${d.frequency.toStringAsFixed(1)} Hz', AppTheme.primary),
        _Row('Fréquence cible',  '${d.targetFrequency.toStringAsFixed(1)} Hz', AppTheme.accent),
        _Row('Amplitude', d.amplitude.toStringAsFixed(3), AppTheme.textSecondary),
        _Row('Puissance', '${(d.power/1000).toStringAsFixed(2)} kW', AppTheme.warning),
      ]),
    ));
  }
}

class _Row extends StatelessWidget {
  final String k, v; final Color c;
  const _Row(this.k, this.v, this.c);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      Text(v, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w700)),
    ]),
  );
}
