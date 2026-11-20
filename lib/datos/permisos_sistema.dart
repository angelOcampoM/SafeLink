// CAPA: DATOS — los permisos que tiene que conceder el sistema
// U-01 · U-02 Permisos. La pantalla explica PARA QUÉ se usan; este contrato es el que
// realmente se los pide al teléfono.
// No hace: no decide cuándo pedirlos (eso es la sesión) ni pinta nada.

/// Qué quedó concedido después de preguntar.
typedef EstadoPermisos = ({bool camara, bool ubicacion, bool notificaciones});

abstract interface class PermisosSistema {
  /// Pide los tres accesos que necesita una alerta y devuelve qué quedó concedido.
  ///
  /// Nunca lanza: si la persona dice no, la app sigue funcionando con lo que haya (la alerta
  /// viajará sin foto, o pendiente de ubicación). Negarse no puede dejar a nadie sin botón
  /// de pánico.
  Future<EstadoPermisos> pedirLosDeLaAlerta();

  /// Lo ya concedido, sin preguntar nada. Para mostrar el estado en Configuración.
  Future<EstadoPermisos> estado();
}

/// En pruebas y en la demo todo está concedido: no hay sistema al que preguntar.
class PermisosConcedidos implements PermisosSistema {
  const PermisosConcedidos();

  static const _todo = (camara: true, ubicacion: true, notificaciones: true);

  @override
  Future<EstadoPermisos> pedirLosDeLaAlerta() async => _todo;

  @override
  Future<EstadoPermisos> estado() async => _todo;
}
