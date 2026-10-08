/// Sección 7, "Métricas".
class GeneralMetrics {
  const GeneralMetrics({
    required this.totalAlerts,
    required this.avgAcceptanceSeconds,
    required this.avgArrivalSeconds,
    required this.noResponseRate,
    required this.confirmedCloseRate,
    required this.alertsByHour,
  });

  final int totalAlerts;
  final double avgAcceptanceSeconds;
  final double avgArrivalSeconds;

  /// 0.0 – 1.0
  final double noResponseRate;

  /// 0.0 – 1.0
  final double confirmedCloseRate;

  /// Exactamente 24 posiciones (0 = 00:00–00:59, hora local).
  final List<int> alertsByHour;

  static const empty = GeneralMetrics(
    totalAlerts: 0,
    avgAcceptanceSeconds: 0,
    avgArrivalSeconds: 0,
    noResponseRate: 0,
    confirmedCloseRate: 0,
    alertsByHour: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  );
}

class GuardMetrics {
  const GuardMetrics({
    required this.attendedCount,
    required this.avgAcceptanceSeconds,
    required this.avgArrivalSeconds,
    required this.escalatedCount,
  });

  final int attendedCount;
  final double avgAcceptanceSeconds;
  final double avgArrivalSeconds;
  final int escalatedCount;
}
