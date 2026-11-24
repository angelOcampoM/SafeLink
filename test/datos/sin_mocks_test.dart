// Con `--dart-define=API_URL=...` NADA puede salir de los datos simulados del front.
//
// Es el acuerdo del equipo para la demo: "nada de mocks, solo consumo real". La prueba que
// había antes solo comprobaba que el repositorio fuera `NubeAuthRepository`, y eso es cierto
// también con el servicio simulado, así que no distinguía una cosa de la otra.
//
// Aquí se levanta un servidor de verdad y se comprueba lo único que no admite duda: que la
// petición SALE de la app y que, si el servidor dice que no, la app NO se inventa la
// respuesta con la semilla local.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/almacen_tokens.dart';
import 'package:safelink/dominio/errores.dart';
import 'package:safelink/main.dart';

void main() {
  late HttpServer servidor;
  late List<String> recibidas;
  late int estado;
  late String cuerpo;

  setUp(() async {
    recibidas = [];
    estado = 200;
    cuerpo = '{"data":null}';
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((p) async {
      recibidas.add('${p.method} ${p.uri.path}');
      p.response.statusCode = estado;
      p.response.headers.contentType = ContentType.json;
      p.response.write(cuerpo);
      await p.response.close();
    });
  });

  tearDown(() async => servidor.close(force: true));

  Dependencias conApi() => Dependencias.crear(
        usarNube: true,
        urlApi: 'http://127.0.0.1:${servidor.port}/api/v1',
        almacenTokens: MemoriaAlmacenTokens(),
      );

  test('el inicio de sesión SALE a la red: la petición llega al servidor', () async {
    estado = 401;
    cuerpo = '{"error":{"code":"INVALID_CREDENTIALS","message":"no"}}';

    await expectLater(
      conApi().auth.iniciarSesion(correo: 'usuario@safelink.mx', contrasena: 'SafeLink1'),
      throwsA(isA<CredencialesInvalidasError>()),
    );
    expect(recibidas, contains('POST /api/v1/auth/login'));
  });

  test('una cuenta de la semilla NO entra si el servidor la rechaza', () async {
    // `usuario@safelink.mx` / `SafeLink1` SÍ existe en los datos simulados del front. Si la
    // app cayera en el mock, este inicio de sesión funcionaría. Tiene que fallar.
    estado = 401;
    cuerpo = '{"error":{"code":"INVALID_CREDENTIALS","message":"no"}}';

    final deps = conApi();
    await expectLater(
      deps.auth.iniciarSesion(correo: 'usuario@safelink.mx', contrasena: 'SafeLink1'),
      throwsA(isA<CredencialesInvalidasError>()),
    );
    expect(deps.auth.usuarioActual, isNull, reason: 'no puede quedar una sesión inventada');
  });

  test('quien entra es quien dice el servidor, no la semilla', () async {
    cuerpo = jsonEncode({
      'data': {
        'id': 'del-servidor',
        'name': 'Persona Del Backend',
        'email': 'usuario@safelink.mx',
        'phone': '7770000000',
        'role': 'protected_user',
        'isActive': true,
        'volumeDoubleClickEnabled': false,
        'falseAlarmCount': 0,
        'blockedUntil': null,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'accessToken': 'a',
        'refreshToken': 'r',
      },
    });

    final u = await conApi().auth.iniciarSesion(
          correo: 'usuario@safelink.mx',
          contrasena: 'SafeLink1',
        );
    // En la semilla del front esta cuenta se llama "Fernanda Morales Gil".
    expect(u.nombre, 'Persona Del Backend');
    expect(u.id, 'del-servidor');
  });

  test('las simulaciones de la demo quedan apagadas', () {
    final deps = conApi();
    deps.iniciarSimulaciones(); // con API real es un no-op; si creara alertas, fallaría aquí
    expect(recibidas, isEmpty, reason: 'arrancar simulaciones no debe generar tráfico ni datos');
  });

  test('sin API_URL sí se usa el simulado: el contraste de la prueba anterior', () async {
    final deps = Dependencias.crear(usarNube: true); // sin urlApi
    final u = await deps.auth.iniciarSesion(correo: 'usuario@safelink.mx', contrasena: 'SafeLink1');
    expect(u.nombre, 'Fernanda Morales Gil', reason: 'esta es la semilla del front');
    expect(recibidas, isEmpty, reason: 'el simulado no sale a la red');
  });
}
