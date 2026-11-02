// CAPA: DATOS — implementación de hoy (sesión)
// U-01 Registro · U-02 Inicio de sesión · G-01 · U-05 Agitación
// Lee y escribe en MemoriaBaseDatos. Cumple el contrato; nadie arriba sabe que es un mapa.

import '../dominio/dominio.dart';
import 'auth_repository.dart';
import 'memoria_base_datos.dart';

class MemoriaAuthRepository implements AuthRepository {
  MemoriaAuthRepository(this._db);
  final MemoriaBaseDatos _db;

  @override
  Usuario? get usuarioActual => _db.usuarioActualId == null ? null : _db.yo;

  Usuario? _porCorreo(String correo) =>
      _db.usuarios.values.where((u) => u.correo.toLowerCase() == correo.trim().toLowerCase()).firstOrNull;

  @override
  Future<Usuario> iniciarSesion({required String correo, required String contrasena}) async {
    await _db.esperar();
    final u = _porCorreo(correo);
    if (u == null || _db.contrasenas[u.id] != contrasena || !u.activo) {
      throw const CredencialesInvalidasError();
    }
    _db.usuarioActualId = u.id;
    return u;
  }

  @override
  Future<Usuario> registrar({
    required String nombre,
    required String correo,
    required String telefono,
    required String contrasena,
  }) async {
    await _db.esperar();
    if (_porCorreo(correo) != null) throw const CorreoRegistradoError();
    final u = Usuario(
      id: _db.nuevoId('usr'),
      nombre: nombre.trim(),
      correo: correo.trim(),
      telefono: telefono.trim(),
      rol: RolUsuario.usuarioProtegido,
      creadoEn: _db.reloj(),
    );
    _db.usuarios[u.id] = u;
    _db.contrasenas[u.id] = contrasena;
    _db.usuarioActualId = u.id;
    return u;
  }

  @override
  Future<void> cerrarSesion() async {
    _db.usuarioActualId = null;
  }

  @override
  Future<Usuario> refrescarSesion() async {
    await _db.esperar();
    return _db.yo;
  }

  @override
  Future<Usuario?> restaurarSesion(String usuarioId) async {
    await _db.esperar();
    final u = _db.usuarios[usuarioId];
    if (u == null || !u.activo) return null;
    _db.usuarioActualId = u.id;
    return u;
  }

  @override
  Future<Usuario> actualizarAgitacion({required bool activa}) async {
    await _db.esperar();
    final u = _db.yo.copyWith(agitacionActiva: activa);
    _db.usuarios[u.id] = u;
    return u;
  }
}
