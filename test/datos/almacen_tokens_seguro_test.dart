// FIRMA-02 · El refresh token es la llave de la sesión y no puede quedar en claro en el
// teléfono. Estas pruebas fijan las tres decisiones que importan:
//   1. Se guarda y se lee del almacenamiento seguro, no de shared_preferences.
//   2. Una sesión abierta con la versión anterior se MIGRA y el texto plano se borra.
//   3. Si el almacenamiento seguro falla NO se cae a texto plano: se pierde la sesión.
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/almacen_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento seguro de mentira: guarda en memoria y puede fingir que el Keystore falla.
class SeguroFalso extends FlutterSecureStorage {
  const SeguroFalso(this._datos, {this.rompe = false});

  final Map<String, String> _datos;
  final bool rompe;

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (rompe) throw PlatformException(code: 'KEYSTORE_ROTO');
    return _datos[key];
  }

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (rompe) throw PlatformException(code: 'KEYSTORE_ROTO');
    if (value == null) { _datos.remove(key); return; }
    _datos[key] = value;
  }

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (rompe) throw PlatformException(code: 'KEYSTORE_ROTO');
    _datos.remove(key);
  }
}

const _clave = 'sesion.refreshToken';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> seguro;

  setUp(() {
    seguro = {};
    SharedPreferences.setMockInitialValues({});
  });

  DispositivoAlmacenTokens almacen({bool rompe = false}) =>
      DispositivoAlmacenTokens(seguro: SeguroFalso(seguro, rompe: rompe));

  Future<String?> enTextoPlano() async => (await SharedPreferences.getInstance()).getString(_clave);

  test('guarda en el almacenamiento seguro, no en texto plano', () async {
    await almacen().guardarRefresh('token-secreto');

    expect(seguro[_clave], 'token-secreto');
    expect(await enTextoPlano(), isNull, reason: 'nunca debe tocar shared_preferences');
  });

  test('lee lo que guardó', () async {
    final a = almacen();
    await a.guardarRefresh('token-secreto');
    expect(await a.leerRefresh(), 'token-secreto');
  });

  test('sin nada guardado devuelve null', () async {
    expect(await almacen().leerRefresh(), isNull);
  });

  test('borrar lo quita del almacenamiento seguro', () async {
    final a = almacen();
    await a.guardarRefresh('token-secreto');
    await a.borrar();
    expect(seguro, isEmpty);
    expect(await a.leerRefresh(), isNull);
  });

  group('migración desde la versión anterior', () {
    test('mueve el token al almacenamiento seguro y borra el texto plano', () async {
      SharedPreferences.setMockInitialValues({_clave: 'token-de-antes'});

      final leido = await almacen().leerRefresh();

      expect(leido, 'token-de-antes', reason: 'la sesión no se pierde al actualizar');
      expect(seguro[_clave], 'token-de-antes', reason: 'ya cifrado');
      expect(await enTextoPlano(), isNull, reason: 'la copia en claro NO puede quedarse');
    });

    test('solo migra una vez: la segunda lectura ya sale del seguro', () async {
      SharedPreferences.setMockInitialValues({_clave: 'token-de-antes'});
      final a = almacen();
      await a.leerRefresh();

      seguro[_clave] = 'token-nuevo'; // como si se hubiera renovado
      expect(await a.leerRefresh(), 'token-nuevo');
    });

    test('borrar limpia también la copia antigua', () async {
      SharedPreferences.setMockInitialValues({_clave: 'token-de-antes'});
      await almacen().borrar();
      expect(await enTextoPlano(), isNull);
    });
  });

  group('si el Keystore falla', () {
    test('leer devuelve null en vez de tumbar la app', () async {
      expect(await almacen(rompe: true).leerRefresh(), isNull);
    });

    test('guardar no revienta, pero la sesión no persiste', () async {
      final a = almacen(rompe: true);
      await a.guardarRefresh('token-secreto');
      expect(seguro, isEmpty);
      expect(await enTextoPlano(), isNull, reason: 'JAMÁS se cae a texto plano');
    });

    test('borrar no revienta', () async {
      await almacen(rompe: true).borrar();
    });

    test('si la migración no puede cifrar, borra igual el texto plano', () async {
      SharedPreferences.setMockInitialValues({_clave: 'token-de-antes'});

      final leido = await almacen(rompe: true).leerRefresh();

      expect(leido, isNull);
      expect(
        await enTextoPlano(),
        isNull,
        reason: 'mejor pedir la contraseña otra vez que dejar la llave sin cifrar',
      );
    });
  });
}
