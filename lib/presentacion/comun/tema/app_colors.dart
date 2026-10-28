// CAPA: PRESENTACIÓN — sistema de diseño (tema)
// Paleta de colores. No hace: no sabe de alertas ni de pantallas.

import 'package:flutter/material.dart';

/// Paleta oficial de SafeLink (sección 8.2 del contexto de desarrollo).
///
/// REGLA: ninguna vista usa `Color(0x...)` ni `Colors.*` directamente.
/// Si necesitas un color nuevo, agrégalo aquí y documéntalo en
/// `docs/GUIA_ESTILOS.md`.
abstract final class AppColors {
  // ── Fondos y superficies (tema oscuro) ─────────────────────────────
  /// Fondo general de todas las pantallas.
  static const background = Color(0xFF0F172A);

  /// Tarjetas, hojas inferiores, campos de texto.
  static const surface = Color(0xFF1E293B);

  /// Superficie elevada: tarjeta dentro de tarjeta, elemento seleccionado.
  static const surfaceElevated = Color(0xFF273449);

  /// Bordes y divisores.
  static const border = Color(0xFF334155);

  /// Fondo del mapa simulado (se ajusta al estilo oscuro de Google Maps).
  static const mapBase = Color(0xFF16213A);

  // ── Texto ──────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF64748B);

  /// Texto sobre un color sólido (botones rojo/azul/verde).
  static const onAccent = Color(0xFFFFFFFF);

  /// Texto sobre ámbar (el blanco no tiene contraste suficiente).
  static const onWarning = Color(0xFF1C1917);

  // ── Semánticos ─────────────────────────────────────────────────────
  /// SOLO botón de alerta y alertas activas. No usar para errores de
  /// formulario ni acciones destructivas comunes (para eso: [danger]).
  static const emergency = Color(0xFFEF4444);
  static const emergencyDark = Color(0xFFB91C1C);

  /// Urgente (alerta por agitación) / pendiente.
  static const warning = Color(0xFFF59E0B);

  /// Confirmado / seguro / guardia en turno.
  static const success = Color(0xFF22C55E);

  /// Mapas, navegación, enlaces, acción primaria del guardia y admin.
  static const info = Color(0xFF3B82F6);

  /// Errores de formulario y acciones destructivas (eliminar, dar de baja).
  /// Es un rojo más apagado para no competir con [emergency].
  static const danger = Color(0xFFF87171);

  // ── Fondos tenues (chips, banners) ─────────────────────────────────
  static Color tint(Color c) => c.withValues(alpha: 0.15);
  static Color tintBorder(Color c) => c.withValues(alpha: 0.40);
}
