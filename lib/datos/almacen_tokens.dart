// CAPA: DATOS — almacén de los tokens de sesión de la API real
// El access token (15 min) vive solo en memoria. El refresh token se conserva
// para poder reabrir la sesión al volver a abrir la app (U-02).
// OJO: DispositivoAlmacenTokens usa shared_preferences (texto plano en el
// teléfono). Es aceptable para el prototipo; en producción el refresh token
// debe guardarse en almacenamiento seguro (Keystore/Keychain).

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AlmacenTokens {
  Future<String?> leerRefresh();

  Future<void> guardarRefresh(String refreshToken);

  Future<void> borrar();
}

class MemoriaAlmacenTokens implements AlmacenTokens {
  String? _refresh;

  @override
  Future<String?> leerRefresh() async => _refresh;

  @override
  Future<void> guardarRefresh(String refreshToken) async => _refresh = refreshToken;

  @override
  Future<void> borrar() async => _refresh = null;
}

class DispositivoAlmacenTokens implements AlmacenTokens {
  static const _clave = 'sesion.refreshToken';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> leerRefresh() async => (await _prefs).getString(_clave);

  @override
  Future<void> guardarRefresh(String refreshToken) async => (await _prefs).setString(_clave, refreshToken);

  @override
  Future<void> borrar() async => (await _prefs).remove(_clave);
}
