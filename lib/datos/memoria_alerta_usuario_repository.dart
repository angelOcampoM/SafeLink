// CAPA: DATOS — implementación de hoy (alertas del usuario)
// U-03 · U-04 · U-06 · U-07 · U-08 · U-09 · Historial de mis alertas
// Lee y escribe en MemoriaBaseDatos y arranca la simulación de respuesta del guardia.

import '../dominio/dominio.dart';
import 'alerta_usuario_repository.dart';
import 'memoria_base_datos.dart';

class MemoriaAlertaUsuarioRepository implements AlertaUsuarioRepository {
  MemoriaAlertaUsuarioRepository(this._db);
  final MemoriaBaseDatos _db;

  @override
  Future<Alerta> crearAlerta({
    required MetodoDisparo metodo,
    required DateTime disparadaEn,
    PuntoGeo? ubicacion,
    int? rumbo,
    String? rutaFoto,
  }) async {
    await _db.esperar();
    final yo = _db.yo;
    if (ReglaAlerta.validarCreacion(yo, _db.reloj()) != null) throw const UsuarioBloqueadoError();

    final id = _db.nuevoId('alt');
    final alerta = Alerta(
      id: id,
      usuarioId: yo.id,
      nombreUsuario: yo.nombre,
      telefonoUsuario: yo.telefono,
      estado: ubicacion == null ? EstadoAlerta.pendienteUbicacion : EstadoAlerta.buscando,
      metodo: metodo,
      disparadaEn: disparadaEn,
      ubicacion: ubicacion,
      rumbo: rumbo,
      fotoUrl: rutaFoto == null ? null : 'https://picsum.photos/seed/$id/640/420',
      evidenciaIncompleta: rutaFoto == null,
    );
    _db.alertas.add(alerta);
    _db.avisar();
    if (alerta.estado == EstadoAlerta.buscando) _db.simularRespuestaGuardia(alerta.id);
    return alerta;
  }

  @override
  Stream<Alerta?> escucharAlertaActiva() {
    final id = _db.yo.id;
    return _db.observar(() => _db.alertas.where((a) => a.usuarioId == id && a.estado.activa).lastOrNull);
  }

  @override
  Future<void> enviarUbicacion(String alertaId, PuntoGeo ubicacion) async {
    final a = _db.alertaPorId(alertaId);
    if (a.estado == EstadoAlerta.pendienteUbicacion) {
      _db.reemplazarAlerta(a.copyWith(estado: EstadoAlerta.buscando, ubicacion: ubicacion));
      _db.simularRespuestaGuardia(alertaId);
    } else {
      _db.reemplazarAlerta(a.copyWith(ubicacion: ubicacion));
    }
  }

  @override
  Future<Alerta> confirmarAtencion(String alertaId) async {
    await _db.esperar();
    final a = _db.alertaPorId(alertaId);
    final motivo = ReglaAlerta.validarConfirmacion(a);
    if (motivo != null) throw EstadoInvalidoError(motivo);
    final cerrada = a.copyWith(estado: EstadoAlerta.cerrada, cerradaEn: _db.reloj());
    _db.reemplazarAlerta(cerrada);
    return cerrada;
  }

  @override
  Future<List<Alerta>> obtenerHistorial() async {
    await _db.esperar();
    return FiltroHistorial(usuarioId: _db.yo.id).aplicar(_db.alertas);
  }
}
