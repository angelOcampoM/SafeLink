// CAPA: DATOS — sensores simulados
// U-06 · U-07. Devuelven datos fijos y verificables, que es lo que pide el
// plan de pruebas ("con cámara, GPS y brújula simulados"). Cada uno puede
// fallar a propósito para probar los caminos de error.
// Al conectar los plugins reales se cambian por Camara/Ubicacion/Brujula de verdad.

import 'dart:async';

import '../dominio/punto_geo.dart';
import 'sensores.dart';

class CamaraSimulada implements Camara {
  CamaraSimulada({this.ruta = 'demo.jpg', this.falla = false});

  final String ruta;

  /// `true` reproduce "la foto no se generó" (U-06).
  final bool falla;

  int tomas = 0;

  @override
  Future<String?> tomarFoto() async {
    tomas++;
    return falla ? null : ruta;
  }
}

class UbicacionSimulada implements Ubicacion {
  UbicacionSimulada({required PuntoGeo inicial, this.sinSenal = false, this.paso = 0.0005})
      : _actual = inicial;

  PuntoGeo _actual;

  /// `true` reproduce "no hay coordenadas válidas" (U-06).
  final bool sinSenal;

  /// Cuánto se desplaza en cada emisión de [seguir].
  final double paso;

  final _control = StreamController<PuntoGeo>.broadcast();
  bool get siguiendo => _control.hasListener;

  @override
  Future<PuntoGeo?> posicionActual() async => sinSenal ? null : _actual;

  @override
  Stream<PuntoGeo> seguir() => _control.stream;

  /// Solo en demo y pruebas: el usuario se movió un paso hacia el norte.
  void mover() {
    _actual = PuntoGeo(_actual.lat + paso, _actual.lng);
    _control.add(_actual);
  }

  void dispose() => _control.close();
}

class BrujulaSimulada implements Brujula {
  BrujulaSimulada({this.grados = 35, this.falla = false});

  final int grados;

  /// `true` reproduce "rumbo no disponible" (U-06).
  final bool falla;

  @override
  Future<int?> rumbo() async => falla ? null : grados;
}
