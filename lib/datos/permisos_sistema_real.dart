// CAPA: DATOS — los permisos del sistema de verdad (permission_handler)
// U-01 · U-02. Implementa el mismo contrato que `PermisosConcedidos`, así que las pruebas y
// la demo no cambian: solo cambia la línea de main.dart.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:permission_handler/permission_handler.dart';

import 'permisos_sistema.dart';

class PermisosSistemaReal implements PermisosSistema {
  const PermisosSistemaReal();

  /// Los tres que pide la pantalla de permisos. La ubicación se pide "mientras se usa la
  /// app": Android exige pedir la de segundo plano en un paso aparte y después de esta, así
  /// que eso se hace cuando haga falta y no en el alta.
  static const _solicitados = [
    Permission.camera,
    Permission.locationWhenInUse,
    Permission.notification,
  ];

  @override
  Future<EstadoPermisos> pedirLosDeLaAlerta() async {
    try {
      final respuesta = await _solicitados.request();
      return _leer(respuesta);
    } on Object catch (e) {
      // Negarse (o que el plugin falle) no puede dejar a nadie sin botón de pánico.
      debugPrint('Permisos: no se pudieron pedir ($e)');
      return const (camara: false, ubicacion: false, notificaciones: false);
    }
  }

  @override
  Future<EstadoPermisos> estado() async {
    try {
      final actual = <Permission, PermissionStatus>{};
      for (final permiso in _solicitados) {
        actual[permiso] = await permiso.status;
      }
      return _leer(actual);
    } on Object catch (e) {
      debugPrint('Permisos: no se pudo leer el estado ($e)');
      return const (camara: false, ubicacion: false, notificaciones: false);
    }
  }

  /// `limited` y `provisional` cuentan como concedido: la app puede usar el acceso.
  static bool _concedido(PermissionStatus? estado) =>
      estado != null && (estado.isGranted || estado.isLimited || estado.isProvisional);

  static EstadoPermisos _leer(Map<Permission, PermissionStatus> respuesta) => (
        camara: _concedido(respuesta[Permission.camera]),
        ubicacion: _concedido(respuesta[Permission.locationWhenInUse]),
        notificaciones: _concedido(respuesta[Permission.notification]),
      );
}
