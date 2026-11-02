// CAPA: DATOS — el contrato del almacén local de sesión
// U-02 Inicio de sesión: la sesión sobrevive a cerrar y volver a abrir la app.
// Habla de "quién quedó dentro" y "quién ya vio los permisos", no de archivos
// ni de claves: la implementación decide si es memoria o el disco del teléfono.
// No hace: no valida credenciales (eso es AuthRepository).

abstract interface class SesionGuardada {
  /// Id del último usuario que inició sesión y no la cerró, o `null`.
  Future<String?> leerUsuarioId();

  Future<void> guardarUsuarioId(String usuarioId);

  Future<void> borrarUsuarioId();

  /// Usuarios que ya vieron la pantalla de permisos (U-02).
  Future<Set<String>> leerPermisosVistos();

  Future<void> marcarPermisosVistos(String usuarioId);
}
