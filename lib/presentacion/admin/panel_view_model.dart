// CAPA: PRESENTACIÓN — ViewModel
// A-06 Métricas generales (periodos 7 / 30 / 90 días o rango personalizado)
// · A-08 Usuarios bloqueados.
// Recalcula las métricas al cambiar de periodo/rango y orquesta el desbloqueo.
// No importa material.dart; el cálculo vive en ReglaMetricas (vía repositorio).

import '../../datos/admin_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';
import '../sesion/sesion_view_model.dart';

enum PeriodoPanel {
  dias7(7, '7 días'),
  dias30(30, '30 días'),
  dias90(90, '90 días');

  const PeriodoPanel(this.dias, this.etiqueta);
  final int dias;
  final String etiqueta;
}

class PanelViewModel extends ViewModel {
  PanelViewModel(this._admin, this._sesion, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AdminRepository _admin;
  final SesionViewModel _sesion;
  final DateTime Function() _reloj;

  /// `null` cuando se usa un rango personalizado (A-06).
  PeriodoPanel? periodo = PeriodoPanel.dias30;

  /// Rango personalizado; `null` cuando se usa un periodo de chips.
  DateTime? desde;
  DateTime? hasta;

  EstadoVista<MetricasGenerales> metricas = const Cargando();
  EstadoVista<List<Usuario>> bloqueados = const Cargando();
  String? mensaje;

  DateTime get ahora => _reloj();

  Future<void> cargar() => Future.wait([_cargarMetricas(), _cargarBloqueados()]);

  Future<void> cambiarPeriodo(PeriodoPanel nuevo) async {
    if (nuevo == periodo) return;
    periodo = nuevo;
    desde = null;
    hasta = null;
    metricas = const Cargando();
    notifyListeners();
    await _cargarMetricas();
  }

  /// A-06: rango de fechas elegido en el calendario. El picker entrega el
  /// último día a medianoche, así que se cierra al final de ese día.
  Future<void> cambiarRango(DateTime inicio, DateTime fin) async {
    periodo = null;
    desde = inicio;
    hasta = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
    metricas = const Cargando();
    notifyListeners();
    await _cargarMetricas();
  }

  Future<void> limpiarRango() => cambiarPeriodo(PeriodoPanel.dias30);

  Future<void> _cargarMetricas() async {
    final ahora = _reloj();
    try {
      final m = await _admin.obtenerMetricas(
        desde: desde ?? ahora.subtract(Duration(days: periodo?.dias ?? PeriodoPanel.dias30.dias)),
        hasta: hasta ?? ahora,
      );
      metricas = m.totalAlertas == 0 ? const Vacio() : Listo(m);
    } catch (e) {
      metricas = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<void> _cargarBloqueados() async {
    try {
      bloqueados = EstadoVista.deLista(await _admin.obtenerUsuariosBloqueados());
    } catch (e) {
      bloqueados = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }

  Future<void> desbloquear(Usuario u) async {
    try {
      await _admin.desbloquearUsuario(u.id);
      mensaje = 'Se retiró el bloqueo de ${u.nombre}';
      await _cargarBloqueados();
    } catch (e) {
      mensaje = ViewModel.mensajeDe(e);
      notifyListeners();
    }
  }

  Future<void> cerrarSesion() => _sesion.cerrarSesion();

  void consumirMensaje() => mensaje = null;
}
