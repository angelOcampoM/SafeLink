// CAPA: DOMINIO — filtros del historial del guardia
// G-03 Historial de alertas atendidas con filtros (rango de fechas, resultado y método de disparo)
// Reutiliza FiltroHistorial para fechas y estado, y agrega el método de disparo.
// Rango [desde, hasta): quien arma el filtro decide si `hasta` incluye el último día.
// No hace: no busca alertas; se aplica en memoria sobre el historial ya cargado.

import 'alerta.dart';
import 'enums.dart';
import 'filtro_historial.dart';

class FiltroMiHistorial {
  const FiltroMiHistorial({this.desde, this.hasta, this.estado, this.metodo});

  final DateTime? desde;
  final DateTime? hasta;
  final EstadoAlerta? estado;
  final MetodoDisparo? metodo;

  bool get hayFiltros => desde != null || hasta != null || estado != null || metodo != null;

  FiltroHistorial get _base => FiltroHistorial(desde: desde, hasta: hasta, estado: estado);

  bool cumple(Alerta a) => _base.cumple(a) && (metodo == null || a.metodo == metodo);

  /// Más recientes primero (igual que FiltroHistorial).
  List<Alerta> aplicar(Iterable<Alerta> alertas) => _base.aplicar(alertas.where((a) => metodo == null || a.metodo == metodo));

  /// Estados que de verdad aparecen en el historial, en el orden del enum.
  static List<EstadoAlerta> estadosPresentes(Iterable<Alerta> alertas) {
    final presentes = {for (final a in alertas) a.estado};
    return [for (final e in EstadoAlerta.values) if (presentes.contains(e)) e];
  }
}
