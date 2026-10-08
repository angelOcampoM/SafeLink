import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import 'layout_widgets.dart';
import 'sl_card.dart';
import 'sl_chip.dart';

/// Tarjeta de alerta reutilizada en el listado del guardia (G-03), la
/// bandeja de escaladas (A-04) y el historial (A-05).
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.alert,
    required this.now,
    this.distanceMeters,
    this.onTap,
    this.showStatus = true,
  });

  final Alert alert;
  final DateTime now;
  final double? distanceMeters;
  final VoidCallback? onTap;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final accent = alert.isUrgent
        ? AppColors.warning
        : (alert.status.isActive ? AppColors.emergency : null);

    return SlCard(
      accent: accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(_initials(alert.userName), color: accent ?? AppColors.info),
              AppSpacing.gapSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.userName ?? 'Usuario', style: context.text.titleMedium),
                    Text(
                      '${Fmt.dateTime(alert.triggeredAt)} · ${Fmt.ago(alert.triggeredAt, now)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (distanceMeters != null)
                Text(Fmt.distance(distanceMeters!), style: context.text.titleMedium?.copyWith(color: AppColors.info)),
            ],
          ),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              TriggerChip(alert.triggerMethod),
              if (showStatus) StatusChip(alert.status),
              if (alert.evidenceIncomplete)
                const SlChip(label: 'Sin foto', color: AppColors.textSecondary, icon: Icons.no_photography_outlined),
              if (alert.escalationReason != null)
                SlChip(label: alert.escalationReason!.label, color: AppColors.warning, icon: Icons.schedule_rounded),
              if (alert.resolution != null) SlChip.fromStyle(alert.resolution!.style),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    return name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
  }
}
