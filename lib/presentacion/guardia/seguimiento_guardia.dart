// CAPA: PRESENTACIÓN — ubicación real del guardia (CR-F02 · G-03 · G-06 · G-07)
// Vive con la sesión, no con una pantalla. Mientras haya un guardia en sesión
// lee el GPS y manda su posición a la API, espaciada por [intervalo] para no
// exceder el límite (429). Con eso el servidor calcula distancia, prioridad,
// tiempo estimado y geocerca con la posición real, y la navegación la muestra.
// Solo se arma con la API real: en la demo la mueve "Simular acercamiento".
// No importa material.dart, no pinta y no decide si se permite la llegada.

import 'dart:async';

import '../../datos/alerta_guardia_repository.dart';
import '../../datos/sensores.dart';
import '../../dominio/enums.dart';
import '../../dominio/punto_geo.dart';
import '../comun/envio_espaciado.dart';
import '../sesion/sesion_view_model.dart';

class SeguimientoGuardia {
  SeguimientoGuardia({
    required AlertaGuardiaRepository alertas,
    required Ubicacion ubicacion,
    required SesionViewModel sesion,
    this.intervalo = Duration.zero,
  })  : _alertas = alertas,
        _ubicacion = ubicacion,
        _sesion = sesion;

  final AlertaGuardiaRepository _alertas;
  final Ubicacion _ubicacion;
  final SesionViewModel _sesion;

  /// Mínimo entre dos envíos (`Configuracion.segundosActualizacionUbicacion`).
  final Duration intervalo;

  final _posiciones = StreamController<PuntoGeo>.broadcast();
  StreamSubscription<PuntoGeo>? _subUbicacion;
  EnvioEspaciado<PuntoGeo>? _envio;

  /// Última posición leída del GPS en esta sesión, o `null` si aún no hay señal.
  PuntoGeo? ultimaPosicion;

  bool get siguiendo => _envio != null;

  /// Cada posición nueva del GPS (la navegación la escucha para la geocerca).
  Stream<PuntoGeo> get posiciones => _posiciones.stream;

  /// Empieza a vigilar la sesión. Lo llama la raíz de composición al arrancar.
  void iniciar() {
    _sesion.removeListener(_alCambiarLaSesion);
    _sesion.addListener(_alCambiarLaSesion);
    _alCambiarLaSesion();
  }

  void _alCambiarLaSesion() {
    final esGuardia = _sesion.usuario?.rol == RolUsuario.guardia;
    if (!esGuardia) {
      _detener();
      return;
    }
    if (_envio == null) {
      final envio = _envio = EnvioEspaciado(intervalo: intervalo, enviar: _alertas.actualizarMiUbicacion);
      // El GPS real solo emite al moverse: la lectura inicial cubre al guardia quieto.
      unawaited(
        _ubicacion.posicionActual().then((p) {
          if (p != null && identical(_envio, envio)) _recibir(p);
        }),
      );
    }
    // Si el flujo terminó (permiso negado o GPS apagado), se vuelve a intentar en el
    // siguiente cambio de sesión en lugar de quedar atorado.
    _subUbicacion ??= _ubicacion.seguir().listen(
      _recibir,
      onError: (Object _) {}, // un error del sensor no detiene el seguimiento
      onDone: () => _subUbicacion = null,
    );
  }

  void _recibir(PuntoGeo p) {
    ultimaPosicion = p;
    _posiciones.add(p);
    _envio?.agregar(p);
  }

  void _detener() {
    _subUbicacion?.cancel();
    _subUbicacion = null;
    _envio?.cerrar();
    _envio = null;
    ultimaPosicion = null;
  }

  void dispose() {
    _sesion.removeListener(_alCambiarLaSesion);
    _detener();
    _posiciones.close();
  }
}
