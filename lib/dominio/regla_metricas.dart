// CAPA: DOMINIO — cálculo de métricas
// A-06 Métricas generales · A-07 Métricas por guardia
// Promedios, tasas, alertas por hora y por zona. Con 0 alertas todo vale 0
// (nunca divide entre 0).
// No hace: no decide el periodo; recibe las alertas ya filtradas.

import 'alerta.dart';
import 'enums.dart';
import 'metricas.dart';

abstract final class ReglaMetricas {
  /// Etiqueta de las alertas sin guardia o cuyo guardia no tiene zona (A-06).
  static const sinZona = 'Sin zona asignada';

  /// A-06: [zonasPorGuardia] mapea guardiaId -> nombre de su zona de cobertura.
  static MetricasGenerales generales(List<Alerta> alertas, {Map<String, String> zonasPorGuardia = const {}}) {
    if (alertas.isEmpty) return MetricasGenerales.vacias;

    final porHora = List<int>.filled(24, 0);
    final porZona = <String, int>{};
    for (final a in alertas) {
      porHora[a.disparadaEn.toLocal().hour]++;
      final zona = a.guardiaId == null ? null : zonasPorGuardia[a.guardiaId];
      final clave = (zona == null || zona.trim().isEmpty) ? sinZona : zona;
      porZona[clave] = (porZona[clave] ?? 0) + 1;
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
      alertasPorZona: _porZonaOrdenado(porZona),
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

  static List<ZonaConteo> _porZonaOrdenado(Map<String, int> porZona) {
    final lista = [for (final e in porZona.entries) (zona: e.key, total: e.value)];
    lista.sort((a, b) => b.total != a.total ? b.total - a.total : a.zona.compareTo(b.zona));
    return lista;
  }

  static double _promedio(List<Alerta> alertas, Duration? Function(Alerta) tomar) {
    final valores = alertas.map(tomar).whereType<Duration>().toList();
    if (valores.isEmpty) return 0;
    return valores.fold<int>(0, (s, d) => s + d.inSeconds) / valores.length;
  }
}
