// G-07 Registro de llegada — geocerca, distancia y rumbo · A-03 radio de cobertura.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/punto_geo.dart';
import 'package:safelink/dominio/regla_geocerca.dart';

void main() {
  const puntoAlerta = PuntoGeo(18.8400, -99.1800);

  group('distanciaMetros', () {
    test('mismo punto = 0 m', () {
      expect(ReglaGeocerca.distanciaMetros(puntoAlerta, puntoAlerta), 0);
    });

    test('0.001° de latitud ≈ 111 m', () {
      final d = ReglaGeocerca.distanciaMetros(puntoAlerta, const PuntoGeo(18.8410, -99.1800));
      expect(d, closeTo(111, 1));
    });
  });

  group('G-07 dentroDeGeocerca / validarLlegada', () {
    test('a ~33 m está dentro de un radio de 50 m', () {
      const cerca = PuntoGeo(18.8403, -99.1800);
      expect(ReglaGeocerca.dentroDeGeocerca(cerca, puntoAlerta, 50), isTrue);
      expect(ReglaGeocerca.validarLlegada(cerca, puntoAlerta, 50), isNull);
    });

    test('a ~111 m está fuera de un radio de 50 m y faltan ~61 m', () {
      const lejos = PuntoGeo(18.8410, -99.1800);
      expect(ReglaGeocerca.dentroDeGeocerca(lejos, puntoAlerta, 50), isFalse);
      expect(ReglaGeocerca.validarLlegada(lejos, puntoAlerta, 50), isNotNull);
      expect(ReglaGeocerca.metrosRestantes(lejos, puntoAlerta, 50), closeTo(61, 1));
    });

    test('sin ubicación no se puede registrar llegada', () {
      expect(ReglaGeocerca.validarLlegada(null, puntoAlerta, 50), isNotNull);
    });
  });

  test('A-03 validarRadio', () {
    expect(ReglaGeocerca.validarRadio(3000, minimo: 500, maximo: 10000), isNull);
    expect(ReglaGeocerca.validarRadio(100, minimo: 500, maximo: 10000), isNotNull);
    expect(ReglaGeocerca.validarRadio(20000, minimo: 500, maximo: 10000), isNotNull);
  });

  group('Rumbo', () {
    test('normaliza a 0–359', () {
      expect(ReglaGeocerca.normalizarRumbo(360), 0);
      expect(ReglaGeocerca.normalizarRumbo(-90), 270);
      expect(ReglaGeocerca.normalizarRumbo(725), 5);
    });

    test('punto cardinal', () {
      expect(ReglaGeocerca.puntoCardinal(0), 'N');
      expect(ReglaGeocerca.puntoCardinal(40), 'NE');
      expect(ReglaGeocerca.puntoCardinal(185), 'S');
      expect(ReglaGeocerca.puntoCardinal(300), 'NO');
    });
  });
}
