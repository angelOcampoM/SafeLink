// CAPA: PRESENTACIÓN — sistema de diseño (tema)
// Espaciado, radios, tamaños y duraciones. No hace: no pinta nada por sí solo.

import 'package:flutter/widgets.dart';

/// Escala de espaciado (múltiplos de 4). Usar siempre estas constantes en
/// `padding`, `SizedBox` y `gap`; nunca números sueltos.
abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// Margen lateral estándar de las pantallas.
  static const screen = EdgeInsets.symmetric(horizontal: md, vertical: md);

  /// Relleno interno estándar de tarjetas.
  static const card = EdgeInsets.all(md);

  // Separadores listos para usar.
  static const gapXxs = SizedBox(width: xxs, height: xxs);
  static const gapXs = SizedBox(width: xs, height: xs);
  static const gapSm = SizedBox(width: sm, height: sm);
  static const gapMd = SizedBox(width: md, height: md);
  static const gapLg = SizedBox(width: lg, height: lg);
  static const gapXl = SizedBox(width: xl, height: xl);
}

/// Radios de borde. El estándar del proyecto es 16 px.
abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 16.0;
  static const pill = 999.0;

  static const brSm = BorderRadius.all(Radius.circular(sm));
  static const brMd = BorderRadius.all(Radius.circular(md));
  static const brPill = BorderRadius.all(Radius.circular(pill));
}

/// Tamaños mínimos y de componentes.
abstract final class AppSizes {
  /// Objetivo táctil mínimo (botones, filas tocables).
  static const touchTarget = 56.0;

  /// Diámetro del botón de emergencia del usuario protegido.
  static const emergencyButton = 220.0;

  static const iconSm = 18.0;
  static const iconMd = 24.0;
  static const iconLg = 32.0;
  static const iconXl = 56.0;

  static const avatar = 44.0;
}

/// Duraciones de animación.
abstract final class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const pulse = Duration(milliseconds: 1400);
}
