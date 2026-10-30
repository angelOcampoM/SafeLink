// CAPA: PRESENTACIÓN — ViewModel
// A-07 Métricas por guardia (filtro por rango de fechas)
// Pide al repositorio las métricas de UN guardia, con rango opcional, y
// traduce el resultado a los cuatro estados de vista. No importa material.dart.

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class MetricasGuardiaViewModel extends ViewModel {
  MetricasGuardiaViewModel(this._admin, this.guardiaId, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AdminRepository _admin;
  final String guardiaId;
  final DateTime Function() _reloj;

  String nombreGuardia = '';
  EstadoVista<MetricasGuardia> estado = const Cargando();

  /// Días completos, inclusivos (la View los toma de un DateRangePicker).
  DateTime? desde;
  DateTime? hasta;

  var _peticion = 0;

  DateTime get ahora => _reloj();

  Future<void> iniciar() async {
    try {
      nombreGuardia = (await _admin.obtenerGuardia(guardiaId)).usuario.nombre;
    } catch (_) {
      nombreGuardia = 'Guardia'; // el título genérico; las métricas igual cargan
    }
    await cargar();
  }

  Future<void> cargar() async {
    final mia = ++_peticion;
    estado = const Cargando();
    notifyListeners();
    try {
      final m = await _admin.obtenerMetricasGuardia(
        guardiaId,
        desde: desde,
        // `hasta` es exclusivo en el dominio: se suma un día para incluir el último.
        hasta: hasta?.add(const Duration(days: 1)),
      );
      if (mia != _peticion) return; // llegó una recarga más nueva
      estado = _sinDatos(m) ? const Vacio() : Listo(m);
    } catch (e) {
      if (mia != _peticion) return;
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  bool _sinDatos(MetricasGuardia m) =>
      m.atendidas == 0 && m.escaladas == 0 && m.promedioAceptacionSeg == 0 && m.promedioLlegadaSeg == 0;

  Future<void> cambiarRango(DateTime? inicio, DateTime? fin) {
    desde = inicio == null ? null : DateTime(inicio.year, inicio.month, inicio.day);
    hasta = fin == null ? null : DateTime(fin.year, fin.month, fin.day);
    return cargar();
  }

  Future<void> limpiarRango() {
    desde = null;
    hasta = null;
    return cargar();
  }
}
