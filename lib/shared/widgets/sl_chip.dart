import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../data/models/enums.dart';

/// Etiqueta compacta de color (no interactiva).
class SlChip extends StatelessWidget {
  const SlChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  factory SlChip.fromStyle(StatusStyle s) => SlChip(label: s.label, color: s.color, icon: s.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs + 2),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: AppRadius.brPill,
        border: Border.all(color: AppColors.tintBorder(color)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(label, style: context.text.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Chip del estado de una alerta. `StatusChip(alert.status)`
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final AlertStatus status;

  @override
  Widget build(BuildContext context) => SlChip.fromStyle(status.style);
}

/// Chip del método de disparo. Agitación sale en ámbar como "Urgente".
class TriggerChip extends StatelessWidget {
  const TriggerChip(this.method, {super.key});
  final TriggerMethod method;

  @override
  Widget build(BuildContext context) {
    final s = method.style;
    return SlChip(
      label: method == TriggerMethod.shake ? 'Urgente · ${s.label}' : s.label,
      color: s.color,
      icon: s.icon,
    );
  }
}
