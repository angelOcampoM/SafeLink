// CAPA: DATOS — almacén de los tokens de sesión de la API real
// El access token (15 min) vive solo en memoria. El refresh token se conserva para poder
// reabrir la sesión al volver a abrir la app (U-02).
//
// FIRMA-02 · Resguardo de credenciales. El refresh token es la llave de la sesión: con él se
// obtienen access tokens nuevos. Antes se guardaba con `shared_preferences`, que en Android es
// un XML sin cifrar dentro del sandbox de la app: basta un teléfono con root o una copia de
// seguridad para leerlo. Ahora va al almacenamiento seguro del sistema (Keystore en Android,
// Keychain en iOS), que cifra el valor con una llave que no sale del hardware.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

/// Almacenamiento seguro del sistema. En Android usa el Keystore con AES-GCM (las opciones
/// por defecto de `flutter_secure_storage` 11); en iOS, el Keychain.
class DispositivoAlmacenTokens implements AlmacenTokens {
  DispositivoAlmacenTokens({FlutterSecureStorage? seguro})
      : _seguro = seguro ?? const FlutterSecureStorage();

  static const _clave = 'sesion.refreshToken';

  final FlutterSecureStorage _seguro;

  /// Si el almacenamiento seguro falla NO se cae a `shared_preferences`: perder la sesión y
  /// tener que iniciarla otra vez es mucho menos grave que dejar la llave en claro en el
  /// teléfono. Un fallo así existe: hay dispositivos con el Keystore roto por una
  /// actualización del sistema.
  @override
  Future<String?> leerRefresh() async {
    try {
      final guardado = await _seguro.read(key: _clave);
      if (guardado != null && guardado.isNotEmpty) return guardado;
    } on Object catch (e) {
      debugPrint('Tokens: no se pudo leer del almacenamiento seguro ($e)');
      // Sin almacenamiento seguro no hay dónde ponerlo a salvo, así que lo que no puede
      // pasar es que la copia en claro de una versión anterior se quede ahí para siempre.
      await _borrarTextoPlano();
      return null;
    }
    return _migrarDesdeTextoPlano();
  }

  @override
  Future<void> guardarRefresh(String refreshToken) async {
    try {
      await _seguro.write(key: _clave, value: refreshToken);
    } on Object catch (e) {
      // Sin almacenamiento seguro la sesión no sobrevive a cerrar la app. Es lo correcto:
      // la alternativa sería guardarla sin cifrar.
      debugPrint('Tokens: no se pudo guardar en el almacenamiento seguro ($e)');
    }
  }

  @override
  Future<void> borrar() async {
    try {
      await _seguro.delete(key: _clave);
    } on Object catch (e) {
      debugPrint('Tokens: no se pudo borrar del almacenamiento seguro ($e)');
    }
    // También la copia antigua, por si quedó de una versión anterior de la app.
    await _borrarTextoPlano();
  }

  /// Una sesión abierta con la versión anterior tiene el token en `shared_preferences`. Se
  /// mueve al almacenamiento seguro y se borra el original; si no, la persona tendría que
  /// volver a iniciar sesión al actualizar y, peor, el token en claro seguiría en el teléfono.
  Future<String?> _migrarDesdeTextoPlano() async {
    final String? antiguo;
    try {
      antiguo = (await SharedPreferences.getInstance()).getString(_clave);
    } on Object catch (e) {
      debugPrint('Tokens: no se pudo leer la copia antigua ($e)');
      return null;
    }
    if (antiguo == null || antiguo.isEmpty) return null;

    try {
      await _seguro.write(key: _clave, value: antiguo);
    } on Object catch (e) {
      // No se pudo mover: se borra igual el texto plano. Mejor pedir la contraseña otra vez
      // que dejar la llave de la sesión sin cifrar.
      debugPrint('Tokens: no se pudo migrar al almacenamiento seguro ($e)');
      await _borrarTextoPlano();
      return null;
    }
    await _borrarTextoPlano();
    return antiguo;
  }

  Future<void> _borrarTextoPlano() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_clave);
    } on Object catch (e) {
      debugPrint('Tokens: no se pudo borrar la copia antigua ($e)');
    }
  }
}
