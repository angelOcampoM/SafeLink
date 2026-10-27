// CAPA: PRESENTACIÓN — sistema de diseño (tema)
// Color e ícono por estado de alerta, método y resolución (traduce enums del dominio a UI).
// No hace: no decide estados; solo los pinta.

import 'package:flutter/material.dart';

import '../../../dominio/enums.dart';
import 'app_colors.dart';

/// Color e ícono de cada estado de alerta. Es la ÚNICA fuente para pintar
/// estados: chips, líneas de tiempo, filas del historial, etc.
///
/// ```dart
/// final style = alerta.estado.style;  // .color, .icon, .label
/// ```
class StatusStyle {
  const StatusStyle(this.color, this.icon, this.label);
  final Color color;
  final IconData icon;
  final String label;
}

extension AlertStatusStyle on EstadoAlerta {
  StatusStyle get style => switch (this) {
        EstadoAlerta.pendienteUbicacion => StatusStyle(AppColors.warning, Icons.location_searching_rounded, etiqueta),
        EstadoAlerta.buscando => StatusStyle(AppColors.emergency, Icons.radar_rounded, etiqueta),
        EstadoAlerta.enAtencion => StatusStyle(AppColors.info, Icons.directions_run_rounded, etiqueta),
        EstadoAlerta.guardiaEnLugar => StatusStyle(AppColors.success, Icons.shield_rounded, etiqueta),
        EstadoAlerta.cerrada => StatusStyle(AppColors.success, Icons.check_circle_rounded, etiqueta),
        EstadoAlerta.sinRespuesta => StatusStyle(AppColors.warning, Icons.timer_off_rounded, etiqueta),
        EstadoAlerta.escalada => StatusStyle(AppColors.warning, Icons.priority_high_rounded, etiqueta),
        EstadoAlerta.resueltaPorAdmin => StatusStyle(AppColors.textSecondary, Icons.gavel_rounded, etiqueta),
      };
}

extension TriggerMethodStyle on MetodoDisparo {
  StatusStyle get style => switch (this) {
        MetodoDisparo.toque => StatusStyle(AppColors.textSecondary, Icons.touch_app_rounded, etiqueta),
        MetodoDisparo.mantener => StatusStyle(AppColors.textSecondary, Icons.pan_tool_rounded, etiqueta),
        // Agitación = urgente (sección 6.3): se destaca en ámbar.
        MetodoDisparo.agitacion => StatusStyle(AppColors.warning, Icons.vibration_rounded, etiqueta),
      };
}

extension ResolutionStyle on Resolucion {
  StatusStyle get style => switch (this) {
        Resolucion.resuelta => StatusStyle(AppColors.success, Icons.check_rounded, etiqueta),
        Resolucion.falsaAlarma => StatusStyle(AppColors.danger, Icons.report_rounded, etiqueta),
        Resolucion.incidenciaServicio => StatusStyle(AppColors.warning, Icons.build_circle_rounded, etiqueta),
      };
}
