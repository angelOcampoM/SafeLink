// CAPA: DATOS — servicio (Gateway)
// El único que "habla" con la API. Aquí la fingimos: recibe y devuelve
// Map<String, Object?> (JSON), tarda 400–800 ms y falla con probabilidad
// [tasaFallo] para probar los estados de error de las pantallas.
// Por dentro, el "servidor" guarda su estado en un MemoriaBaseDatos propio y
// reutiliza la lógica en memoria, así no se duplican reglas de negocio.
// Los repositorios `nube_*` lo usan. La pantalla y el ViewModel no saben que existe.

import 'dart:async';
import 'dart:math';

import '../dominio/dominio.dart';
import 'memoria_admin_repository.dart';
import 'memoria_alerta_guardia_repository.dart';
import 'memoria_alerta_usuario_repository.dart';
import 'memoria_auth_repository.dart';
import 'memoria_base_datos.dart';
import 'nube_mapeadores.dart';

typedef _Manejador = Future<Object?> Function(Map<String, String> params, Json cuerpo, Map<String, String> query);

class _Ruta {
  _Ruta(this.metodo, String patron, this.manejar)
      : _re = RegExp('^${patron.replaceAllMapped(RegExp(r':(\w+)'), (m) => '(?<${m[1]}>[^/]+)')}\$');

  final String metodo;
  final RegExp _re;
  final _Manejador manejar;

  Map<String, String>? coincide(String metodo, String ruta) {
    if (metodo != this.metodo) return null;
    final m = _re.firstMatch(ruta);
    if (m == null) return null;
    return {for (final n in m.groupNames) n: m.namedGroup(n)!};
  }
}

class SafeLinkService {
  SafeLinkService({
    MemoriaBaseDatos? servidor,
    this.tasaFallo = 0.0,
    Random? azar,
    this.latenciaMin = const Duration(milliseconds: 400),
    this.latenciaMax = const Duration(milliseconds: 800),
  })  : _db = servidor ?? MemoriaBaseDatos(latencia: Duration.zero),
        _azar = azar ?? Random() {
    _auth = MemoriaAuthRepository(_db);
    _usuario = MemoriaAlertaUsuarioRepository(_db);
    _guardia = MemoriaAlertaGuardiaRepository(_db);
    _admin = MemoriaAdminRepository(_db);
    _rutas = _definirRutas();
  }

  final MemoriaBaseDatos _db;
  final Random _azar;

  /// 0.0 = nunca falla · 0.3 = falla 3 de cada 10 peticiones · 1.0 = siempre.
  double tasaFallo;
  Duration latenciaMin;
  Duration latenciaMax;

  late final MemoriaAuthRepository _auth;
  late final MemoriaAlertaUsuarioRepository _usuario;
  late final MemoriaAlertaGuardiaRepository _guardia;
  late final MemoriaAdminRepository _admin;
  late final List<_Ruta> _rutas;

  // ── API pública (lo que vería un cliente HTTP) ────────────────────
  Future<Json> get(String ruta, {Map<String, String> query = const {}}) => _peticion('GET', ruta, const {}, query);
  Future<Json> post(String ruta, [Json cuerpo = const {}]) => _peticion('POST', ruta, cuerpo, const {});
  Future<Json> put(String ruta, [Json cuerpo = const {}]) => _peticion('PUT', ruta, cuerpo, const {});
  Future<Json> patch(String ruta, [Json cuerpo = const {}]) => _peticion('PATCH', ruta, cuerpo, const {});
  Future<Json> delete(String ruta) => _peticion('DELETE', ruta, const {}, const {});

  /// Canal en tiempo real (como un WebSocket). Cada evento es `{ "data": ... }`.
  Stream<Json> escuchar(String canal) {
    final Stream<Object?> origen;
    final alerta = RegExp(r'^guard/alerts/([^/]+)$').firstMatch(canal);
    if (canal == 'alerts/active') {
      origen = _usuario.escucharAlertaActiva().map((a) => a == null ? null : AlertaJson.aJson(a));
    } else if (canal == 'guard/alerts') {
      origen = _guardia.escucharAlertasDisponibles().map((l) => [for (final p in l) AlertaPriorizadaJson.aJson(p)]);
    } else if (alerta != null) {
      origen = _guardia.escucharAlerta(alerta[1]!).map(AlertaJson.aJson);
    } else if (canal == 'admin/alerts/escalated') {
      origen = _admin.escucharEscaladas().map((l) => [for (final a in l) AlertaJson.aJson(a)]);
    } else {
      return Stream.value({'error': ErrorJson.aJson(const NoEncontradoError('Canal desconocido'))});
    }
    return origen.map((d) => {'data': d});
  }

  /// Arranca las simulaciones del "servidor" (alertas nuevas, escalamiento).
  void iniciarSimulaciones() => _db.iniciarSimulaciones();

  void dispose() => _db.dispose();

  Future<Json> _peticion(String metodo, String ruta, Json cuerpo, Map<String, String> query) async {
    final rango = max(0, latenciaMax.inMilliseconds - latenciaMin.inMilliseconds);
    final espera = latenciaMin.inMilliseconds + (rango == 0 ? 0 : _azar.nextInt(rango));
    if (espera > 0) await Future<void>.delayed(Duration(milliseconds: espera));

    if (tasaFallo > 0 && _azar.nextDouble() < tasaFallo) {
      return {'error': ErrorJson.aJson(const ServicioNoDisponibleError())};
    }
    for (final r in _rutas) {
      final params = r.coincide(metodo, ruta);
      if (params == null) continue;
      try {
        return {'data': await r.manejar(params, cuerpo, query)};
      } on ErrorDominio catch (e) {
        return {'error': ErrorJson.aJson(e)};
      }
    }
    return {'error': ErrorJson.aJson(NoEncontradoError('$metodo $ruta no existe'))};
  }

  // ── "Servidor": endpoints de la sección 7 ─────────────────────────
  List<_Ruta> _definirRutas() {
    DateTime? fecha(String? v) => v == null ? null : DateTime.parse(v);
    PuntoGeo? punto(Object? j) => PuntoGeoJson.opcional(j);

    return [
      // Sesión
      _Ruta(
        'POST',
        '/auth/login',
        (_, c, __) async => UsuarioJson.aJson(
          await _auth.iniciarSesion(correo: c['email']! as String, contrasena: c['password']! as String),
        ),
      ),
      _Ruta(
        'POST',
        '/auth/register',
        (_, c, __) async => UsuarioJson.aJson(
          await _auth.registrar(
            nombre: c['name']! as String,
            correo: c['email']! as String,
            telefono: c['phone']! as String,
            contrasena: c['password']! as String,
          ),
        ),
      ),
      _Ruta('POST', '/auth/logout', (_, __, ___) async {
        await _auth.cerrarSesion();
        return null;
      }),
      _Ruta('GET', '/auth/me', (_, __, ___) async => UsuarioJson.aJson(await _auth.refrescarSesion())),
      _Ruta(
        'PATCH',
        '/users/me/settings',
        (_, c, __) async => UsuarioJson.aJson(await _auth.actualizarAgitacion(activa: c['shakeEnabled']! as bool)),
      ),

      // Usuario protegido
      _Ruta(
        'POST',
        '/alerts',
        (_, c, __) async => AlertaJson.aJson(
          await _usuario.crearAlerta(
            metodo: CodigosJson.desde(CodigosJson.metodo, c['triggerMethod']),
            disparadaEn: DateTime.parse(c['triggeredAt']! as String),
            ubicacion: punto(c['location']),
            rumbo: c['heading'] as int?,
            rutaFoto: c['photoPath'] as String?,
          ),
        ),
      ),
      _Ruta('GET', '/alerts/mine',
          (_, __, ___) async => [for (final a in await _usuario.obtenerHistorial()) AlertaJson.aJson(a)],),
      _Ruta('POST', '/alerts/:id/locations', (p, c, _) async {
        await _usuario.enviarUbicacion(p['id']!, punto(c['location'])!);
        return null;
      }),
      _Ruta('POST', '/alerts/:id/confirm',
          (p, _, __) async => AlertaJson.aJson(await _usuario.confirmarAtencion(p['id']!)),),

      // Guardia
      _Ruta('GET', '/guard/me', (_, __, ___) async => GuardiaJson.aJson(await _guardia.obtenerMiPerfil())),
      _Ruta('GET', '/guard/history',
          (_, __, ___) async => [for (final a in await _guardia.obtenerMiHistorial()) AlertaJson.aJson(a)],),
      _Ruta('GET', '/guard/metrics',
          (_, __, ___) async => MetricasGuardiaJson.aJson(await _guardia.obtenerMisMetricas()),),
      _Ruta('PUT', '/guard/location', (_, c, __) async {
        await _guardia.actualizarMiUbicacion(punto(c['location'])!);
        return null;
      }),
      _Ruta('GET', '/guard/alerts/:id', (p, _, __) async => AlertaJson.aJson(await _guardia.obtenerAlerta(p['id']!))),
      _Ruta('POST', '/guard/alerts/:id/accept',
          (p, _, __) async => AlertaJson.aJson(await _guardia.aceptarAlerta(p['id']!)),),
      _Ruta('POST', '/guard/alerts/:id/ignore', (p, _, __) async {
        await _guardia.ignorarAlerta(p['id']!);
        return null;
      }),
      _Ruta('POST', '/guard/alerts/:id/arrive',
          (p, _, __) async => AlertaJson.aJson(await _guardia.marcarLlegada(p['id']!)),),

      // Administración
      _Ruta(
        'GET',
        '/admin/guards',
        (_, __, q) async =>
            [for (final g in await _admin.obtenerGuardias(busqueda: q['search'] ?? '')) GuardiaJson.aJson(g)],
      ),
      _Ruta(
        'POST',
        '/admin/guards',
        (_, c, __) async => GuardiaJson.aJson(
          await _admin.crearGuardia(
            nombre: c['name']! as String,
            correo: c['email']! as String,
            telefono: c['phone']! as String,
            contrasena: c['password']! as String,
          ),
        ),
      ),
      _Ruta('GET', '/admin/guards/:id', (p, _, __) async => GuardiaJson.aJson(await _admin.obtenerGuardia(p['id']!))),
      _Ruta(
        'PATCH',
        '/admin/guards/:id',
        (p, c, _) async => GuardiaJson.aJson(
          await _admin.actualizarGuardia(
            p['id']!,
            nombre: c['name'] as String?,
            correo: c['email'] as String?,
            telefono: c['phone'] as String?,
          ),
        ),
      ),
      _Ruta('DELETE', '/admin/guards/:id', (p, _, __) async {
        await _admin.darDeBajaGuardia(p['id']!);
        return null;
      }),
      _Ruta(
        'PUT',
        '/admin/guards/:id/coverage',
        (p, c, _) async => GuardiaJson.aJson(
          await _admin.actualizarCobertura(
            p['id']!,
            inicioTurno: c['shiftStart']! as String,
            finTurno: c['shiftEnd']! as String,
            centro: punto(c['center'])!,
            radioMetros: c['radiusMeters']! as int,
            zona: (c['zone'] as String?) ?? '',
          ),
        ),
      ),
      _Ruta(
        'POST',
        '/admin/alerts/:id/resolve',
        (p, c, _) async => AlertaJson.aJson(
          await _admin.resolverAlerta(
            p['id']!,
            CodigosJson.desde(CodigosJson.resolucion, c['resolution']),
            nota: (c['adminNote'] as String?) ?? '',
          ),
        ),
      ),
      _Ruta(
        'GET',
        '/admin/alerts',
        (_, __, q) async =>
            [for (final a in await _admin.obtenerHistorial(FiltroHistorialJson.desdeQuery(q))) AlertaJson.aJson(a)],
      ),
      _Ruta(
        'GET',
        '/admin/metrics',
        (_, __, q) async => MetricasGeneralesJson.aJson(
          await _admin.obtenerMetricas(desde: fecha(q['from']), hasta: fecha(q['to'])),
        ),
      ),
      _Ruta(
        'GET',
        '/admin/metrics/guards/:id',
        (p, _, q) async => MetricasGuardiaJson.aJson(
          await _admin.obtenerMetricasGuardia(p['id']!, desde: fecha(q['from']), hasta: fecha(q['to'])),
        ),
      ),
      _Ruta(
        'GET',
        '/admin/users',
        (_, __, ___) async => [for (final u in await _admin.obtenerUsuarios()) UsuarioJson.aJson(u)],
      ),
      _Ruta(
        'GET',
        '/admin/users/blocked',
        (_, __, ___) async => [for (final u in await _admin.obtenerUsuariosBloqueados()) UsuarioJson.aJson(u)],
      ),
      _Ruta('DELETE', '/admin/users/:id/block', (p, _, __) async {
        await _admin.desbloquearUsuario(p['id']!);
        return null;
      }),
    ];
  }
}
