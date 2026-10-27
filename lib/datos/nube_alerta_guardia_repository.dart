// CAPA: DATOS — implementación de mañana (alertas del guardia)
// G-02 · G-03 · G-04 · G-05 · G-06 · G-07 · Historial y métricas personales
// Cumple el MISMO contrato que la de memoria; traduce entidad <-> JSON y usa el servicio.

import '../dominio/dominio.dart';
import 'alerta_guardia_repository.dart';
import 'nube_mapeadores.dart';
import 'safelink_service.dart';

class NubeAlertaGuardiaRepository implements AlertaGuardiaRepository {
  NubeAlertaGuardiaRepository(this._service);
  final SafeLinkService _service;

  Alerta _alerta(Json r) => AlertaJson.desdeJson(RespuestaJson.datos(r)! as Json);

  @override
  Future<Guardia> obtenerMiPerfil() async => GuardiaJson.desdeJson(RespuestaJson.datos(await _service.get('/guard/me'))! as Json);

  @override
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles() => _service.escuchar('guard/alerts').map(
        (e) => [for (final j in RespuestaJson.datos(e)! as List) AlertaPriorizadaJson.desdeJson(j as Json)],
      );

  @override
  Future<Alerta> obtenerAlerta(String alertaId) async => _alerta(await _service.get('/guard/alerts/$alertaId'));

  @override
  Stream<Alerta> escucharAlerta(String alertaId) =>
      _service.escuchar('guard/alerts/$alertaId').map((e) => AlertaJson.desdeJson(RespuestaJson.datos(e)! as Json));

  @override
  Future<Alerta> aceptarAlerta(String alertaId) async => _alerta(await _service.post('/guard/alerts/$alertaId/accept'));

  @override
  Future<void> ignorarAlerta(String alertaId) async {
    RespuestaJson.datos(await _service.post('/guard/alerts/$alertaId/ignore'));
  }

  @override
  Future<void> actualizarMiUbicacion(PuntoGeo ubicacion) async {
    RespuestaJson.datos(await _service.put('/guard/location', {'location': PuntoGeoJson.aJson(ubicacion)}));
  }

  @override
  Future<Alerta> marcarLlegada(String alertaId) async => _alerta(await _service.post('/guard/alerts/$alertaId/arrive'));

  @override
  Future<List<Alerta>> obtenerMiHistorial() async => AlertaJson.lista(RespuestaJson.datos(await _service.get('/guard/history')));

  @override
  Future<MetricasGuardia> obtenerMisMetricas() async =>
      MetricasGuardiaJson.desdeJson(RespuestaJson.datos(await _service.get('/guard/metrics'))! as Json);
}
