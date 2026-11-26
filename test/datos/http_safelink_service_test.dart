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
import 'package:safelink/datos/nube_alerta_usuario_repository.dart';
import 'package:safelink/datos/nube_auth_repository.dart';
import 'package:safelink/datos/safelink_service.dart';
import 'package:safelink/dominio/dominio.dart';
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
  group('foto de la alerta (U-06, D2)', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('safelink-foto-'));
    tearDown(() => dir.deleteSync(recursive: true));

    const jpeg = [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46];
    const alerta = {
      'id': 'alt-1', 'userId': 'usr-1', 'userName': null, 'userPhone': null, 'guardId': null, 'guardName': null,
      'status': 'searching', 'triggerMethod': 'tap', 'photoUrl': 'http://x/foto', 'evidenceIncomplete': false,
      'location': {'lat': 18.84, 'lng': -99.18}, 'heading': 35, 'triggeredAt': '2026-11-16T18:00:00.000Z',
      'acceptedAt': null, 'arrivedAt': null, 'closedAt': null, 'escalationReason': null, 'resolution': null,
      'adminNote': null, 'etaSeconds': null,
    };

    String cuerpoTexto(http.Request r) => latin1.decode(r.bodyBytes);

    test('crearAlerta manda multipart con el JSON en data y la foto en photo', () async {
      final foto = File('${dir.path}/IMG_2026_secreta.jpg')..writeAsBytesSync(jpeg);
      final s = servicio((r) async => _json({'data': alerta}, 201));

      final creada = await NubeAlertaUsuarioRepository(s).crearAlerta(
        metodo: MetodoDisparo.toque,
        disparadaEn: DateTime.utc(2026, 11, 16, 18),
        ubicacion: const PuntoGeo(18.84, -99.18),
        rumbo: 35,
        rutaFoto: foto.path,
      );

      expect(creada.evidenciaIncompleta, isFalse);
      final p = peticiones.single;
      expect(p.url.path, '/api/v1/alerts');
      expect(p.headers['content-type'], startsWith('multipart/form-data; boundary='));
      final texto = cuerpoTexto(p);
      expect(texto, contains('name="data"'));
      expect(texto, contains('"triggerMethod":"tap"'));
      expect(texto, contains('name="photo"; filename="evidencia"'));
      // La ruta local del teléfono solo viaja dentro del JSON (photoPath), nunca como nombre de archivo.
      expect(texto, isNot(contains('filename="IMG_2026_secreta.jpg"')));
    });

    test('si la foto no existe, la alerta se manda igual sin el archivo', () async {
      final s = servicio((r) async => _json({'data': {...alerta, 'photoUrl': null, 'evidenceIncomplete': true}}, 201));

      final creada = await NubeAlertaUsuarioRepository(s).crearAlerta(
        metodo: MetodoDisparo.mantener,
        disparadaEn: DateTime.utc(2026, 11, 16, 18),
        rutaFoto: '${dir.path}/no-existe.jpg',
      );

      expect(creada.evidenciaIncompleta, isTrue);
      final texto = cuerpoTexto(peticiones.single);
      expect(texto, contains('name="data"'));
      expect(texto, isNot(contains('name="photo"')));
    });

    test('ante un 401 renueva el token y reintenta con la foto otra vez', () async {
      await almacen.guardarRefresh('refresh-1');
      final foto = File('${dir.path}/f.jpg')..writeAsBytesSync(jpeg);
      var intentos = 0;
      final s = servicio((r) async {
        if (r.url.path.endsWith('/auth/refresh')) return _conTokens('acceso-2', 'refresh-2');
        intentos += 1;
        return intentos == 1 ? _noAutorizado() : _json({'data': alerta}, 201);
      });

      await NubeAlertaUsuarioRepository(s).crearAlerta(
        metodo: MetodoDisparo.toque,
        disparadaEn: DateTime.utc(2026, 11, 16, 18),
        rutaFoto: foto.path,
      );

      final alertas = peticiones.where((r) => r.url.path.endsWith('/alerts')).toList();
      expect(alertas, hasLength(2));
      expect(cuerpoTexto(alertas.last), contains('name="photo"'));
      expect(alertas.last.headers['Authorization'], 'Bearer acceso-2');
    });

    test('el servicio simulado sigue recibiendo un POST normal con photoPath', () async {
      final s = SafeLinkService(latenciaMin: Duration.zero, latenciaMax: Duration.zero);
      final r = await s.postConArchivo('/auth/login', {'email': 'nadie@safelink.mx', 'password': 'x'}, rutaArchivo: '/x.jpg');
      expect((r['error']! as Map)['code'], 'INVALID_CREDENTIALS');
      s.dispose();
    });
  });

  // El canal en tiempo real ya no se prueba aquí. Esta prueba afirmaba que `escuchar()`
  // devolvía SERVICE_UNAVAILABLE ("llega en una tarjeta posterior"), y dejó de ser cierto al
  // implementarlo (D51). Además era inestable: con el cliente simulado competían dos caminos
  // (fallo de red contra 401 y refresh) y ganaba uno u otro según el momento.
  // Ahora el canal tiene sus propias pruebas contra un servidor real: test/datos/http_sse_test.dart.

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
    // Ojo: `isA<NubeAuthRepository>()` se cumple TAMBIÉN con el servicio simulado, así que
    // estas dos no distinguen mock de real. Que con API_URL no se use ningún dato simulado
    // del front lo demuestra test/datos/sin_mocks_test.dart, con un servidor de verdad.
  });

  test('SafeLinkService simulado sigue cumpliendo el envoltorio', () async {
    final s = SafeLinkService(latenciaMin: Duration.zero, latenciaMax: Duration.zero);
    final r = await s.post('/auth/login', {'email': 'nadie@safelink.mx', 'password': 'x'});
    expect((r['error']! as Map)['code'], 'INVALID_CREDENTIALS');
    s.dispose();
  });
}
