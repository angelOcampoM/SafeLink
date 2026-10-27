// CAPA: DATOS — implementación de hoy (alertas del guardia)
// G-02 · G-03 · G-04 · G-05 · G-06 · G-07 · Historial y métricas personales
// Lee y escribe en MemoriaBaseDatos; el orden y la geocerca los pide al dominio.

import '../dominio/dominio.dart';
import 'alerta_guardia_repository.dart';
import 'memoria_base_datos.dart';

class MemoriaAlertaGuardiaRepository implements AlertaGuardiaRepository {
  MemoriaAlertaGuardiaRepository(this._db);
  final MemoriaBaseDatos _db;

  Guardia get _yo => _db.guardiaPorId(_db.yo.id);

  @override
  Future<Guardia> obtenerMiPerfil() async {
    await _db.esperar();
    return _yo;
  }

  @override
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles() {
    final id = _db.yo.id;
    return _db.observar(() {
      final g = _db.guardiaPorId(id);
      final ahora = _db.reloj();
      if (!g.disponibleA(ahora)) return <AlertaPriorizada>[];
      final ignoradas = _db.ignoradas[id] ?? const <String>{};
      final candidatas = _db.alertas.where(
        (a) =>
            a.estado == EstadoAlerta.buscando &&
            a.ubicacion != null &&
            !ignoradas.contains(a.id) &&
            ReglaGeocerca.dentroDeCobertura(g.perfil.centroCobertura!, g.perfil.radioCoberturaMetros!, a.ubicacion!),
      );
      return ReglaPrioridad.ordenar(
        alertas: candidatas.toList(),
        ubicacionGuardia: g.perfil.ultimaUbicacion ?? g.perfil.centroCobertura!,
        ahora: ahora,
        metrosPorMinutoEspera: _db.config.metrosPorMinutoEspera,
      );
    });
  }

  @override
  Future<Alerta> obtenerAlerta(String alertaId) async {
    await _db.esperar();
    return _db.alertaPorId(alertaId);
  }

  @override
  Stream<Alerta> escucharAlerta(String alertaId) => _db.observar(() => _db.alertaPorId(alertaId));

  @override
  Future<Alerta> aceptarAlerta(String alertaId) async {
    await _db.esperar();
    final a = _db.alertaPorId(alertaId);
    if (ReglaAlerta.validarAceptacion(a) != null) throw const AlertaTomadaError();
    final yo = _yo;
    final aceptada = a.copyWith(
      estado: EstadoAlerta.enAtencion,
      guardiaId: yo.usuario.id,
      nombreGuardia: yo.usuario.nombre,
      aceptadaEn: _db.reloj(),
    );
    _db.reemplazarAlerta(aceptada);
    return aceptada;
  }

  @override
  Future<void> ignorarAlerta(String alertaId) async {
    _db.ignoradas.putIfAbsent(_db.yo.id, () => <String>{}).add(alertaId);
    _db.avisar();
  }

  @override
  Future<void> actualizarMiUbicacion(PuntoGeo ubicacion) async {
    final id = _db.yo.id;
    _db.perfiles[id] = _db.perfiles[id]!.copyWith(ultimaUbicacion: ubicacion, ultimaUbicacionEn: _db.reloj());
    _db.avisar();
  }

  @override
  Future<Alerta> marcarLlegada(String alertaId) async {
    await _db.esperar();
    final a = _db.alertaPorId(alertaId);
    final aqui = _yo.perfil.ultimaUbicacion;
    final radio = _db.config.radioGeocercaMetros;
    if (ReglaGeocerca.validarLlegada(aqui, a.ubicacion, radio) != null) {
      throw FueraDeGeocercaError(
        aqui == null || a.ubicacion == null ? double.infinity : ReglaGeocerca.metrosRestantes(aqui, a.ubicacion!, radio),
      );
    }
    final llegada = a.copyWith(estado: EstadoAlerta.guardiaEnLugar, llegadaEn: _db.reloj());
    _db.reemplazarAlerta(llegada);
    _db.simularConfirmacionUsuario(alertaId);
    return llegada;
  }

  @override
  Future<List<Alerta>> obtenerMiHistorial() async {
    await _db.esperar();
    return FiltroHistorial(guardiaId: _db.yo.id).aplicar(_db.alertas.where((a) => !a.estado.activa));
  }

  @override
  Future<MetricasGuardia> obtenerMisMetricas() async {
    await _db.esperar();
    return ReglaMetricas.deGuardia(_db.yo.id, _db.alertas);
  }
}
