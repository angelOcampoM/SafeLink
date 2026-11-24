// CAPA: DATOS — implementación real (almacén local de sesión)
// U-02. Guarda en el almacenamiento del teléfono con shared_preferences, así
// la sesión sigue abierta después de cerrar la app.
// Mañana, con API real, aquí se guardará el token en vez del id.
// No hace: no conoce entidades del dominio, solo cadenas.

import 'package:shared_preferences/shared_preferences.dart';

import 'sesion_guardada.dart';

class DispositivoSesionGuardada implements SesionGuardada {
  static const _claveUsuario = 'sesion.usuarioId';
  static const _clavePermisos = 'sesion.permisosVistos';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> leerUsuarioId() async => (await _prefs).getString(_claveUsuario);

  @override
  Future<void> guardarUsuarioId(String usuarioId) async => (await _prefs).setString(_claveUsuario, usuarioId);

  @override
  Future<void> borrarUsuarioId() async => (await _prefs).remove(_claveUsuario);

  @override
  Future<Set<String>> leerPermisosVistos() async => ((await _prefs).getStringList(_clavePermisos) ?? const []).toSet();

  @override
  Future<void> marcarPermisosVistos(String usuarioId) async {
    final prefs = await _prefs;
    final vistos = (prefs.getStringList(_clavePermisos) ?? const <String>[]).toSet()..add(usuarioId);
    await prefs.setStringList(_clavePermisos, vistos.toList());
  }
}
