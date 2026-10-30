// CAPA: DATOS — implementación de hoy (administración)
// A-01 · A-02 · A-03 · A-04 · A-05 · A-06 · A-07 · A-08
// Lee y escribe en MemoriaBaseDatos; falsas alarmas, filtros y métricas los
// pide al dominio.

import '../dominio/dominio.dart';
import 'admin_repository.dart';
import 'memoria_base_datos.dart';

class MemoriaAdminRepository implements AdminRepository {
  MemoriaAdminRepository(this._db);
  final MemoriaBaseDatos _db;

  bool _correoOcupado(String correo, {String? excepto}) => _db.usuarios.values
      .any((u) => u.id != excepto && u.correo.toLowerCase() == correo.trim().toLowerCase());

  @override
  Future<List<Guardia>> obtenerGuardias({String busqueda = ''}) async {
    await _db.esperar();
    final q = busqueda.trim().toLowerCase();
    return _db.perfiles.keys
        .map(_db.guardiaPorId)
        .where((g) => q.isEmpty || g.usuario.nombre.toLowerCase().contains(q) || g.usuario.correo.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        if (a.usuario.activo != b.usuario.activo) return a.usuario.activo ? -1 : 1;
        return a.usuario.nombre.compareTo(b.usuario.nombre);
      });
  }

  @override
  Future<Guardia> obtenerGuardia(String guardiaId) async {
    await _db.esperar();
    return _db.guardiaPorId(guardiaId);
  }

  @override
  Future<Guardia> crearGuardia({required String nombre, required String correo, required String telefono}) async {
    await _db.esperar();
    if (_correoOcupado(correo)) throw const CorreoRegistradoError();
    final id = _db.nuevoId('grd');
    _db.usuarios[id] = Usuario(
      id: id,
      nombre: nombre.trim(),
      correo: correo.trim(),
      telefono: telefono.trim(),
      rol: RolUsuario.guardia,
      creadoEn: _db.reloj(),
    );
    _db.contrasenas[id] = 'SafeLink1';
    _db.perfiles[id] = PerfilGuardia(
      usuarioId: id,
      inicioTurno: '08:00',
      finTurno: '16:00',
      centroCobertura: null,
      radioCoberturaMetros: null,
    );
    _db.avisar();
    return _db.guardiaPorId(id);
  }

  @override
  Future<Guardia> actualizarGuardia(String guardiaId, {String? nombre, String? correo, String? telefono}) async {
    await _db.esperar();
    if (correo != null && _correoOcupado(correo, excepto: guardiaId)) throw const CorreoRegistradoError();
    final u = _db.guardiaPorId(guardiaId).usuario;
    _db.usuarios[guardiaId] = u.copyWith(nombre: nombre?.trim(), correo: correo?.trim(), telefono: telefono?.trim());
    _db.avisar();
    return _db.guardiaPorId(guardiaId);
  }

  @override
  Future<void> darDeBajaGuardia(String guardiaId) async {
    await _db.esperar();
    _db.usuarios[guardiaId] = _db.guardiaPorId(guardiaId).usuario.copyWith(activo: false);
    _db.avisar();
  }

  @override
  Future<Guardia> actualizarCobertura(
    String guardiaId, {
    required String inicioTurno,
    required String finTurno,
    required PuntoGeo centro,
    required int radioMetros,
  }) async {
    await _db.esperar();
    final motivo = ReglaTurno.validar(inicioTurno, finTurno) ??
        ReglaGeocerca.validarRadio(
          radioMetros,
          minimo: _db.config.radioCoberturaMinMetros,
          maximo: _db.config.radioCoberturaMaxMetros,
        );
    if (motivo != null) throw EstadoInvalidoError(motivo);
    _db.perfiles[guardiaId] = _db.guardiaPorId(guardiaId).perfil.copyWith(
          inicioTurno: inicioTurno,
          finTurno: finTurno,
          centroCobertura: centro,
          radioCoberturaMetros: radioMetros,
        );
    _db.avisar();
    return _db.guardiaPorId(guardiaId);
  }

  @override
  Stream<List<Alerta>> escucharEscaladas() => _db.observar(
        () => _db.alertas.where((a) => a.estado == EstadoAlerta.escalada).toList()
          ..sort((a, b) => a.disparadaEn.compareTo(b.disparadaEn)),
      );

  @override
  Future<Alerta> resolverAlerta(String alertaId, Resolucion resolucion, {required String nota}) async {
    await _db.esperar();
    final a = _db.alertaPorId(alertaId);
    final motivo = ReglaAlerta.validarResolucion(a) ?? ReglaAlerta.nota(nota);
    if (motivo != null) throw EstadoInvalidoError(motivo);
    final ahora = _db.reloj();
    final resuelta = a.copyWith(estado: EstadoAlerta.resueltaPorAdmin, resolucion: resolucion, notaAdmin: nota.trim(), cerradaEn: ahora);
    if (resolucion == Resolucion.falsaAlarma) {
      _db.usuarios[a.usuarioId] = ReglaAlerta.aplicarFalsaAlarma(
        _db.usuarios[a.usuarioId]!,
        ahora: ahora,
        limite: _db.config.limiteFalsasAlarmas,
        diasBloqueo: _db.config.diasBloqueo,
      );
    }
    _db.reemplazarAlerta(resuelta);
    return resuelta;
  }

  @override
  Future<List<Alerta>> obtenerHistorial(FiltroHistorial filtro) async {
    await _db.esperar();
    return filtro.aplicar(_db.alertas);
  }

  @override
  Future<MetricasGenerales> obtenerMetricas({DateTime? desde, DateTime? hasta}) async {
    final lista = await obtenerHistorial(FiltroHistorial(desde: desde, hasta: hasta));
    return ReglaMetricas.generales(lista);
  }

  @override
  Future<MetricasGuardia> obtenerMetricasGuardia(String guardiaId, {DateTime? desde, DateTime? hasta}) async {
    final lista = await obtenerHistorial(FiltroHistorial(desde: desde, hasta: hasta, guardiaId: guardiaId));
    return ReglaMetricas.deGuardia(guardiaId, lista);
  }

  @override
  Future<List<Usuario>> obtenerUsuarios() async {
    await _db.esperar();
    return _db.usuarios.values.where((u) => u.rol == RolUsuario.usuarioProtegido).toList()
      ..sort((a, b) => a.nombre.compareTo(b.nombre));
  }

  @override
  Future<List<Usuario>> obtenerUsuariosBloqueados() async {
    await _db.esperar();
    final ahora = _db.reloj();
    return _db.usuarios.values.where((u) => u.bloqueadoEn(ahora)).toList();
  }

  @override
  Future<void> desbloquearUsuario(String usuarioId) async {
    await _db.esperar();
    _db.usuarios[usuarioId] = _db.usuarios[usuarioId]!.copyWith(quitarBloqueo: true, falsasAlarmas: 0);
    _db.avisar();
  }
}
