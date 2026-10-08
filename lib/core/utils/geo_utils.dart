import 'dart:math' as math;

import '../../data/models/geo_point.dart';

abstract final class GeoUtils {
  static const _earthRadiusMeters = 6371000.0;

  /// Distancia en metros (fórmula de Haversine).
  static double distanceMeters(GeoPoint a, GeoPoint b) {
    final dLat = _rad(b.lat - a.lat);
    final dLng = _rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * _earthRadiusMeters * math.asin(math.sqrt(h));
  }

  /// G-07: el botón "Llegué" se habilita si la distancia ≤ radio.
  static bool isInsideGeofence(GeoPoint guard, GeoPoint alert, int radiusMeters) =>
      distanceMeters(guard, alert) <= radiusMeters;

  /// ¿La ubicación de la alerta cae en el radio de cobertura del guardia?
  static bool isInsideCoverage(GeoPoint center, int radiusMeters, GeoPoint point) =>
      distanceMeters(center, point) <= radiusMeters;

  /// Normaliza cualquier ángulo a 0–359.
  static int normalizeHeading(num degrees) => ((degrees % 360) + 360).round() % 360;

  /// Punto cardinal en español para mostrar junto al rumbo.
  static String cardinal(int heading) {
    const names = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return names[((normalizeHeading(heading) + 22.5) ~/ 45) % 8];
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
