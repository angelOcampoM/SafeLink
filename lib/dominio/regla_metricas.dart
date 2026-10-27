// CAPA: DOMINIO — cálculo de métricas
// A-06 Métricas generales · A-07 Métricas por guardia
// Promedios, tasas y alertas por hora. Con 0 alertas todo vale 0 (nunca divide entre 0).
// No hace: no decide el periodo; recibe las alertas ya filtradas.

import 'alerta.dart';
import 'enums.dart';
import 'metricas.dart';

abstract final class ReglaMetricas {
  static MetricasGenerales generales(List<Alerta> alertas) {
    if (alertas.isEmpty) return MetricasGenerales.vacias;

    final porHora = List<int>.filled(24, 0);
    for (final a in alertas) {
      porHora[a.disparadaEn.toLocal().hour]++;
    }

    final sinRespuesta = alertas.where((a) => a.razonEscalamiento == RazonEscalamiento.sinRespuesta).length;
    final cerradas = alertas.where((a) => a.estado == EstadoAlerta.cerrada).length;

    return MetricasGenerales(
      totalAlertas: alertas.length,
      promedioAceptacionSeg: _promedio(alertas, (a) => a.aceptadaEn?.difference(a.disparadaEn)),
      promedioLlegadaSeg: _promedio(alertas, (a) => a.llegadaEn?.difference(a.aceptadaEn ?? a.disparadaEn)),
      tasaSinRespuesta: sinRespuesta / alertas.length,
      tasaCierreConfirmado: cerradas / alertas.length,
      alertasPorHora: porHora,
    );
  }

  static MetricasGuardia deGuardia(String guardiaId, List<Alerta> alertas) {
    final mias = alertas.where((a) => a.guardiaId == guardiaId).toList();
    return MetricasGuardia(
      atendidas: mias.where((a) => a.llegadaEn != null).length,
      promedioAceptacionSeg: _promedio(mias, (a) => a.aceptadaEn?.difference(a.disparadaEn)),
      promedioLlegadaSeg: _promedio(mias, (a) => a.llegadaEn?.difference(a.aceptadaEn ?? a.disparadaEn)),
      escaladas: mias.where((a) => a.razonEscalamiento != null).length,
    );
  }

  static double _promedio(List<Alerta> alertas, Duration? Function(Alerta) tomar) {
    final valores = alertas.map(tomar).whereType<Duration>().toList();
    if (valores.isEmpty) return 0;
    return valores.fold<int>(0, (s, d) => s + d.inSeconds) / valores.length;
  }
}
