// CAPA: PRESENTACIÓN — ViewModel
// Historial de alertas atendidas por el guardia + métricas personales (A-07 desde su lado)
// G-03 Filtros del historial: rango de fechas, resultado y método de disparo, aplicados en memoria.
// Carga historial y métricas en un solo EstadoVista y filtra con FiltroMiHistorial (dominio).
// No importa material.dart y no cambia el contrato: pide la lista completa una vez.

import '../../datos/alerta_guardia_repository.dart';
import '../../dominio/dominio.dart';
import '../comun/estado_vista.dart';
import '../comun/view_model.dart';

typedef HistorialGuardia = ({List<Alerta> alertas, MetricasGuardia metricas});

/// Resumen de lo que se ve con los filtros aplicados.
typedef ResumenHistorial = ({int conteo, double promedioLlegadaSeg});

class HistorialGuardiaViewModel extends ViewModel {
  HistorialGuardiaViewModel(this._alertas, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final AlertaGuardiaRepository _alertas;
  final DateTime Function() _reloj;

  /// Historial COMPLETO (sin filtrar) y métricas. Vacío = aún no atiende alertas.
  EstadoVista<HistorialGuardia> estado = const Cargando();

  /// Días completos, inclusivos (la View los toma de un DateRangePicker).
  DateTime? desde;
  DateTime? hasta;
  EstadoAlerta? estadoFiltro;
  MetodoDisparo? metodo;

  DateTime get ahora => _reloj();
  bool get hayFiltros => filtro.hayFiltros;

  FiltroMiHistorial get filtro => FiltroMiHistorial(
        desde: desde,
        // `hasta` es exclusivo en el dominio: se suma un día para incluir el último.
        hasta: hasta?.add(const Duration(days: 1)),
        estado: estadoFiltro,
        metodo: metodo,
      );

  List<Alerta> get _todas => estado.datos?.alertas ?? const [];

  /// Lo que se ve en la lista, más recientes primero.
  List<Alerta> get filtradas => filtro.aplicar(_todas);

  /// Resultados que aparecen en el historial (para los chips de "resultado").
  List<EstadoAlerta> get estadosDisponibles => FiltroMiHistorial.estadosPresentes(_todas);

  ResumenHistorial get resumen {
    final l = filtradas;
    return (conteo: l.length, promedioLlegadaSeg: ReglaMetricas.generales(l).promedioLlegadaSeg);
  }

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

  void cambiarRango(DateTime? inicio, DateTime? fin) {
    desde = inicio == null ? null : DateTime(inicio.year, inicio.month, inicio.day);
    hasta = fin == null ? null : DateTime(fin.year, fin.month, fin.day);
    notifyListeners();
  }

  void cambiarEstado(EstadoAlerta? e) {
    estadoFiltro = e;
    notifyListeners();
  }

  void cambiarMetodo(MetodoDisparo? m) {
    metodo = m;
    notifyListeners();
  }

  void limpiarFiltros() {
    desde = null;
    hasta = null;
    estadoFiltro = null;
    metodo = null;
    notifyListeners();
  }
}
