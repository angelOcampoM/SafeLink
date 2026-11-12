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
// Tiempo real (SSE): llega en BE-03/BE-04; por ahora `escuchar` informa que no está.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../dominio/errores.dart';
import 'almacen_tokens.dart';
import 'cliente_api.dart';
import 'nube_mapeadores.dart';

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

  final String _base;
  final http.Client _http;
  final AlmacenTokens _almacen;
  final Duration tiempoMaximo;

  String? _accessToken;
  Future<_ResultadoRefresh>? _refrescando;

  Json get _sinConexion => {'error': ErrorJson.aJson(const ServicioNoDisponibleError())};

  @override
  Stream<Json> escuchar(String canal) => Stream.value({
        'error': {
          'code': 'SERVICE_UNAVAILABLE',
          'message': 'Tiempo real disponible en una tarjeta posterior',
        },
      });

  @override
  Future<Json> enviar(String metodo, String ruta, {Json? cuerpo, Map<String, String>? query}) async {
    final publica = _publicas.contains(ruta);
    var r = await _una(metodo, ruta, cuerpo, query, conBearer: !publica);

    if (ruta == '/auth/logout') {
      try {
        if (r.esNoAutorizado && (await _refrescar()).estado == _EstadoRefresh.listo) {
          r = await _una(metodo, ruta, cuerpo, query, conBearer: true); // un solo reintento
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
        r = await _una(metodo, ruta, cuerpo, query, conBearer: true);
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
  Future<_Resp> _una(String metodo, String ruta, Json? cuerpo, Map<String, String>? query, {required bool conBearer}) async {
    final uri = Uri.parse('$_base$ruta').replace(queryParameters: (query == null || query.isEmpty) ? null : query);
    final conCuerpo = metodo == 'POST' || metodo == 'PUT' || metodo == 'PATCH';

    final http.Response res;
    try {
      final peticion = http.Request(metodo, uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json'
        ..headers.addAll({if (conBearer && _accessToken != null) 'Authorization': 'Bearer $_accessToken'});
      if (conCuerpo) {
        peticion.headers['Content-Type'] = 'application/json';
        peticion.body = jsonEncode(cuerpo ?? const <String, Object?>{}); // {} si no hay datos
      }
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
