// CAPA: DOMINIO — métricas de operación (sección 7)
// A-06 Métricas generales · A-07 Métricas por guardia
// Solo los valores; el cálculo vive en ReglaMetricas.

/// Conteo de alertas de una zona de cobertura (A-06).
typedef ZonaConteo = ({String zona, int total});

class MetricasGenerales {
  const MetricasGenerales({
    required this.totalAlertas,
    required this.promedioAceptacionSeg,
    required this.promedioLlegadaSeg,
    required this.tasaSinRespuesta,
    required this.tasaCierreConfirmado,
    required this.alertasPorHora,
    required this.alertasPorZona,
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

  /// Alertas agrupadas por la zona de cobertura del guardia que las atendió
  /// (A-06). Más frecuentes primero; las sin guardia o sin zona caen en
  /// 'Sin zona asignada'.
  final List<ZonaConteo> alertasPorZona;

  static const vacias = MetricasGenerales(
    totalAlertas: 0,
    promedioAceptacionSeg: 0,
    promedioLlegadaSeg: 0,
    tasaSinRespuesta: 0,
    tasaCierreConfirmado: 0,
    alertasPorHora: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    alertasPorZona: [],
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
