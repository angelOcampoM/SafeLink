// CAPA: DATOS — los sensores del teléfono de verdad
// U-06 Captura automática de evidencia · U-07 Ubicación en tiempo real.
// Implementan los mismos contratos que `sensores_simulados.dart`, así que las pruebas y la
// demo siguen usando los simulados y no cambia nada más que la línea de main.dart.
//
// Regla común a los tres: NUNCA lanzan. Si el sensor no responde, no hay permiso o el
// teléfono no tiene la pieza, devuelven `null` y la alerta viaja igual (marcada como
// evidencia incompleta o pendiente de ubicación). Una alerta de pánico no se pierde porque
// la cámara tardó.

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

import '../dominio/punto_geo.dart';
import '../dominio/regla_geocerca.dart';
import 'sensores.dart';

/// Precisión y antigüedad máxima aceptables para la posición de una alerta.
const _ajustesUbicacion = LocationSettings(
  accuracy: LocationAccuracy.high,
  distanceFilter: 10, // metros: no manda una posición nueva por estar quieto
);

/// Cuánto se espera por una lectura antes de darla por perdida. Es corto a propósito:
/// más vale una alerta sin ubicación que una alerta que no sale.
const _esperaMaxima = Duration(seconds: 8);

/// U-06 · U-07 · GPS real.
class UbicacionReal implements Ubicacion {
  @override
  Future<PuntoGeo?> posicionActual() async {
    try {
      if (!await _servicioYPermisoListos()) return null;
      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: _ajustesUbicacion,
      ).timeout(_esperaMaxima);
      return PuntoGeo(posicion.latitude, posicion.longitude);
    } on Object catch (e) {
      debugPrint('Ubicación: no se pudo leer la posición ($e)');
      return null;
    }
  }

  /// U-07: posiciones sucesivas mientras la alerta está activa. Un error del GPS no termina
  /// el flujo: la pantalla sigue esperando la siguiente lectura.
  @override
  Stream<PuntoGeo> seguir() async* {
    if (!await _servicioYPermisoListos()) return;
    yield* Geolocator.getPositionStream(locationSettings: _ajustesUbicacion)
        .map((p) => PuntoGeo(p.latitude, p.longitude))
        .handleError((Object e) => debugPrint('Ubicación: se interrumpió el seguimiento ($e)'));
  }
}

/// U-06 · Rumbo. Sale del propio GPS (`Position.heading`): es el curso del dispositivo, que es
/// lo que importa para saber hacia dónde mira la foto, y evita depender de un paquete de
/// brújula aparte. Con el teléfono quieto el GPS no da rumbo fiable y devuelve `null`.
class BrujulaReal implements Brujula {
  @override
  Future<int?> rumbo() async {
    try {
      if (!await _servicioYPermisoListos()) return null;
      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: _ajustesUbicacion,
      ).timeout(_esperaMaxima);
      final grados = posicion.heading;
      // heading es negativo (o 0 sin movimiento) cuando no hay un rumbo válido.
      if (grados.isNaN || grados < 0) return null;
      return ReglaGeocerca.normalizarRumbo(grados);
    } on Object catch (e) {
      debugPrint('Brújula: no se pudo leer el rumbo ($e)');
      return null;
    }
  }
}

/// U-06 · Una sola foto automática, sin vista previa ni botón: el usuario está en apuros y no
/// va a encuadrar nada. Se abre la cámara, se dispara y se cierra.
class CamaraReal implements Camara {
  CamaraReal({this.resolucion = ResolutionPreset.medium});

  /// Media a propósito: la foto tiene que salir y subir rápido, no quedar bonita.
  final ResolutionPreset resolucion;

  @override
  Future<String?> tomarFoto() async {
    CameraController? control;
    try {
      final camaras = await availableCameras();
      if (camaras.isEmpty) return null;
      // Trasera si existe; si no, la primera que haya.
      final elegida = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camaras.first,
      );
      control = CameraController(
        elegida,
        resolucion,
        enableAudio: false, // es una foto: el micrófono no se toca
      );
      await control.initialize().timeout(_esperaMaxima);
      final archivo = await control.takePicture().timeout(_esperaMaxima);
      return archivo.path;
    } on Object catch (e) {
      debugPrint('Cámara: no se pudo tomar la foto ($e)');
      return null;
    } finally {
      // Siempre: una cámara abierta deja el LED encendido y bloquea a las demás apps.
      try {
        await control?.dispose();
      } on Object {
        // Ya estaba cerrada.
      }
    }
  }
}

/// ¿El GPS está encendido y con permiso? Se comprueba antes de cada lectura porque la persona
/// puede apagarlo o quitar el permiso con la app abierta.
Future<bool> _servicioYPermisoListos() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
  return permiso == LocationPermission.always || permiso == LocationPermission.whileInUse;
}
