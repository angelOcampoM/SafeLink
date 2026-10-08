import '../../data/models/alert.dart';
import '../../data/models/enums.dart';
import '../../data/models/metrics.dart';

/// Cálculo de métricas (A-06, A-07). Con cero alertas todo vale 0.
abstract final class MetricsCalculator {
  static GeneralMetrics general(List<Alert> alerts) {
    if (alerts.isEmpty) return GeneralMetrics.empty;

    final byHour = List<int>.filled(24, 0);
    for (final a in alerts) {
      byHour[a.triggeredAt.toLocal().hour]++;
    }

    final noResponse = alerts.where((a) => a.escalationReason == EscalationReason.noResponse).length;
    final closed = alerts.where((a) => a.status == AlertStatus.closed).length;

    return GeneralMetrics(
      totalAlerts: alerts.length,
      avgAcceptanceSeconds: _avg(alerts, (a) => a.acceptedAt?.difference(a.triggeredAt)),
      avgArrivalSeconds: _avg(alerts, (a) => a.arrivedAt?.difference(a.acceptedAt ?? a.triggeredAt)),
      noResponseRate: noResponse / alerts.length,
      confirmedCloseRate: closed / alerts.length,
      alertsByHour: byHour,
    );
  }

  static GuardMetrics forGuard(String guardId, List<Alert> alerts) {
    final mine = alerts.where((a) => a.guardId == guardId).toList();
    return GuardMetrics(
      attendedCount: mine.where((a) => a.arrivedAt != null).length,
      avgAcceptanceSeconds: _avg(mine, (a) => a.acceptedAt?.difference(a.triggeredAt)),
      avgArrivalSeconds: _avg(mine, (a) => a.arrivedAt?.difference(a.acceptedAt ?? a.triggeredAt)),
      escalatedCount: mine.where((a) => a.escalationReason != null).length,
    );
  }

  static double _avg(List<Alert> alerts, Duration? Function(Alert) pick) {
    final values = alerts.map(pick).whereType<Duration>().toList();
    if (values.isEmpty) return 0;
    return values.fold<int>(0, (s, d) => s + d.inSeconds) / values.length;
  }
}
