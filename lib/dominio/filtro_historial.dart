// CAPA: DOMINIO — criterio de búsqueda del historial
// A-05 Historial con filtros (también lo usan los historiales de usuario y guardia)
// Filtros combinables (rango de fechas, guardia, usuario, estado) y la regla de
// cuándo una alerta los cumple. Rango [desde, hasta).
// No hace: no busca nada; el repositorio lo aplica sobre sus datos.

import 'alerta.dart';
import 'enums.dart';

class FiltroHistorial {
  const FiltroHistorial({this.desde, this.hasta, this.guardiaId, this.usuarioId, this.estado});

  final DateTime? desde;
  final DateTime? hasta;
  final String? guardiaId;
  final String? usuarioId;
  final EstadoAlerta? estado;

  bool cumple(Alerta a) =>
      (desde == null || !a.disparadaEn.isBefore(desde!)) &&
      (hasta == null || a.disparadaEn.isBefore(hasta!)) &&
      (guardiaId == null || a.guardiaId == guardiaId) &&
      (usuarioId == null || a.usuarioId == usuarioId) &&
      (estado == null || a.estado == estado);

  /// Más recientes primero.
  List<Alerta> aplicar(Iterable<Alerta> alertas) =>
      alertas.where(cumple).toList()..sort((a, b) => b.disparadaEn.compareTo(a.disparadaEn));
}
