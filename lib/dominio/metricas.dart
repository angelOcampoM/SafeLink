// CAPA: DOMINIO — métricas de operación (sección 7)
// A-06 Métricas generales · A-07 Métricas por guardia
// Solo los valores; el cálculo vive en ReglaMetricas.

class MetricasGenerales {
  const MetricasGenerales({
    required this.totalAlertas,
    required this.promedioAceptacionSeg,
    required this.promedioLlegadaSeg,
    required this.tasaSinRespuesta,
    required this.tasaCierreConfirmado,
    required this.alertasPorHora,
  });

  final int totalAlertas;
  final double promedioAceptacionSeg;
  final double promedioLlegadaSeg;

  /// 0.0 – 1.0
  final double tasaSinRespuesta;

  /// 0.0 – 1.0
  final double tasaCierreConfirmado;

  /// Exactamente 24 posiciones (0 = 00:00–00:59, hora local).
  final List<int> alertasPorHora;

  static const vacias = MetricasGenerales(
    totalAlertas: 0,
    promedioAceptacionSeg: 0,
    promedioLlegadaSeg: 0,
    tasaSinRespuesta: 0,
    tasaCierreConfirmado: 0,
    alertasPorHora: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  );
}

class MetricasGuardia {
  const MetricasGuardia({
    required this.atendidas,
    required this.promedioAceptacionSeg,
    required this.promedioLlegadaSeg,
    required this.escaladas,
  });

  final int atendidas;
  final double promedioAceptacionSeg;
  final double promedioLlegadaSeg;
  final int escaladas;

  static const vacias = MetricasGuardia(atendidas: 0, promedioAceptacionSeg: 0, promedioLlegadaSeg: 0, escaladas: 0);
}
