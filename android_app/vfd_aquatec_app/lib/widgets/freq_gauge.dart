import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FreqGauge extends StatelessWidget {
  final double current;
  final double target;
  final double maxFreq;

  const FreqGauge({
    super.key,
    required this.current,
    required this.target,
    this.maxFreq = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _GaugePainter(
          current: current.clamp(0, maxFreq),
          target:  target.clamp(0, maxFreq),
          maxFreq: maxFreq,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 30),
              Text(
                current.toStringAsFixed(1),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 40, fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const Text('Hz',
                style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cible: ${target.toStringAsFixed(1)} Hz',
                style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 12,
                ),
              ),
              Text(
                '${(current * 60).toStringAsFixed(0)} tr/min',
                style: const TextStyle(
                  color: AppTheme.accent, fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double current, target, maxFreq;
  _GaugePainter({required this.current, required this.target, required this.maxFreq});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = min(cx, cy) - 16;

    const startAngle = pi * 0.75;
    const sweepTotal = pi * 1.5;

    final bgPaint = Paint()
      ..color = AppTheme.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final targetPaint = Paint()
      ..color = AppTheme.primary.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final curPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: pi * 2,
        colors: [AppTheme.primaryDark, AppTheme.primary, AppTheme.accent],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, sweepTotal, false, bgPaint,
    );

    // Target arc
    final tSweep = (target / maxFreq) * sweepTotal;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      startAngle, tSweep, false, targetPaint,
    );

    // Current arc
    final cSweep = (current / maxFreq) * sweepTotal;
    if (cSweep > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        startAngle, cSweep, false, curPaint,
      );
    }

    // Tick marks
    final tickPaint = Paint()
      ..color = AppTheme.textMuted
      ..strokeWidth = 1.5;
    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + (i / 10) * sweepTotal;
      final inner = r - 10;
      final outer = r + 4;
      canvas.drawLine(
        Offset(cx + inner * cos(angle), cy + inner * sin(angle)),
        Offset(cx + outer * cos(angle), cy + outer * sin(angle)),
        tickPaint,
      );
    }

    // Needle dot
    final needleAngle = startAngle + cSweep;
    final nx = cx + r * cos(needleAngle);
    final ny = cy + r * sin(needleAngle);
    canvas.drawCircle(Offset(nx, ny), 6,
      Paint()..color = AppTheme.primary..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(nx, ny), 6,
      Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.current != current || old.target != target;
}
