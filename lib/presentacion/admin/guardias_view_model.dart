// CAPA: PRESENTACIÓN — ViewModel
// A-01 Alta · A-02 Edición y baja · A-03 Turnos y radios · A-07 Métricas por guardia
// Búsqueda, listado, métricas del guardia seleccionado y baja lógica.
// No importa material.dart; la disponibilidad la decide el dominio.

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

class GuardiasViewModel extends ViewModel {
  GuardiasViewModel(this._admin, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AdminRepository _admin;
  final DateTime Function() _reloj;

  String busqueda = '';
  EstadoVista<List<Guardia>> estado = const Cargando();
  EstadoVista<MetricasGuardia> metricasSeleccion = const Cargando();
  String? mensaje;

  var _peticion = 0;

  DateTime get ahora => _reloj();

  Future<void> cargar() async {
    final mia = ++_peticion;
    if (estado is! Listo) {
      estado = const Cargando();
      notifyListeners();
    }
    try {
      final lista = await _admin.obtenerGuardias(busqueda: busqueda);
      if (mia != _peticion) return; // llegó una búsqueda más nueva
      estado = EstadoVista.deLista(lista);
    } catch (e) {
      if (mia != _peticion) return;
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<void> buscar(String texto) {
    busqueda = texto;
    return cargar();
  }

  /// Etiqueta de estado del guardia para su chip.
  ({String etiqueta, bool activo, bool enTurno}) estadoDe(Guardia g) =>
      (etiqueta: !g.usuario.activo ? 'Dado de baja' : g.disponibleA(ahora) ? 'En turno' : 'Fuera de turno', activo: g.usuario.activo, enTurno: g.disponibleA(ahora));

  Future<void> seleccionar(Guardia g) async {
    metricasSeleccion = const Cargando();
    notifyListeners();
    try {
      metricasSeleccion = Listo(await _admin.obtenerMetricasGuardia(g.usuario.id));
    } catch (e) {
      metricasSeleccion = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<bool> darDeBaja(Guardia g) async {
    try {
      await _admin.darDeBajaGuardia(g.usuario.id);
      mensaje = '${g.usuario.nombre} quedó dado de baja';
      await cargar();
      return true;
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
      notifyListeners();
      return false;
    }
  }

  void consumirMensaje() => mensaje = null;
}
