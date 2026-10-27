// CAPA: PRESENTACIÓN — ViewModel
// Historial de alertas atendidas por el guardia + métricas personales (A-07 desde su lado)
// Carga ambas cosas en un solo EstadoVista. No importa material.dart.

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

typedef HistorialGuardia = ({List<Alerta> alertas, MetricasGuardia metricas});

class HistorialGuardiaViewModel extends ViewModel {
  HistorialGuardiaViewModel(this._alertas, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final DateTime Function() _reloj;

  EstadoVista<HistorialGuardia> estado = const Cargando();

  DateTime get ahora => _reloj();

  Future<void> cargar() async {
    if (estado is! Listo) {
      estado = const Cargando();
      notifyListeners();
    }
    try {
      final r = await Future.wait<Object>([_alertas.obtenerMiHistorial(), _alertas.obtenerMisMetricas()]);
      final alertas = r[0] as List<Alerta>;
      estado = alertas.isEmpty ? const Vacio() : Listo((alertas: alertas, metricas: r[1] as MetricasGuardia));
    } catch (e) {
      estado = ErrorVista(ViewModel.mensajeDe(e));
    }
    notifyListeners();
  }
}
