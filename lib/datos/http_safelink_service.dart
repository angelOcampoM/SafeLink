// CAPA: DATOS — cliente HTTP real (Gateway contra el backend)
// Cumple el mismo contrato que SafeLinkService (simulado): devuelve el
// envoltorio `{ "data": ... }` / `{ "error": { code, message } }` y nunca lanza.
// Errores de red, de tiempo o respuestas que no son JSON del backend se
// traducen a `SERVICE_UNAVAILABLE`.
//
// Sesión: guarda accessToken (memoria) y refreshToken (AlmacenTokens), manda
// `Authorization: Bearer` en todas las rutas salvo login/register/refresh y, ante
// un 401, hace UN refresh compartido (single-flight) y reintenta una vez.
// Nunca escribe tokens en logs.
// Foto de la alerta (U-06, D2): `postConArchivo` la manda como multipart.
// Tiempo real (SSE, D3): `escuchar` abre `GET /events/<canal>` y se mantiene conectado.
// Reconecta sola con espera creciente, y cuando el servidor cierra el canal porque venció el
// access token (D26) hace refresh y vuelve a conectar sin que la pantalla se entere.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../dominio/errores.dart';
import 'almacen_tokens.dart';
import 'cliente_api.dart';
import 'nube_mapeadores.dart';
import 'sse_eventos.dart';

enum _EstadoRefresh { listo, rechazado, falloRed }

typedef _ResultadoRefresh = ({_EstadoRefresh estado, Json? error});

class HttpSafeLinkService extends ClienteApi {
  HttpSafeLinkService({
    required String urlBase,
    http.Client? cliente,
    AlmacenTokens? almacen,
    this.tiempoMaximo = const Duration(seconds: 15),
  })  : _base = urlBase.trim().replaceAll(RegExp(r'/+$'), ''),
        _http = cliente ?? http.Client(),
        _almacen = almacen ?? MemoriaAlmacenTokens();

  /// Rutas sin Bearer; además son las que devuelven accessToken/refreshToken.
  static const _publicas = {'/auth/login', '/auth/register', '/auth/refresh'};

  /// Canales del contrato (sección 6). `guard/alerts/:id` lleva el id de la alerta.
  static final _canalConId = RegExp(r'^guard/alerts/[^/]+$');
  static const _canalesFijos = {'alerts/active', 'guard/alerts', 'admin/alerts/escalated'};

  /// Espera entre reintentos de un canal: arranca en 1 s y se duplica hasta 30 s.
  static const _esperaMinima = Duration(seconds: 1);
  static const _esperaMaxima = Duration(seconds: 30);

  final String _base;
  final http.Client _http;
  final AlmacenTokens _almacen;
  final Duration tiempoMaximo;

  String? _accessToken;
  Future<_ResultadoRefresh>? _refrescando;

  Json get _sinConexion => {'error': ErrorJson.aJson(const ServicioNoDisponibleError())};

  /// Canal en tiempo real (D3). El flujo **no termina solo**: mientras alguien escuche, se
  /// reconecta. Una pantalla que depende de una alerta en curso no puede quedarse muda porque
  /// el túnel se cayó un segundo; quien deja de necesitarlo cancela la suscripción.
  @override
  Stream<Json> escuchar(String canal) {
    if (!_canalesFijos.contains(canal) && !_canalConId.hasMatch(canal)) {
      return Stream.value({'error': ErrorJson.aJson(const NoEncontradoError('Canal desconocido'))});
    }

    var cancelado = false;
    var espera = _esperaMinima;
    StreamSubscription<Json>? suscripcion;
    http.Client? conexion;
    late final StreamController<Json> control;

    /// Cierra la conexión en curso, si hay.
    ///
    /// El ORDEN importa: primero se cierra el cliente HTTP y después se cancela la
    /// suscripción. Al revés, `cancel()` se queda esperando a que el socket termine —y un SSE
    /// no termina nunca—, así que una pantalla que se cierra se colgaría al soltar el canal.
    Future<void> cerrarConexion() async {
      final cliente = conexion;
      conexion = null;
      cliente?.close(); // aborta el flujo HTTP abierto
      final sub = suscripcion;
      suscripcion = null;
      await sub?.cancel();
    }

    /// Un intento: devuelve `true` si hay que reconectar, `false` si el canal se termina.
    Future<bool> unIntento() async {
      // Cliente propio por intento: cerrarlo es lo que aborta un SSE abierto, y hacerlo sobre
      // el cliente compartido cancelaría también las peticiones normales en vuelo.
      final cliente = http.Client();
      conexion = cliente;
      final http.StreamedResponse respuesta;
      try {
        final peticion = http.Request('GET', Uri.parse('$_base/events/$canal'))
          ..followRedirects = false
          ..headers['Accept'] = 'text/event-stream'
          ..headers['Cache-Control'] = 'no-store';
        if (_accessToken != null) peticion.headers['Authorization'] = 'Bearer $_accessToken';
        // El tiempo máximo aplica solo a abrir el canal: el flujo después vive indefinidamente.
        respuesta = await cliente.send(peticion).timeout(tiempoMaximo);
      } on Object {
        cliente.close();
        if (!cancelado) control.add(_sinConexion);
        return true;
      }
      if (cancelado) {
        cliente.close();
        return false;
      }

      if (respuesta.statusCode == 401) {
        cliente.close();
        // D26: el token venció o la sesión ya no vale. Un refresh y se reintenta.
        final refresh = await _refrescar();
        if (refresh.estado == _EstadoRefresh.listo) return true; // reconecta callado
        if (refresh.estado == _EstadoRefresh.rechazado) {
          if (!cancelado) {
            control.add({'error': ErrorJson.aJson(const SinSesionError())});
            await control.close();
          }
          return false; // la sesión se perdió de verdad: que la app lo vea y cierre sesión
        }
        control.add(refresh.error ?? _sinConexion);
        return true;
      }
      if (respuesta.statusCode != 200) {
        cliente.close();
        if (!cancelado) control.add(await _errorDeRespuesta(respuesta));
        return true;
      }

      // Conexión buena: la espera vuelve al mínimo para que el siguiente corte reaccione rápido.
      espera = _esperaMinima;
      final terminado = Completer<bool>();
      // Un error del transporte (se cayó la red, o nosotros abortamos el socket al cancelar)
      // significa "se cortó": se absorbe aquí para que el flujo simplemente termine y la
      // reconexión la decida el bucle. Si se dejara subir, cancelar una pantalla soltaría una
      // excepción que ya nadie escucha.
      final lineas = respuesta.stream
          .toStringStream()
          .transform(const LineSplitter())
          .handleError((Object _) {});
      suscripcion = eventosSse(lineas).listen(
        (evento) {
          if (cancelado) return;
          // El servidor avisa UNAUTHORIZED y cierra cuando vence el token (D26): eso se
          // resuelve con un refresh, no mostrándole al usuario que se quedó sin sesión.
          if (_esNoAutorizado(evento)) return; // el cierre del stream dispara la reconexión
          control.add(evento);
        },
        onError: (Object _) {
          if (!terminado.isCompleted) terminado.complete(true);
        },
        onDone: () {
          if (!terminado.isCompleted) terminado.complete(true);
        },
        cancelOnError: true,
      );
      final reconectar = await terminado.future;
      await cerrarConexion();
      return reconectar && !cancelado;
    }

    Future<void> bucle() async {
      while (!cancelado) {
        final seguir = await unIntento();
        if (!seguir || cancelado) return;
        await Future<void>.delayed(espera);
        // Espera creciente, con techo: un servidor caído no recibe una petición por segundo.
        final siguiente = espera * 2;
        espera = siguiente > _esperaMaxima ? _esperaMaxima : siguiente;
      }
    }

    control = StreamController<Json>(
      onListen: () => unawaited(bucle()),
      onCancel: () async {
        cancelado = true;
        await cerrarConexion();
      },
    );
    return control.stream;
  }

  /// ¿El evento es el aviso de sesión vencida que manda el servidor antes de cerrar (D26)?
  static bool _esNoAutorizado(Json evento) {
    final error = evento['error'];
    return error is Map && error['code'] == 'UNAUTHORIZED';
  }

  /// Envoltorio de error de una respuesta que no es 200 al abrir el canal.
  Future<Json> _errorDeRespuesta(http.StreamedResponse respuesta) async {
    try {
      final cuerpo = jsonDecode(await respuesta.stream.bytesToString());
      if (cuerpo is Map && cuerpo['error'] is Map) return Json.from(cuerpo);
    } on Object {
      // Respuesta que no es JSON del backend (un proxy, por ejemplo).
    }
    return _sinConexion;
  }

  @override
  Future<Json> enviar(String metodo, String ruta, {Json? cuerpo, Map<String, String>? query}) =>
      _enviar(metodo, ruta, cuerpo, query);

  /// U-06 · D2: `multipart/form-data` con el JSON en el campo `data` y la foto en
  /// `photo`. Si el archivo no se puede leer, la alerta viaja igual sin foto (el
  /// backend la marca como evidencia incompleta): nunca se pierde una alerta por la foto.
  @override
  Future<Json> postConArchivo(String ruta, Json datos, {String? rutaArchivo}) =>
      _enviar('POST', ruta, datos, null, rutaArchivo: rutaArchivo, multipart: true);

  Future<Json> _enviar(
    String metodo,
    String ruta,
    Json? cuerpo,
    Map<String, String>? query, {
    String? rutaArchivo,
    bool multipart = false,
  }) async {
    final publica = _publicas.contains(ruta);
    Future<_Resp> una({required bool conBearer}) =>
        _una(metodo, ruta, cuerpo, query, conBearer: conBearer, rutaArchivo: rutaArchivo, multipart: multipart);
    var r = await una(conBearer: !publica);

    if (ruta == '/auth/logout') {
      try {
        if (r.esNoAutorizado && (await _refrescar()).estado == _EstadoRefresh.listo) {
          r = await una(conBearer: true); // un solo reintento
        }
      } finally {
        // La sesión local se cierra pase lo que pase con el servidor.
        _accessToken = null;
        await _almacen.borrar();
      }
      return r.error == null ? r.respuesta : {'data': null};
    }

    if (!publica && r.esNoAutorizado) {
      final refresh = await _refrescar();
      if (refresh.estado == _EstadoRefresh.listo) {
        r = await una(conBearer: true); // el multipart se vuelve a armar: su cuerpo no se reutiliza
      } else if (refresh.estado == _EstadoRefresh.falloRed) {
        return refresh.error ?? _sinConexion;
      }
    }
    return r.respuesta;
  }

  @override
  Future<Json?> restaurarSesionGuardada() async {
    final token = await _almacen.leerRefresh();
    if (token == null || token.isEmpty) return {'data': null};
    final refresh = await _refrescar();
    return switch (refresh.estado) {
      _EstadoRefresh.listo => null,
      _EstadoRefresh.rechazado => {'data': null},
      _EstadoRefresh.falloRed => refresh.error ?? _sinConexion,
    };
  }

  // ── Interno ───────────────────────────────────────────────────────

  /// Un solo refresh en vuelo: las peticiones concurrentes que reciben 401 lo comparten.
  Future<_ResultadoRefresh> _refrescar() => _refrescando ??= _hacerRefresh().whenComplete(() => _refrescando = null);

  Future<_ResultadoRefresh> _hacerRefresh() async {
    final token = await _almacen.leerRefresh();
    if (token == null || token.isEmpty) return (estado: _EstadoRefresh.rechazado, error: null);
    final r = await _una('POST', '/auth/refresh', {'refreshToken': token}, null, conBearer: false);
    if (r.error == null) return (estado: _EstadoRefresh.listo, error: null);
    if (r.codigoError == 'UNAUTHORIZED') {
      _accessToken = null;
      await _almacen.borrar();
      return (estado: _EstadoRefresh.rechazado, error: null);
    }
    return (estado: _EstadoRefresh.falloRed, error: r.respuesta);
  }

  /// Una petición HTTP, sin reintentos. Guarda los tokens de login/register/refresh.
  Future<_Resp> _una(
    String metodo,
    String ruta,
    Json? cuerpo,
    Map<String, String>? query, {
    required bool conBearer,
    String? rutaArchivo,
    bool multipart = false,
  }) async {
    final uri = Uri.parse('$_base$ruta').replace(queryParameters: (query == null || query.isEmpty) ? null : query);
    final conCuerpo = metodo == 'POST' || metodo == 'PUT' || metodo == 'PATCH';

    final http.Response res;
    try {
      final http.BaseRequest peticion;
      if (multipart) {
        peticion = await _multipart(metodo, uri, cuerpo, rutaArchivo);
      } else {
        final json = http.Request(metodo, uri);
        if (conCuerpo) {
          json.headers['Content-Type'] = 'application/json';
          json.body = jsonEncode(cuerpo ?? const <String, Object?>{}); // {} si no hay datos
        }
        peticion = json;
      }
      peticion
        ..followRedirects = false
        ..headers['Accept'] = 'application/json'
        ..headers.addAll({if (conBearer && _accessToken != null) 'Authorization': 'Bearer $_accessToken'});
      // Un solo tiempo máximo para enviar y leer la respuesta.
      res = await (() async => http.Response.fromStream(await _http.send(peticion)))().timeout(tiempoMaximo);
    } on Object {
      return _Resp(0, _sinConexion);
    }

    final Object? decodificado;
    try {
      decodificado = jsonDecode(utf8.decode(res.bodyBytes));
    } on Object {
      return _Resp(res.statusCode, _sinConexion);
    }
    if (decodificado is! Map || (!decodificado.containsKey('data') && decodificado['error'] is! Map)) {
      return _Resp(res.statusCode, _sinConexion);
    }
    var cuerpoRespuesta = Json.from(decodificado);
    if (_publicas.contains(ruta) && cuerpoRespuesta['error'] == null) {
      cuerpoRespuesta = await _extraerTokens(cuerpoRespuesta);
    }
    return _Resp(res.statusCode, cuerpoRespuesta);
  }

  /// Petición multipart: el JSON va en `data` y, si se puede leer, el archivo en `photo`.
  /// El nombre del archivo que viaja es fijo: la ruta local del teléfono no sale del equipo
  /// (el servidor tampoco la usaría, D2).
  Future<http.MultipartRequest> _multipart(String metodo, Uri uri, Json? cuerpo, String? rutaArchivo) async {
    final peticion = http.MultipartRequest(metodo, uri)..fields['data'] = jsonEncode(cuerpo ?? const <String, Object?>{});
    if (rutaArchivo != null && rutaArchivo.isNotEmpty) {
      try {
        peticion.files.add(await http.MultipartFile.fromPath('photo', rutaArchivo, filename: 'evidencia'));
      } on Object {
        // Sin acceso al archivo (o en web): la alerta viaja sin foto.
      }
    }
    return peticion;
  }

  /// Guarda los tokens y los quita del User antes de entregarlo al mapeador.
  Future<Json> _extraerTokens(Json respuesta) async {
    final datos = respuesta['data'];
    if (datos is! Map) return respuesta;
    final usuario = Json.from(datos);
    final acceso = usuario.remove('accessToken');
    final refresh = usuario.remove('refreshToken');
    if (acceso is String) _accessToken = acceso;
    if (refresh is String) await _almacen.guardarRefresh(refresh);
    return {...respuesta, 'data': usuario};
  }
}

class _Resp {
  _Resp(this.estado, this.respuesta);
  final int estado;
  final Json respuesta;

  Object? get error => respuesta['error'];

  String? get codigoError {
    final e = respuesta['error'];
    return e is Map ? e['code'] as String? : null;
  }

  bool get esNoAutorizado => estado == 401 && codigoError == 'UNAUTHORIZED';
}
