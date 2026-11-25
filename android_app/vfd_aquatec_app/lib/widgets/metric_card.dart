import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MetricCard extends StatelessWidget {
  final String  label;
  final String  value;
  final String  unit;
  final IconData icon;
  final Color   color;
  final double? progress; // 0.0–1.0 optional progress bar

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.color = AppTheme.primary,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12, fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                style: TextStyle(
                  color: color, fontSize: 26,
                  fontWeight: FontWeight.w700, letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit,
                  style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final bool running;
  const StatusBadge({super.key, required this.running});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: (running ? AppTheme.running : AppTheme.stopped).withOpacity(0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: running ? AppTheme.running : AppTheme.stopped,
          width: 1.5,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: running ? AppTheme.running : AppTheme.stopped,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          running ? 'EN MARCHE' : 'ARRÊTÉ',
          style: TextStyle(
            color: running ? AppTheme.running : AppTheme.stopped,
            fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1,
          ),
        ),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12, fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
