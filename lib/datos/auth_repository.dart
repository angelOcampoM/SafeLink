// CAPA: DATOS — el contrato de sesión
// U-01 Registro · U-02 Inicio de sesión · G-01 Login del guardia · U-05 Agitación
// Habla en lenguaje del dominio: iniciar sesión, registrar, cerrar sesión.
// No dice "HTTP", ni "token", ni "lista en memoria".
// Implementaciones: MemoriaAuthRepository (hoy) y NubeAuthRepository (mañana).

import '../dominio/usuario.dart';

abstract interface class AuthRepository {
  /// Usuario con sesión abierta, o `null`.
  Usuario? get usuarioActual;

  /// Lanza `CredencialesInvalidasError`.
  Future<Usuario> iniciarSesion({required String correo, required String contrasena});

  /// Solo crea usuarios protegidos. Lanza `CorreoRegistradoError`.
  Future<Usuario> registrar({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
  });

  Future<void> cerrarSesion();

  /// Vuelve a leer al usuario en sesión (bloqueo, falsas alarmas…).
  Future<Usuario> refrescarSesion();

  /// U-02: reabre la sesión que quedó guardada en el dispositivo.
  /// Devuelve `null` si ese usuario ya no existe o fue dado de baja.
  /// Mañana recibirá un token en vez del id.
  Future<Usuario?> restaurarSesion(String usuarioId);

  Future<Usuario> actualizarAgitacion({required bool activa});
}
