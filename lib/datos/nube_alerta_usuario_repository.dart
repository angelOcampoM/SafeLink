// CAPA: DATOS — implementación de mañana (alertas del usuario)
// U-03 · U-04 · U-06 · U-07 · U-08 · U-09 · Historial de mis alertas
// Cumple el MISMO contrato que la de memoria; traduce Alerta <-> JSON y usa el servicio.

import '../dominio/dominio.dart';
import 'alerta_usuario_repository.dart';
import 'nube_mapeadores.dart';
import 'safelink_service.dart';

class NubeAlertaUsuarioRepository implements AlertaUsuarioRepository {
  NubeAlertaUsuarioRepository(this._service);
  final SafeLinkService _service;

  @override
  Future<Alerta> crearAlerta({
    required MetodoDisparo metodo,
    required DateTime disparadaEn,
    PuntoGeo? ubicacion,
    int? rumbo,
    String? rutaFoto,
  }) async {
    final r = await _service.post('/alerts', {
      'triggerMethod': CodigosJson.metodo[metodo],
      'triggeredAt': disparadaEn.toIso8601String(),
      'location': ubicacion == null ? null : PuntoGeoJson.aJson(ubicacion),
      'heading': rumbo,
      'photoPath': rutaFoto,
    });
    return AlertaJson.desdeJson(RespuestaJson.datos(r)! as Json);
  }

  @override
  Stream<Alerta?> escucharAlertaActiva() => _service.escuchar('alerts/active').map((e) {
        final d = RespuestaJson.datos(e);
        return d == null ? null : AlertaJson.desdeJson(d as Json);
      });

  @override
  Future<void> enviarUbicacion(String alertaId, PuntoGeo ubicacion) async {
    RespuestaJson.datos(await _service.post('/alerts/$alertaId/locations', {'location': PuntoGeoJson.aJson(ubicacion)}));
  }

  @override
  Future<Alerta> confirmarAtencion(String alertaId) async =>
      AlertaJson.desdeJson(RespuestaJson.datos(await _service.post('/alerts/$alertaId/confirm'))! as Json);

  @override
  Future<List<Alerta>> obtenerHistorial() async => AlertaJson.lista(RespuestaJson.datos(await _service.get('/alerts/mine')));
}
