// CAPA: PRESENTACIÓN — sistema de diseño (tema)
// Escala tipográfica Inter. No hace: no elige estilos por pantalla.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Escala tipográfica. En las vistas se accede con
/// `Theme.of(context).textTheme.<estilo>` o con la extensión `context.text`
/// (ver `presentacion/comun/tema/theme_extensions.dart`).
///
/// | Estilo          | Tamaño | Uso                                         |
/// |-----------------|--------|---------------------------------------------|
/// | displayLarge    | 56     | Cuenta regresiva                             |
/// | displaySmall    | 32     | Cifras de métricas, ETA grande               |
/// | headlineMedium  | 24     | Título principal de pantalla                 |
/// | titleLarge      | 20     | Título de AppBar / hoja inferior             |
/// | titleMedium     | 16     | Título de tarjeta                            |
/// | bodyLarge       | 16     | Texto de lectura principal                   |
/// | bodyMedium      | 14     | Texto secundario, descripciones              |
/// | labelLarge      | 16     | Texto de botones                             |
/// | labelMedium     | 13     | Chips, etiquetas                             |
/// | bodySmall       | 12     | Metadatos (hora, distancia)                  |
abstract final class AppTypography {
  static TextTheme textTheme() {
    const p = AppColors.textPrimary;
    const s = AppColors.textSecondary;

    final base = const TextTheme(
      displayLarge: TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: p, height: 1.1),
      displayMedium: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: p, height: 1.1),
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: p, height: 1.15),
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: p, height: 1.2),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p, height: 1.25),
      headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: p, height: 1.25),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p, height: 1.3),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p, height: 1.35),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p, height: 1.35),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: p, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: s, height: 1.45),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: s, height: 1.4),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p, letterSpacing: 0.2),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s, letterSpacing: 0.4),
    );

    // En pruebas de interfaz no hay red: se usa la fuente por defecto.
    if (_useSystemFont) return base;
    return GoogleFonts.interTextTheme(base);
  }

  static bool _useSystemFont = false;

  /// Llamar en `setUp` de las pruebas de interfaz para no descargar fuentes.
  static void useSystemFontForTests() => _useSystemFont = true;
}
