// CAPA: DOMINIO — regla de geocerca y cobertura
// G-04 Distancia · G-06 Ruta · G-07 Registro de llegada · A-03 Radio de cobertura
// Distancia Haversine, dentro de geocerca/cobertura, rumbo y validación del radio.
// No hace: no lee el GPS; recibe los puntos ya obtenidos.

import 'dart:math' as math;

import 'punto_geo.dart';

abstract final class ReglaGeocerca {
  static const _radioTierraMetros = 6371000.0;

  /// Distancia en metros (fórmula de Haversine).
  static double distanciaMetros(PuntoGeo a, PuntoGeo b) {
    final dLat = _rad(b.lat - a.lat);
    final dLng = _rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * _radioTierraMetros * math.asin(math.sqrt(h));
  }

  /// G-07: el botón "Llegué" se habilita si la distancia ≤ radio.
  static bool dentroDeGeocerca(PuntoGeo guardia, PuntoGeo alerta, int radioMetros) =>
      distanciaMetros(guardia, alerta) <= radioMetros;

  /// Metros que faltan para entrar a la geocerca (0 si ya está dentro).
  static double metrosRestantes(PuntoGeo guardia, PuntoGeo alerta, int radioMetros) =>
      math.max(0, distanciaMetros(guardia, alerta) - radioMetros);

  /// G-07: devuelve el motivo del rechazo, o `null` si puede registrar llegada.
  static String? validarLlegada(PuntoGeo? guardia, PuntoGeo? alerta, int radioMetros) {
    if (guardia == null || alerta == null) return 'Aún no tenemos tu ubicación';
    if (!dentroDeGeocerca(guardia, alerta, radioMetros)) return 'Aún no estás en el punto de la alerta';
    return null;
  }

  /// ¿La ubicación de la alerta cae en el radio de cobertura del guardia?
  static bool dentroDeCobertura(PuntoGeo centro, int radioMetros, PuntoGeo punto) =>
      distanciaMetros(centro, punto) <= radioMetros;

  /// A-03: devuelve el motivo del rechazo, o `null` si el radio es válido.
  static String? validarRadio(int radioMetros, {required int minimo, required int maximo}) {
    if (radioMetros < minimo) return 'El radio mínimo es de $minimo m';
    if (radioMetros > maximo) return 'El radio máximo es de $maximo m';
    return null;
  }

  /// A-06: devuelve el motivo del rechazo, o `null` si la zona es válida.
  static String? validarZona(String? zona) {
    if (zona == null || zona.trim().isEmpty) return 'Escribe la zona de cobertura';
    return null;
  }

  /// Punto a una fracción (0–1) del camino entre [desde] y [hasta].
  static PuntoGeo avanzar(PuntoGeo desde, PuntoGeo hasta, double fraccion) =>
      PuntoGeo(desde.lat + (hasta.lat - desde.lat) * fraccion, desde.lng + (hasta.lng - desde.lng) * fraccion);

  /// Normaliza cualquier ángulo a 0–359.
  static int normalizarRumbo(num grados) => ((grados % 360) + 360).round() % 360;

  /// Punto cardinal en español para mostrar junto al rumbo.
  static String puntoCardinal(int rumbo) {
    const nombres = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return nombres[((normalizarRumbo(rumbo) + 22.5) ~/ 45) % 8];
  }

  static double _rad(double grados) => grados * math.pi / 180;
}
