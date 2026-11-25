import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/vfd_provider.dart';
import '../theme/app_theme.dart';

class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});
  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();

  final _quickCmds = [
    'STATUS','TELEM ON','TELEM OFF',
    'START','STOP',
    'FREQ 20','FREQ 30','FREQ 40','FREQ 50',
    'MODE 1','MODE 2','MODE 3',
    'ADD 30 10','ADD 50 8','LIST','CLEAR','GO',
  ];

  void _send(BuildContext context, String cmd) {
    if (cmd.trim().isEmpty) return;
    context.read<VfdProvider>().sendCommand(cmd.trim());
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final vfd = context.watch<VfdProvider>();

    return Column(
      children: [
        // Quick command chips
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('COMMANDES RAPIDES',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10,
                  fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickCmds.map((cmd) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => _send(context, cmd),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(cmd,
                          style: const TextStyle(
                            color: AppTheme.primary, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),

        // Log area
        Expanded(
          child: Container(
            color: const Color(0xFF070B14),
            child: vfd.consoleLog.isEmpty
              ? const Center(child: Text('Console vide.\nEnvoie une commande...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)))
              : SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    vfd.consoleLog,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF88),
                      fontSize: 12, height: 1.6,
                    ),
                  ),
                ),
          ),
        ),

        // Input bar
        Container(
          color: AppTheme.surface,
          padding: EdgeInsets.only(
            left: 12, right: 12, top: 10,
            bottom: MediaQuery.of(context).viewInsets.bottom + 10,
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Tape une commande...',
                  prefixText: '> ',
                  prefixStyle: TextStyle(color: AppTheme.primary,
                    fontFamily: 'monospace', fontWeight: FontWeight.w700),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onSubmitted: (v) => _send(context, v),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _send(context, _ctrl.text),
              icon: const Icon(Icons.send, color: AppTheme.primary),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary.withOpacity(0.15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: vfd.clearConsole,
              icon: const Icon(Icons.delete_sweep, color: AppTheme.textMuted),
              tooltip: 'Effacer console',
            ),
          ]),
        ),
      ],
    );
  }
}
