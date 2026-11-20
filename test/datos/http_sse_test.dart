// D3 · El canal en tiempo real del cliente HTTP, contra un servidor real en loopback.
//
// Se usa un HttpServer de verdad en vez de un cliente simulado porque lo que hay que probar
// es justo lo que un simulado no reproduce: el troceado del flujo, la cabecera Authorization,
// que el canal NO se termine al caerse la conexión y que un 401 provoque refresh y reconexión.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/almacen_tokens.dart';
import 'package:safelink/datos/http_safelink_service.dart';
import 'package:safelink/datos/nube_mapeadores.dart' show Json;

/// Lo que el servidor de prueba vio y lo que debe contestar.
class ServidorFalso {
  ServidorFalso(this._servidor) {
    _servidor.listen(_atender);
  }

  static Future<ServidorFalso> abrir() async =>
      ServidorFalso(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _servidor;

  String get urlBase => 'http://127.0.0.1:${_servidor.port}/api/v1';

  /// Peticiones recibidas: ruta y cabecera Authorization.
  final peticiones = <({String ruta, String? autorizacion})>[];

  /// Respuesta de `/auth/refresh`: 200 renueva, 401 la rechaza.
  int estadoRefresh = 200;

  /// Estados con los que responder a cada conexión del canal, en orden.
  /// Cuando se agotan, se usa el último.
  List<int> estadosDelCanal = [200];

  /// Qué escribir en cada conexión del canal, en orden. Si la lista se agota se repite el
  /// último. `null` = mantener la conexión abierta sin escribir nada más.
  List<String?> cuerposDelCanal = ['data: {"data":1}\n\n'];

  /// ¿Cerrar la conexión del canal tras escribir? (simula un corte de red)
  bool cerrarTrasEscribir = true;

  int _conexionesCanal = 0;
  int get conexionesCanal => _conexionesCanal;

  final _abiertas = <HttpResponse>[];

  Future<void> _atender(HttpRequest peticion) async {
    final ruta = peticion.uri.path;
    peticiones.add((ruta: ruta, autorizacion: peticion.headers.value('authorization')));

    if (ruta.endsWith('/auth/refresh')) {
      peticion.response.statusCode = estadoRefresh;
      peticion.response.headers.contentType = ContentType.json;
      peticion.response.write(
        estadoRefresh == 200
            ? '{"data":{"id":"u1","name":"n","email":"e@e.mx","phone":"7771234567",'
                '"role":"protected_user","isActive":true,"volumeDoubleClickEnabled":false,'
                '"falseAlarmCount":0,"blockedUntil":null,"createdAt":"2026-01-01T00:00:00.000Z",'
                '"accessToken":"token-nuevo","refreshToken":"refresh-nuevo"}}'
            : '{"error":{"code":"UNAUTHORIZED","message":"no"}}',
      );
      await peticion.response.close();
      return;
    }

    // Canal SSE.
    final indice = _conexionesCanal;
    _conexionesCanal++;
    final estado = estadosDelCanal[indice.clamp(0, estadosDelCanal.length - 1)];
    peticion.response.statusCode = estado;
    if (estado != 200) {
      peticion.response.headers.contentType = ContentType.json;
      peticion.response.write('{"error":{"code":"SERVICE_UNAVAILABLE","message":"no"}}');
      await peticion.response.close();
      return;
    }
    peticion.response.headers.set('content-type', 'text/event-stream; charset=utf-8');
    // Sin esto, Dart retiene la respuesta hasta cerrarla y no habría nada "en vivo" que leer
    // (el backend real manda además x-accel-buffering: no por el mismo motivo).
    peticion.response.bufferOutput = false;
    final cuerpo = cuerposDelCanal[indice.clamp(0, cuerposDelCanal.length - 1)];
    if (cuerpo != null) {
      peticion.response.write(cuerpo);
      await peticion.response.flush();
    }
    if (cerrarTrasEscribir) {
      await peticion.response.close();
    } else {
      _abiertas.add(peticion.response);
    }
  }

  Future<void> cerrar() async {
    for (final r in _abiertas) {
      try {
        await r.close();
      } on Object {
        // Ya estaba cerrada.
      }
    }
    await _servidor.close(force: true);
  }
}

void main() {
  late ServidorFalso servidor;
  late HttpSafeLinkService servicio;
  late MemoriaAlmacenTokens almacen;

  setUp(() async {
    servidor = await ServidorFalso.abrir();
    almacen = MemoriaAlmacenTokens();
    await almacen.guardarRefresh('refresh-guardado');
    servicio = HttpSafeLinkService(
      urlBase: servidor.urlBase,
      almacen: almacen,
      tiempoMaximo: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    await servidor.cerrar();
  });

  test('un canal desconocido responde NOT_FOUND sin salir a la red', () async {
    final evento = await servicio.escuchar('canal/inventado').first;
    expect((evento['error']! as Map)['code'], 'NOT_FOUND');
    expect(servidor.peticiones, isEmpty);
  });

  test('entrega los eventos del servidor como envoltorios', () async {
    servidor.cuerposDelCanal = ['data: {"data":{"id":"a1"}}\n\n'];
    servidor.cerrarTrasEscribir = false;

    final evento = await servicio.escuchar('alerts/active').first;
    expect(evento['data'], {'id': 'a1'});
  });

  test('pide la ruta /events/<canal> del contrato', () async {
    servidor.cerrarTrasEscribir = false;
    await servicio.escuchar('guard/alerts').first;
    expect(servidor.peticiones.first.ruta, '/api/v1/events/guard/alerts');
  });

  test('el canal con id lleva el id de la alerta en la ruta', () async {
    servidor.cerrarTrasEscribir = false;
    await servicio.escuchar('guard/alerts/abc-123').first;
    expect(servidor.peticiones.first.ruta, '/api/v1/events/guard/alerts/abc-123');
  });

  test('los ping del servidor no llegan a la app como eventos', () async {
    servidor.cuerposDelCanal = [': ping\n\n: ping\n\ndata: {"data":"real"}\n\n'];
    servidor.cerrarTrasEscribir = false;

    final evento = await servicio.escuchar('alerts/active').first;
    expect(evento['data'], 'real');
  });

  test('cancelar la suscripción cierra la conexión y no reconecta', () async {
    servidor.cuerposDelCanal = ['data: {"data":1}\n\n'];
    servidor.cerrarTrasEscribir = false;

    final recibidos = <Object?>[];
    final sub = servicio.escuchar('alerts/active').listen(
          (e) => recibidos.add(e['data']),
        );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    final conexiones = servidor.conexionesCanal;

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(recibidos, [1]);
    expect(servidor.conexionesCanal, conexiones, reason: 'cancelado no debe reconectar');
  });

  test(
    'si el servidor corta la conexión, el canal NO termina: reconecta',
    () async {
      // La primera conexión escribe y corta; la segunda manda otro evento y se queda abierta.
      servidor.cuerposDelCanal = ['data: {"data":1}\n\n', 'data: {"data":2}\n\n'];
      servidor.cerrarTrasEscribir = true;

      final recibidos = <Object?>[];
      var termino = false;
      final sub = servicio.escuchar('alerts/active').listen(
            (e) => recibidos.add(e['data']),
            onDone: () => termino = true,
          );

      // La espera mínima entre reintentos es 1 s.
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await sub.cancel();

      expect(termino, isFalse, reason: 'una pantalla en vivo no puede quedarse muda');
      expect(recibidos, containsAllInOrder([1, 2]));
      expect(servidor.conexionesCanal, greaterThanOrEqualTo(2));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'un 401 al abrir el canal hace refresh y reconecta con el token nuevo',
    () async {
      servidor.estadosDelCanal = [401, 200];
      servidor.cuerposDelCanal = [null, 'data: {"data":"tras refresh"}\n\n'];
      servidor.cerrarTrasEscribir = false;

      final evento = await servicio.escuchar('alerts/active').first;
      expect(evento['data'], 'tras refresh');

      final delCanal = servidor.peticiones.where((p) => p.ruta.contains('/events/')).toList();
      expect(delCanal, hasLength(2));
      expect(delCanal.last.autorizacion, 'Bearer token-nuevo');
      expect(servidor.peticiones.any((p) => p.ruta.endsWith('/auth/refresh')), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'si el refresh se rechaza, el canal avisa UNAUTHORIZED y se cierra',
    () async {
      servidor.estadosDelCanal = [401];
      servidor.estadoRefresh = 401;

      final eventos = await servicio.escuchar('alerts/active').toList();
      expect(eventos, hasLength(1));
      expect((eventos.single['error']! as Map)['code'], 'UNAUTHORIZED');
      // La sesión local se borró: la app tiene que volver al login.
      expect(await almacen.leerRefresh(), anyOf(isNull, isEmpty));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'un error del servidor al abrir el canal se avisa y se reintenta',
    () async {
      servidor.estadosDelCanal = [503, 200];
      servidor.cuerposDelCanal = [null, 'data: {"data":"ya"}\n\n'];
      servidor.cerrarTrasEscribir = false;

      final recibidos = <Json>[];
      final sub = servicio.escuchar('alerts/active').listen(recibidos.add);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await sub.cancel();

      expect((recibidos.first['error']! as Map)['code'], 'SERVICE_UNAVAILABLE');
      expect(recibidos.last['data'], 'ya');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'sin servidor al otro lado avisa SERVICE_UNAVAILABLE y sigue intentando',
    () async {
      final url = servidor.urlBase; // hay que leerla ANTES de cerrarlo
      await servidor.cerrar();
      final caido = HttpSafeLinkService(
        urlBase: url,
        almacen: MemoriaAlmacenTokens(),
        tiempoMaximo: const Duration(milliseconds: 300),
      );

      final recibidos = <Json>[];
      var termino = false;
      final sub = caido.escuchar('alerts/active').listen(
            recibidos.add,
            onDone: () => termino = true,
          );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await sub.cancel();

      expect(recibidos, isNotEmpty);
      expect((recibidos.first['error']! as Map)['code'], 'SERVICE_UNAVAILABLE');
      expect(termino, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
