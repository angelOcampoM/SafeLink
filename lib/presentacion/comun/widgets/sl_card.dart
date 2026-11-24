// CAPA: PRESENTACIÓN — sistema de diseño (componente compartido)
// Contenedor base con acento opcional. No hace: no conoce entidades.

import 'package:flutter/material.dart';

import '../tema/theme.dart';

/// Tarjeta base. Usa [accent] para resaltar (borde + franja izquierda),
/// por ejemplo ámbar en alertas urgentes o rojo en la alerta activa.
class SlCard extends StatelessWidget {
  const SlCard({
    super.key,
    required this.child,
    this.onTap,
    this.accent,
    this.padding = AppSpacing.card,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final borderColor = accent == null ? AppColors.border : AppColors.tintBorder(accent!);

    return Material(
      color: color ?? (accent == null ? AppColors.surface : Color.alphaBlend(accent!.withValues(alpha: 0.06), AppColors.surface)),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: borderColor, width: accent == null ? 1 : 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (accent != null)
              Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: accent)),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}
