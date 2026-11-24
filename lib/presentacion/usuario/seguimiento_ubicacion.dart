// CAPA: PRESENTACIÓN — transmisión de la ubicación en tiempo real (U-07)
// Vive con la sesión, no con una pantalla: la ubicación debe seguir viajando
// aunque el usuario cambie de vista o bloquee el teléfono. Escucha la alerta
// activa y, mientras la haya, manda al repositorio cada posición del sensor.
// Se detiene solo cuando la alerta se cierra.
// No importa material.dart, no pinta y no decide cuándo se dispara una alerta.

import 'dart:async';

import '../../datos/alerta_usuario_repository.dart';
import '../../datos/sensores.dart';
import '../../dominio/alerta.dart';
import '../../dominio/enums.dart';
import '../../dominio/punto_geo.dart';
import '../sesion/sesion_view_model.dart';

class SeguimientoUbicacion {
  SeguimientoUbicacion({
    required AlertaUsuarioRepository alertas,
    required Ubicacion ubicacion,
    required SesionViewModel sesion,
  })  : _alertas = alertas,
        _ubicacion = ubicacion,
        _sesion = sesion;

  final AlertaUsuarioRepository _alertas;
  final Ubicacion _ubicacion;
  final SesionViewModel _sesion;

  StreamSubscription<Alerta?>? _subAlerta;
  StreamSubscription<PuntoGeo>? _subUbicacion;

  /// Id de la alerta cuya ubicación se está transmitiendo, o `null`.
  String? alertaSeguida;

  bool get transmitiendo => alertaSeguida != null;

  /// Empieza a vigilar. Lo llama la raíz de composición al arrancar la app.
  /// Solo escucha mientras hay un usuario protegido en sesión: sin sesión no
  /// hay alerta que seguir ni a quién mandarle la ubicación.
  void iniciar() {
    _sesion.removeListener(_alCambiarLaSesion);
    _sesion.addListener(_alCambiarLaSesion);
    _alCambiarLaSesion();
  }

  void _alCambiarLaSesion() {
    final esProtegido = _sesion.usuario?.rol == RolUsuario.usuarioProtegido;
    if (!esProtegido) {
      _subAlerta?.cancel();
      _subAlerta = null;
      _detenerEnvio();
      return;
    }
    _subAlerta ??= _alertas.escucharAlertaActiva().listen(_alCambiarLaAlerta, onError: (_) => _detenerEnvio());
  }

  void _alCambiarLaAlerta(Alerta? alerta) {
    // La alerta se cerró (o no hay ninguna): se deja de compartir.
    if (alerta == null || !alerta.estado.activa) {
      _detenerEnvio();
      return;
    }
    if (alertaSeguida == alerta.id) return; // ya se está transmitiendo
    _detenerEnvio();
    alertaSeguida = alerta.id;
    _subUbicacion = _ubicacion.seguir().listen((p) => _alertas.enviarUbicacion(alerta.id, p));
  }

  void _detenerEnvio() {
    _subUbicacion?.cancel();
    _subUbicacion = null;
    alertaSeguida = null;
  }

  void dispose() {
    _sesion.removeListener(_alCambiarLaSesion);
    _subAlerta?.cancel();
    _detenerEnvio();
  }
}
