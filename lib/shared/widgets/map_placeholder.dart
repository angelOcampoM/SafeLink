import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';

/// Marcador para [MapPlaceholder]. `offset` va de (-1,-1) a (1,1) respecto
/// al centro del mapa.
class MapMarker {
  const MapMarker({required this.offset, required this.color, required this.icon, this.label, this.heading});
  final Offset offset;
  final Color color;
  final IconData icon;
  final String? label;

  /// Si se indica, dibuja el cono de rumbo de la cámara (G-04).
  final int? heading;
}

/// Mapa simulado mientras no se integra Google Maps. Tiene el MISMO lugar y
/// tamaño que tendrá el `GoogleMap`, para que el diseño no cambie al
/// sustituirlo. Dibuja cuadrícula de calles, marcadores, ruta y radio.
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({
    super.key,
    this.markers = const [],
    this.showRoute = false,
    this.radiusFraction,
    this.height = 240,
  });

  final List<MapMarker> markers;

  /// Línea punteada entre el primer y el último marcador.
  final bool showRoute;

  /// Círculo de cobertura/geocerca, como fracción del lado corto (0–1).
  final double? radiusFraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.brMd,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, c) {
            Offset toPx(Offset o) => Offset((o.dx + 1) / 2 * c.maxWidth, (o.dy + 1) / 2 * c.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MapPainter(
                      markers: markers,
                      showRoute: showRoute,
                      radiusFraction: radiusFraction,
                      toPx: toPx,
                    ),
                  ),
                ),
                for (final m in markers)
                  Positioned(
                    left: toPx(m.offset).dx - 18,
                    top: toPx(m.offset).dy - 18,
                    child: _Pin(marker: m),
                  ),
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: Text('Mapa simulado', style: context.text.labelSmall?.copyWith(color: AppColors.textMuted)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.marker});
  final MapMarker marker;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: marker.color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.onAccent, width: 2),
        boxShadow: [BoxShadow(color: marker.color.withValues(alpha: 0.6), blurRadius: 12)],
      ),
      child: Icon(marker.icon, size: AppSizes.iconSm, color: AppColors.onAccent),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.markers, required this.showRoute, required this.radiusFraction, required this.toPx});

  final List<MapMarker> markers;
  final bool showRoute;
  final double? radiusFraction;
  final Offset Function(Offset) toPx;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.mapBase);

    // Calles
    final street = Paint()
      ..color = AppColors.border.withValues(alpha: 0.6)
      ..strokeWidth = 6;
    final minor = Paint()
      ..color = AppColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 2;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      final y = size.height * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x - 20, size.height), i.isEven ? street : minor);
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 10), i.isOdd ? street : minor);
    }

    // Radio de cobertura / geocerca alrededor del último marcador
    if (radiusFraction != null && markers.isNotEmpty) {
      final c = toPx(markers.last.offset);
      final r = size.shortestSide * radiusFraction!;
      canvas.drawCircle(c, r, Paint()..color = AppColors.info.withValues(alpha: 0.12));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = AppColors.info.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Conos de rumbo
    for (final m in markers.where((m) => m.heading != null)) {
      final c = toPx(m.offset);
      final a = (m.heading! - 90) * math.pi / 180; // 0° = norte (arriba)
      const spread = 0.45;
      final len = size.shortestSide * 0.35;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + len * math.cos(a - spread), c.dy + len * math.sin(a - spread))
        ..arcToPoint(
          Offset(c.dx + len * math.cos(a + spread), c.dy + len * math.sin(a + spread)),
          radius: Radius.circular(len),
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [m.color.withValues(alpha: 0.55), m.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: len)),
      );
    }

    // Ruta punteada
    if (showRoute && markers.length >= 2) {
      final a = toPx(markers.first.offset);
      final b = toPx(markers.last.offset);
      final paint = Paint()
        ..color = AppColors.info
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      const steps = 24;
      for (var i = 0; i < steps; i += 2) {
        canvas.drawLine(Offset.lerp(a, b, i / steps)!, Offset.lerp(a, b, (i + 1) / steps)!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.markers != markers || old.showRoute != showRoute || old.radiusFraction != radiusFraction;
}
