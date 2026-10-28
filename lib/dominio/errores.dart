// CAPA: DOMINIO — errores que el negocio sabe nombrar
// Reflejan los `error.code` de la API (sección 7): { "error": { "code", "message" } }.
// El ViewModel los atrapa y muestra `mensaje`.
// No hace: no sabe de HTTP; el `nube_` traduce el JSON de error a estas clases.

class ErrorDominio implements Exception {
  const ErrorDominio(this.codigo, this.mensaje);
  final String codigo;

  /// Mensaje en español listo para mostrar.
  final String mensaje;

  @override
  String toString() => '$codigo: $mensaje';
}

class CredencialesInvalidasError extends ErrorDominio {
  const CredencialesInvalidasError() : super('INVALID_CREDENTIALS', 'Correo o contraseña incorrectos');
}

class CorreoRegistradoError extends ErrorDominio {
  const CorreoRegistradoError() : super('EMAIL_TAKEN', 'Ese correo ya está registrado');
}

class UsuarioBloqueadoError extends ErrorDominio {
  const UsuarioBloqueadoError() : super('USER_BLOCKED', 'Tu cuenta está bloqueada temporalmente');
}

class AlertaTomadaError extends ErrorDominio {
  const AlertaTomadaError() : super('ALERT_TAKEN', 'Otro guardia ya aceptó esta alerta');
}

class FueraDeGeocercaError extends ErrorDominio {
  const FueraDeGeocercaError(this.metrosRestantes) : super('OUTSIDE_GEOFENCE', 'Aún no estás en el punto de la alerta');
  final double metrosRestantes;
}

class EstadoInvalidoError extends ErrorDominio {
  const EstadoInvalidoError(String mensaje) : super('INVALID_STATE', mensaje);
}

class NoEncontradoError extends ErrorDominio {
  const NoEncontradoError([String mensaje = 'No encontramos lo que buscabas']) : super('NOT_FOUND', mensaje);
}

class SinSesionError extends ErrorDominio {
  const SinSesionError() : super('UNAUTHORIZED', 'Tu sesión terminó. Vuelve a iniciar sesión.');
}

/// La red o el servidor fallaron (latencia, caída, `tasaFallo` del servicio falso).
class ServicioNoDisponibleError extends ErrorDominio {
  const ServicioNoDisponibleError() : super('SERVICE_UNAVAILABLE', 'No pudimos conectar con el servidor. Intenta de nuevo.');
}
