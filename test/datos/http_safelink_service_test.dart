// Cliente HTTP real (HttpSafeLinkService) probado con un http.Client falso.
// Cubre: tokens y Bearer, 401 -> refresh único -> reintento, restaurar sesión,
// logout, errores de red y que el modo simulado siga siendo el predeterminado.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safelink/datos/almacen_tokens.dart';
import 'package:safelink/datos/http_safelink_service.dart';
import 'package:safelink/datos/nube_alerta_guardia_repository.dart';
import 'package:safelink/datos/nube_auth_repository.dart';
import 'package:safelink/datos/safelink_service.dart';
import 'package:safelink/main.dart';

const _usuario = {
  'id': 'usr-1',
  'name': 'Fernanda Morales Gil',
  'email': 'usuario@safelink.mx',
  'phone': '7771234567',
  'role': 'protected_user',
  'isActive': true,
  'volumeDoubleClickEnabled': false,
  'falseAlarmCount': 0,
  'blockedUntil': null,
  'createdAt': '2026-08-12T15:00:00.000Z',
};

http.Response _json(Object cuerpo, [int estado = 200]) =>
    http.Response(jsonEncode(cuerpo), estado, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response _conTokens(String acceso, String refresh) =>
    _json({'data': {..._usuario, 'accessToken': acceso, 'refreshToken': refresh}});

http.Response _noAutorizado() =>
    _json({'error': {'code': 'UNAUTHORIZED', 'message': 'Tu sesión terminó. Vuelve a iniciar sesión.'}}, 401);

void main() {
  late List<http.Request> peticiones;
  late MemoriaAlmacenTokens almacen;

  HttpSafeLinkService servicio(Future<http.Response> Function(http.Request) manejador) {
    peticiones = [];
    return HttpSafeLinkService(
      urlBase: 'http://127.0.0.1:3000/api/v1/',
      cliente: MockClient((r) {
        peticiones.add(r);
        return manejador(r);
      }),
      almacen: almacen,
    );
  }

  setUp(() => almacen = MemoriaAlmacenTokens());

  test('login guarda los tokens, los quita del User y manda Bearer después', () async {
    final s = servicio((r) async {
      if (r.url.path.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
      return _json({'data': []});
    });

    final login = await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});
    final datos = login['data']! as Map;
    expect(datos['id'], 'usr-1');
    expect(datos.containsKey('accessToken'), isFalse);
    expect(datos.containsKey('refreshToken'), isFalse);
    expect(await almacen.leerRefresh(), 'refresh-1');
    expect(peticiones.first.url.toString(), 'http://127.0.0.1:3000/api/v1/auth/login');
    expect(peticiones.first.headers.containsKey('Authorization'), isFalse);

    await s.get('/alerts/mine');
    expect(peticiones.last.headers['Authorization'], 'Bearer acceso-1');
  });

  test('un POST sin datos manda {} y el GET manda la query', () async {
    final s = servicio((r) async => _json({'data': null}));
    await s.post('/auth/logout');
    expect(peticiones.single.body, '{}');
    expect(peticiones.single.headers['Content-Type'], contains('application/json'));
    await s.get('/admin/guards', query: {'search': 'ana'});
    expect(peticiones.last.url.queryParameters, {'search': 'ana'});
  });

  test('401 en otra ruta: un refresh y un reintento con el token nuevo', () async {
    var vigente = 'acceso-1';
    final s = servicio((r) async {
      final ruta = r.url.path;
      if (ruta.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
      if (ruta.endsWith('/auth/refresh')) {
        expect(jsonDecode(r.body), {'refreshToken': 'refresh-1'});
        vigente = 'acceso-2';
        return _conTokens('acceso-2', 'refresh-2');
      }
      return r.headers['Authorization'] == 'Bearer $vigente' ? _json({'data': []}) : _noAutorizado();
    });
    await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});
    vigente = 'otro'; // el servidor ya no acepta acceso-1

    final r = await s.get('/alerts/mine');

    expect(r, {'data': <Object?>[]});
    final rutas = [for (final p in peticiones) p.url.path.replaceFirst('/api/v1', '')];
    expect(rutas, ['/auth/login', '/alerts/mine', '/auth/refresh', '/alerts/mine']);
    expect(peticiones.last.headers['Authorization'], 'Bearer acceso-2');
    expect(await almacen.leerRefresh(), 'refresh-2');
  });

  test('401 concurrentes comparten un solo refresh', () async {
    var refrescado = false;
    final s = servicio((r) async {
      final ruta = r.url.path;
      if (ruta.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
      if (ruta.endsWith('/auth/refresh')) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        refrescado = true;
        return _conTokens('acceso-2', 'refresh-2');
      }
      return r.headers['Authorization'] == 'Bearer acceso-2' ? _json({'data': []}) : _noAutorizado();
    });
    await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});

    final resultados = await Future.wait([s.get('/alerts/mine'), s.get('/guard/history'), s.get('/guard/me')]);

    expect(refrescado, isTrue);
    expect(resultados.every((r) => r['error'] == null), isTrue);
    expect(peticiones.where((p) => p.url.path.endsWith('/auth/refresh')), hasLength(1));
  });

  test('si el refresh falla con UNAUTHORIZED se devuelve el 401 y se borran los tokens', () async {
    await almacen.guardarRefresh('viejo');
    final s = servicio((r) async => _noAutorizado());

    final r = await s.get('/alerts/mine');

    expect((r['error']! as Map)['code'], 'UNAUTHORIZED');
    expect(await almacen.leerRefresh(), isNull);
    expect(peticiones.where((p) => p.url.path.endsWith('/auth/refresh')), hasLength(1));
  });

  test('login con credenciales malas no dispara refresh', () async {
    final s = servicio((r) async => _json({'error': {'code': 'INVALID_CREDENTIALS', 'message': 'x'}}, 401));
    final r = await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'mala'});
    expect((r['error']! as Map)['code'], 'INVALID_CREDENTIALS');
    expect(peticiones, hasLength(1));
  });

  group('restaurar sesión', () {
    test('hace /auth/refresh ANTES de /auth/session y manda el Bearer nuevo', () async {
      await almacen.guardarRefresh('refresh-1');
      final s = servicio((r) async {
        if (r.url.path.endsWith('/auth/refresh')) return _conTokens('acceso-2', 'refresh-2');
        return _json({'data': _usuario});
      });

      final u = await NubeAuthRepository(s).restaurarSesion('usr-1');

      expect(u?.id, 'usr-1');
      expect([for (final p in peticiones) p.url.path.replaceFirst('/api/v1', '')], ['/auth/refresh', '/auth/session']);
      expect(peticiones.last.headers['Authorization'], 'Bearer acceso-2');
      expect(jsonDecode(peticiones.last.body), {'userId': 'usr-1'});
    });

    test('sin refresh token guardado devuelve null sin llamar a la API', () async {
      final s = servicio((r) async => _json({'data': _usuario}));
      expect(await NubeAuthRepository(s).restaurarSesion('usr-1'), isNull);
      expect(peticiones, isEmpty);
    });

    test('refresh con UNAUTHORIZED devuelve null (no lanza) y borra el token', () async {
      await almacen.guardarRefresh('vencido');
      final s = servicio((r) async => _noAutorizado());
      expect(await NubeAuthRepository(s).restaurarSesion('usr-1'), isNull);
      expect(peticiones, hasLength(1));
      expect(await almacen.leerRefresh(), isNull);
    });

    test('refresh con la red caída lanza SERVICE_UNAVAILABLE y conserva el token', () async {
      await almacen.guardarRefresh('refresh-1');
      final s = servicio((r) async => throw const SocketException('sin red'));
      await expectLater(
        NubeAuthRepository(s).restaurarSesion('usr-1'),
        throwsA(predicate((e) => e.toString().contains('conectar'))),
      );
      expect(await almacen.leerRefresh(), 'refresh-1');
    });
  });

  test('logout borra los tokens locales aunque el servidor falle', () async {
    final s = servicio((r) async {
      if (r.url.path.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
      throw const SocketException('sin red');
    });
    await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});

    final r = await s.post('/auth/logout');

    expect(r, {'data': null});
    expect(await almacen.leerRefresh(), isNull);
    await s.get('/alerts/mine');
    expect(peticiones.last.headers.containsKey('Authorization'), isFalse);
  });

  group('errores de red', () {
    test('excepción de red -> SERVICE_UNAVAILABLE con envoltorio', () async {
      final s = servicio((r) async => throw http.ClientException('sin red'));
      final r = await s.get('/alerts/mine');
      expect(r.keys, ['error']);
      expect((r['error']! as Map)['code'], 'SERVICE_UNAVAILABLE');
      expect((r['error']! as Map)['message'], isNotEmpty);
    });

    test('tiempo agotado -> SERVICE_UNAVAILABLE', () async {
      final s = HttpSafeLinkService(
        urlBase: 'http://127.0.0.1:3000/api/v1',
        cliente: MockClient((_) => Completer<http.Response>().future),
        almacen: almacen,
        tiempoMaximo: const Duration(milliseconds: 20),
      );
      final r = await s.get('/alerts/mine');
      expect((r['error']! as Map)['code'], 'SERVICE_UNAVAILABLE');
    });

    test('respuesta que no es el envoltorio -> SERVICE_UNAVAILABLE', () async {
      final s = servicio((r) async => http.Response('<html>bad gateway</html>', 502));
      final r = await s.get('/alerts/mine');
      expect((r['error']! as Map)['code'], 'SERVICE_UNAVAILABLE');
    });

    test('los errores de la API pasan tal cual (remainingMeters incluido)', () async {
      final s = servicio(
        (r) async => _json(
          {
            'error': {'code': 'OUTSIDE_GEOFENCE', 'message': 'x', 'remainingMeters': 132.4},
          },
          422,
        ),
      );
      final r = await s.post('/guard/alerts/a1/arrive');
      expect((r['error']! as Map)['remainingMeters'], 132.4);
    });
  });


  group('endurecimiento', () {
    test('logout con access vencido: refresh, reintento y tokens borrados', () async {
      var logoutsRevocados = 0;
      final s = servicio((r) async {
        final ruta = r.url.path;
        if (ruta.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
        if (ruta.endsWith('/auth/refresh')) return _conTokens('acceso-2', 'refresh-2');
        if (r.headers['Authorization'] == 'Bearer acceso-2') {
          logoutsRevocados++;
          return _json({'data': null});
        }
        return _noAutorizado();
      });
      await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});

      final r = await s.post('/auth/logout');

      expect(r, {'data': null});
      expect(logoutsRevocados, 1);
      expect(
        [for (final p in peticiones) p.url.path.replaceFirst('/api/v1', '')],
        ['/auth/login', '/auth/logout', '/auth/refresh', '/auth/logout'],
      );
      expect(await almacen.leerRefresh(), isNull);
    });

    test('logout: si todo falla igual se borran los tokens', () async {
      await almacen.guardarRefresh('refresh-1');
      final s = servicio((r) async => _noAutorizado());
      expect(await s.post('/auth/logout'), {'data': null});
      expect(await almacen.leerRefresh(), isNull);
    });

    test('si el reintento tras el refresh vuelve a dar 401 no hay segundo refresh', () async {
      final s = servicio((r) async {
        if (r.url.path.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
        if (r.url.path.endsWith('/auth/refresh')) return _conTokens('acceso-2', 'refresh-2');
        return _noAutorizado();
      });
      await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});

      final r = await s.get('/alerts/mine');

      expect((r['error']! as Map)['code'], 'UNAUTHORIZED');
      expect(peticiones.where((p) => p.url.path.endsWith('/auth/refresh')), hasLength(1));
      expect(peticiones.where((p) => p.url.path.endsWith('/alerts/mine')), hasLength(2));
    });

    test('un 401 posterior a un refresh terminado usa el refresh token NUEVO', () async {
      final usados = <String>[];
      var n = 1;
      final s = servicio((r) async {
        final ruta = r.url.path;
        if (ruta.endsWith('/auth/login')) return _conTokens('acceso-1', 'refresh-1');
        if (ruta.endsWith('/auth/refresh')) {
          usados.add((jsonDecode(r.body) as Map)['refreshToken'] as String);
          n++;
          return _conTokens('acceso-$n', 'refresh-$n');
        }
        return r.headers['Authorization'] == 'Bearer acceso-$n' ? _json({'data': []}) : _noAutorizado();
      });
      await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});

      n++; // el servidor ya no acepta acceso-1
      await s.get('/alerts/mine'); // 401 -> refresh con refresh-1
      n++; // el servidor invalida otra vez el access
      await s.get('/alerts/mine'); // 401 -> refresh con el token nuevo (refresh-3), no con refresh-1

      expect(usados, ['refresh-1', 'refresh-3']);
    });

    test('no se manda Bearer en login, register ni refresh aunque haya sesión', () async {
      final s = servicio((r) async {
        if (r.url.path.endsWith('/auth/refresh')) return _conTokens('acceso-2', 'refresh-2');
        if (r.url.path.endsWith('/auth/login') || r.url.path.endsWith('/auth/register')) {
          return _conTokens('acceso-1', 'refresh-1');
        }
        return r.headers['Authorization'] == 'Bearer acceso-2' ? _json({'data': []}) : _noAutorizado();
      });
      await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});
      await s.post('/auth/register', {'name': 'n'});
      await s.post('/auth/login', {'email': 'a@b.mx', 'password': 'x'});
      await s.get('/alerts/mine'); // dispara /auth/refresh

      for (final p in peticiones.where((p) => RegExp(r'/auth/(login|register|refresh)$').hasMatch(p.url.path))) {
        expect(p.headers.containsKey('Authorization'), isFalse, reason: p.url.path);
      }
      expect(peticiones.where((p) => p.url.path.endsWith('/auth/refresh')), hasLength(1));
    });

    test('los ids con / ? # van codificados en la ruta y no siguen redirecciones', () async {
      final s = servicio((r) async => _json({'data': null}));
      await NubeAlertaGuardiaRepository(s).ignorarAlerta('a/b?c#d');
      final p = peticiones.single;
      expect(p.url.toString(), 'http://127.0.0.1:3000/api/v1/guard/alerts/a%2Fb%3Fc%23d/ignore');
      expect(p.url.hasQuery, isFalse);
      expect(p.followRedirects, isFalse);
    });
  });
  test('escuchar informa que el tiempo real llega después', () async {
    final s = servicio((r) async => _json({'data': null}));
    final e = await s.escuchar('alerts/active').first;
    expect((e['error']! as Map)['code'], 'SERVICE_UNAVAILABLE');
  });

  group('modo predeterminado', () {
    test('sin API_URL ni USAR_NUBE la app usa memoria', () {
      expect(urlApi, isEmpty);
      expect(usarNube, isFalse);
    });

    test('Dependencias.crear(usarNube: true) sin URL sigue usando el servicio simulado', () {
      final d = Dependencias.crear(usarNube: true);
      expect(d.auth, isA<NubeAuthRepository>());
    });

    test('con URL de API arma el cliente HTTP sin tocar la red', () {
      final d = Dependencias.crear(usarNube: true, urlApi: 'http://127.0.0.1:3000/api/v1', almacenTokens: MemoriaAlmacenTokens());
      expect(d.auth, isA<NubeAuthRepository>());
      d.iniciarSimulaciones(); // no hace nada y no falla
    });
  });

  test('SafeLinkService simulado sigue cumpliendo el envoltorio', () async {
    final s = SafeLinkService(latenciaMin: Duration.zero, latenciaMax: Duration.zero);
    final r = await s.post('/auth/login', {'email': 'nadie@safelink.mx', 'password': 'x'});
    expect((r['error']! as Map)['code'], 'INVALID_CREDENTIALS');
    s.dispose();
  });
}
