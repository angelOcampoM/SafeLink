/// Errores de dominio que la UI sabe mostrar. Reflejan los `error.code`
/// de la API (sección 7): `{ "error": { "code": ..., "message": ... } }`.
class AppException implements Exception {
  const AppException(this.code, this.message);
  final String code;

  /// Mensaje en español listo para mostrar.
  final String message;

  @override
  String toString() => '$code: $message';
}

class InvalidCredentialsException extends AppException {
  const InvalidCredentialsException() : super('INVALID_CREDENTIALS', 'Correo o contraseña incorrectos');
}

class EmailTakenException extends AppException {
  const EmailTakenException() : super('EMAIL_TAKEN', 'Ese correo ya está registrado');
}

class UserBlockedException extends AppException {
  const UserBlockedException() : super('USER_BLOCKED', 'Tu cuenta está bloqueada temporalmente');
}

class AlertTakenException extends AppException {
  const AlertTakenException() : super('ALERT_TAKEN', 'Otro guardia ya aceptó esta alerta');
}

class OutsideGeofenceException extends AppException {
  const OutsideGeofenceException(this.remainingMeters)
      : super('OUTSIDE_GEOFENCE', 'Aún no estás en el punto de la alerta');
  final double remainingMeters;
}

class InvalidStateException extends AppException {
  const InvalidStateException(String message) : super('INVALID_STATE', message);
}
