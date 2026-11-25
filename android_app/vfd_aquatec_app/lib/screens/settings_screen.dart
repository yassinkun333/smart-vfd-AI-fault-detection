import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vfd_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _tapCount = 0;
  bool _devUnlocked = false;

  @override
  Widget build(BuildContext context) {
    final vfd = context.watch<VfdProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection card
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('CONNEXION BLE'),
                const SizedBox(height: 16),
                _InfoRow('Statut', vfd.bleStatus,
                  vfd.bleConnected ? AppTheme.running : AppTheme.stopped),
                _InfoRow('Mode', vfd.simMode ? 'SIMULATION' : 'BLE RÉEL',
                  vfd.simMode ? AppTheme.warning : AppTheme.primary),
                const SizedBox(height: 16),
                if (!vfd.simMode) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: vfd.bleConnected ? null : vfd.startScan,
                      icon: vfd.scanning
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.bluetooth_searching),
                      label: Text(vfd.scanning
                        ? 'Recherche...'
                        : vfd.bleConnected
                          ? 'Connecté ✓'
                          : 'SCANNER & CONNECTER'),
                    ),
                  ),
                  if (vfd.bleConnected) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: vfd.disconnect,
                        icon: const Icon(Icons.bluetooth_disabled,
                          color: AppTheme.stopped),
                        label: const Text('DÉCONNECTER',
                          style: TextStyle(color: AppTheme.stopped)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.stopped)),
                      ),
                    ),
                  ],
                ],
                if (vfd.simMode) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.science, color: AppTheme.warning, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(child: Text(
                        'Mode simulation actif.\nLes valeurs sont générées localement.',
                        style: TextStyle(color: AppTheme.warning, fontSize: 13))),
                    ]),
                  ),
                ],
              ],
            ),
          )),
          const SizedBox(height: 16),

          // About card with hidden tap
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('À PROPOS'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    setState(() { _tapCount++; });
                    if (_tapCount >= 7) {
                      setState(() { _devUnlocked = true; });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mode développeur déverrouillé'),
                          backgroundColor: AppTheme.primaryDark,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else if (_tapCount >= 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Encore ${7-_tapCount} taps...'),
                          backgroundColor: AppTheme.surface,
                          duration: const Duration(milliseconds: 800),
                        ),
                      );
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('VFD-Aquatec IHM',
                        style: TextStyle(color: AppTheme.textPrimary,
                          fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('Version 1.0.0  •  Projet PFE ENIT',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      SizedBox(height: 4),
                      Text('Variateur de fréquence 3 kW',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                _InfoRow('MCU', 'STM32G474RET6', AppTheme.textSecondary),
                _InfoRow('Bridge', 'ESP32-WROOM-32E', AppTheme.textSecondary),
                _InfoRow('BLE', 'Nordic UART Service', AppTheme.textSecondary),
                _InfoRow('SPWM', '10 kHz porteur', AppTheme.textSecondary),
                _InfoRow('Puissance nominale', '3 kW', AppTheme.textSecondary),
              ],
            ),
          )),

          // ── HIDDEN DEVELOPER SECTION ─────────────────────────────────────
          if (_devUnlocked) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.warning, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.developer_mode,
                          color: AppTheme.warning, size: 20),
                        const SizedBox(width: 8),
                        const Text('MODE DÉVELOPPEUR',
                          style: TextStyle(color: AppTheme.warning,
                            fontSize: 13, fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                      ]),
                      const SizedBox(height: 16),

                      // THE HIDDEN SWITCH
                      Row(children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vfd.simMode
                                ? '🔬  MODE SIMULATION'
                                : '📡  MODE BLE RÉEL',
                              style: TextStyle(
                                color: vfd.simMode ? AppTheme.warning : AppTheme.primary,
                                fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              vfd.simMode
                                ? 'Capteurs simulés localement\nsans connexion matérielle'
                                : 'Données réelles via BLE\ndepuis ESP32 + STM32',
                              style: const TextStyle(color: AppTheme.textSecondary,
                                fontSize: 12),
                            ),
                          ],
                        )),
                        Switch(
                          value: vfd.simMode,
                          onChanged: (v) {
                            vfd.setSimMode(v);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(v
                                ? '🔬 Mode simulation activé'
                                : '📡 Mode BLE réel activé'),
                              backgroundColor: v ? AppTheme.warning : AppTheme.primary,
                              duration: const Duration(seconds: 2),
                            ));
                          },
                          activeColor: AppTheme.warning,
                          inactiveThumbColor: AppTheme.primary,
                          inactiveTrackColor: AppTheme.primary.withOpacity(0.3),
                        ),
                      ]),

                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('⚠  Pour la soutenance :',
                              style: TextStyle(color: AppTheme.warning,
                                fontSize: 12, fontWeight: FontWeight.w600)),
                            SizedBox(height: 4),
                            Text(
                              '• Simulation : démonstration sans matériel\n'
                              '• BLE réel : connexion ESP32 nécessaire\n'
                              '• Ce menu est accessible via 7 taps sur "À propos"',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 11,
                                height: 1.6)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String k, v; final Color c;
  const _InfoRow(this.k, this.v, this.c);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(k, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      Text(v, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}
