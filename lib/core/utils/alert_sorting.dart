import '../../data/models/alert.dart';
import '../../data/models/geo_point.dart';
import 'geo_utils.dart';

/// Alerta + datos calculados para el listado del guardia (G-03).
class RankedAlert {
  const RankedAlert(this.alert, this.distanceMeters, this.waitingMinutes, this.score);
  final Alert alert;
  final double distanceMeters;
  final double waitingMinutes;
  final double score;
}

/// Orden del listado del guardia (sección 6.3, provisional):
/// 1. Primero las de agitación (urgentes).
/// 2. Después, menor `score = distancia − minutosEspera × metrosPorMinuto`.
List<RankedAlert> rankAlertsForGuard({
  required List<Alert> alerts,
  required GeoPoint guardLocation,
  required DateTime now,
  int metersPerWaitingMinute = 100,
}) {
  final ranked = alerts.where((a) => a.location != null).map((a) {
    final d = GeoUtils.distanceMeters(guardLocation, a.location!);
    final w = now.difference(a.triggeredAt).inSeconds / 60.0;
    return RankedAlert(a, d, w, d - w * metersPerWaitingMinute);
  }).toList();

  ranked.sort((x, y) {
    if (x.alert.isUrgent != y.alert.isUrgent) return x.alert.isUrgent ? -1 : 1;
    return x.score.compareTo(y.score);
  });
  return ranked;
}
