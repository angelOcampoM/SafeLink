// CAPA: DATOS — implementación de mañana (administración)
// A-01 · A-02 · A-03 · A-04 · A-05 · A-06 · A-07 · A-08
// Cumple el MISMO contrato que la de memoria; traduce entidad <-> JSON y usa el servicio.

import '../dominio/dominio.dart';
import 'admin_repository.dart';
import 'nube_mapeadores.dart';
import 'safelink_service.dart';

class NubeAdminRepository implements AdminRepository {
  NubeAdminRepository(this._service);
  final SafeLinkService _service;

  Guardia _guardia(Json r) => GuardiaJson.desdeJson(RespuestaJson.datos(r)! as Json);

  Map<String, String> _periodo(DateTime? desde, DateTime? hasta) => {
        if (desde != null) 'from': desde.toIso8601String(),
        if (hasta != null) 'to': hasta.toIso8601String(),
      };

  @override
  Future<List<Guardia>> obtenerGuardias({String busqueda = ''}) async {
    final d = RespuestaJson.datos(await _service.get('/admin/guards', query: {'search': busqueda}));
    return [for (final j in d! as List) GuardiaJson.desdeJson(j as Json)];
  }

  @override
  Future<Guardia> obtenerGuardia(String guardiaId) async => _guardia(await _service.get('/admin/guards/$guardiaId'));

  @override
  Future<Guardia> crearGuardia({required String nombre, required String correo, required String telefono}) async =>
      _guardia(await _service.post('/admin/guards', {'name': nombre, 'email': correo, 'phone': telefono}));

  @override
  Future<Guardia> actualizarGuardia(String guardiaId, {String? nombre, String? correo, String? telefono}) async =>
      _guardia(await _service.patch('/admin/guards/$guardiaId', {
        if (nombre != null) 'name': nombre,
        if (correo != null) 'email': correo,
        if (telefono != null) 'phone': telefono,
      }),);

  @override
  Future<void> darDeBajaGuardia(String guardiaId) async {
    RespuestaJson.datos(await _service.delete('/admin/guards/$guardiaId'));
  }

  @override
  Future<Guardia> actualizarCobertura(
    String guardiaId, {
    required String inicioTurno,
    required String finTurno,
    required PuntoGeo centro,
    required int radioMetros,
  }) async =>
      _guardia(await _service.put('/admin/guards/$guardiaId/coverage', {
        'shiftStart': inicioTurno,
        'shiftEnd': finTurno,
        'center': PuntoGeoJson.aJson(centro),
        'radiusMeters': radioMetros,
      }),);

  @override
  Stream<List<Alerta>> escucharEscaladas() =>
      _service.escuchar('admin/alerts/escalated').map((e) => AlertaJson.lista(RespuestaJson.datos(e)));

  @override
  Future<Alerta> resolverAlerta(String alertaId, Resolucion resolucion) async {
    final r = await _service.post('/admin/alerts/$alertaId/resolve', {'resolution': CodigosJson.resolucion[resolucion]});
    return AlertaJson.desdeJson(RespuestaJson.datos(r)! as Json);
  }

  @override
  Future<List<Alerta>> obtenerHistorial(FiltroHistorial filtro) async =>
      AlertaJson.lista(RespuestaJson.datos(await _service.get('/admin/alerts', query: FiltroHistorialJson.aQuery(filtro))));

  @override
  Future<MetricasGenerales> obtenerMetricas({DateTime? desde, DateTime? hasta}) async {
    final r = await _service.get('/admin/metrics', query: _periodo(desde, hasta));
    return MetricasGeneralesJson.desdeJson(RespuestaJson.datos(r)! as Json);
  }

  @override
  Future<MetricasGuardia> obtenerMetricasGuardia(String guardiaId, {DateTime? desde, DateTime? hasta}) async {
    final r = await _service.get('/admin/metrics/guards/$guardiaId', query: _periodo(desde, hasta));
    return MetricasGuardiaJson.desdeJson(RespuestaJson.datos(r)! as Json);
  }

  @override
  Future<List<Usuario>> obtenerUsuariosBloqueados() async {
    final d = RespuestaJson.datos(await _service.get('/admin/users/blocked'));
    return [for (final j in d! as List) UsuarioJson.desdeJson(j as Json)];
  }

  @override
  Future<void> desbloquearUsuario(String usuarioId) async {
    RespuestaJson.datos(await _service.delete('/admin/users/$usuarioId/block'));
  }
}
