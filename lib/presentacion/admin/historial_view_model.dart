// CAPA: PRESENTACIÓN — ViewModel
// A-05 Historial con filtros (rango de fechas, guardia y estado, combinables)
// Arma un FiltroHistorial (dominio) con lo que elige el admin y pide el
// historial al repositorio. No importa material.dart.

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class HistorialViewModel extends ViewModel {
  HistorialViewModel(this._admin, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AdminRepository _admin;
  final DateTime Function() _reloj;

  /// Días completos, inclusivos (la View los toma de un DateRangePicker).
  DateTime? desde;
  DateTime? hasta;
  String? guardiaId;
  EstadoAlerta? estadoFiltro;

  List<Guardia> guardias = const [];
  EstadoVista<List<Alerta>> estado = const Cargando();

  var _peticion = 0;

  DateTime get ahora => _reloj();
  bool get hayFiltros => desde != null || guardiaId != null || estadoFiltro != null;
  String? get nombreGuardia => guardias.where((g) => g.usuario.id == guardiaId).firstOrNull?.usuario.nombre;

  FiltroHistorial get filtro => FiltroHistorial(
        desde: desde,
        // `hasta` es exclusivo en el dominio: se suma un día para incluir el último.
        hasta: hasta?.add(const Duration(days: 1)),
        guardiaId: guardiaId,
        estado: estadoFiltro,
      );

  Future<void> iniciar() async {
    try {
      guardias = await _admin.obtenerGuardias();
    } catch (_) {
      guardias = const []; // el filtro de guardia queda vacío; el historial igual carga
    }
    await cargar();
  }

  Future<void> cargar() async {
    final mia = ++_peticion;
    estado = const Cargando();
    notifyListeners();
    try {
      final lista = await _admin.obtenerHistorial(filtro);
      if (mia != _peticion) return;
      estado = EstadoVista.deLista(lista);
    } catch (e) {
      if (mia != _peticion) return;
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<void> cambiarRango(DateTime? inicio, DateTime? fin) {
    desde = inicio == null ? null : DateTime(inicio.year, inicio.month, inicio.day);
    hasta = fin == null ? null : DateTime(fin.year, fin.month, fin.day);
    return cargar();
  }

  Future<void> cambiarGuardia(String? id) {
    guardiaId = id;
    return cargar();
  }

  Future<void> cambiarEstado(EstadoAlerta? e) {
    estadoFiltro = e;
    return cargar();
  }

  Future<void> limpiarFiltros() {
    desde = null;
    hasta = null;
    guardiaId = null;
    estadoFiltro = null;
    return cargar();
  }
}
