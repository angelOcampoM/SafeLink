import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import 'app_colors.dart';

/// Color e ícono de cada estado de alerta. Es la ÚNICA fuente para pintar
/// estados: chips, líneas de tiempo, filas del historial, etc.
///
/// ```dart
/// final style = alert.status.style;  // .color, .icon, .label
/// ```
class StatusStyle {
  const StatusStyle(this.color, this.icon, this.label);
  final Color color;
  final IconData icon;
  final String label;
}

extension AlertStatusStyle on AlertStatus {
  StatusStyle get style => switch (this) {
        AlertStatus.pendingLocation => StatusStyle(AppColors.warning, Icons.location_searching_rounded, label),
        AlertStatus.searching => StatusStyle(AppColors.emergency, Icons.radar_rounded, label),
        AlertStatus.inProgress => StatusStyle(AppColors.info, Icons.directions_run_rounded, label),
        AlertStatus.guardArrived => StatusStyle(AppColors.success, Icons.shield_rounded, label),
        AlertStatus.closed => StatusStyle(AppColors.success, Icons.check_circle_rounded, label),
        AlertStatus.noResponse => StatusStyle(AppColors.warning, Icons.timer_off_rounded, label),
        AlertStatus.escalated => StatusStyle(AppColors.warning, Icons.priority_high_rounded, label),
        AlertStatus.resolvedByAdmin => StatusStyle(AppColors.textSecondary, Icons.gavel_rounded, label),
      };
}

extension TriggerMethodStyle on TriggerMethod {
  StatusStyle get style => switch (this) {
        TriggerMethod.tap => StatusStyle(AppColors.textSecondary, Icons.touch_app_rounded, label),
        TriggerMethod.hold => StatusStyle(AppColors.textSecondary, Icons.pan_tool_rounded, label),
        // Agitación = urgente (sección 6.3): se destaca en ámbar.
        TriggerMethod.shake => StatusStyle(AppColors.warning, Icons.vibration_rounded, label),
      };
}

extension ResolutionStyle on Resolution {
  StatusStyle get style => switch (this) {
        Resolution.resolved => StatusStyle(AppColors.success, Icons.check_rounded, label),
        Resolution.falseAlarm => StatusStyle(AppColors.danger, Icons.report_rounded, label),
        Resolution.serviceIncident => StatusStyle(AppColors.warning, Icons.build_circle_rounded, label),
      };
}
