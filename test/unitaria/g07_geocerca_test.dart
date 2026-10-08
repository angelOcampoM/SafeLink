// G-07 Registro de llegada — geocerca y distancia.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/core/utils/geo_utils.dart';
import 'package:safelink/data/models/geo_point.dart';

void main() {
  const alertPoint = GeoPoint(18.8400, -99.1800);

  group('GeoUtils.distanceMeters', () {
    test('mismo punto = 0 m', () {
      expect(GeoUtils.distanceMeters(alertPoint, alertPoint), 0);
    });

    test('0.001° de latitud ≈ 111 m', () {
      final d = GeoUtils.distanceMeters(alertPoint, const GeoPoint(18.8410, -99.1800));
      expect(d, closeTo(111, 1));
    });
  });

  group('G-07 isInsideGeofence', () {
    test('a ~33 m está dentro de un radio de 50 m', () {
      expect(GeoUtils.isInsideGeofence(const GeoPoint(18.8403, -99.1800), alertPoint, 50), isTrue);
    });

    test('a ~111 m está fuera de un radio de 50 m', () {
      expect(GeoUtils.isInsideGeofence(const GeoPoint(18.8410, -99.1800), alertPoint, 50), isFalse);
    });
  });

  group('Rumbo', () {
    test('normaliza a 0–359', () {
      expect(GeoUtils.normalizeHeading(360), 0);
      expect(GeoUtils.normalizeHeading(-90), 270);
      expect(GeoUtils.normalizeHeading(725), 5);
    });

    test('punto cardinal', () {
      expect(GeoUtils.cardinal(0), 'N');
      expect(GeoUtils.cardinal(40), 'NE');
      expect(GeoUtils.cardinal(185), 'S');
      expect(GeoUtils.cardinal(300), 'NO');
    });
  });
}
