// G-03 Listado por cercanía y prioridad (sección 6.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/core/utils/alert_sorting.dart';
import 'package:safelink/data/models/models.dart';

void main() {
  final now = DateTime(2026, 10, 7, 18, 0);
  const guard = GeoPoint(18.8400, -99.1800);

  Alert alert(String id, double dLat, int minutesAgo, {TriggerMethod m = TriggerMethod.tap}) => Alert(
        id: id,
        userId: 'u',
        status: AlertStatus.searching,
        triggerMethod: m,
        triggeredAt: now.subtract(Duration(minutes: minutesAgo)),
        location: GeoPoint(guard.lat + dLat, guard.lng),
      );

  test('las de agitación van primero aunque estén más lejos', () {
    final ranked = rankAlertsForGuard(
      alerts: [alert('cerca', 0.001, 0), alert('lejos-shake', 0.02, 0, m: TriggerMethod.shake)],
      guardLocation: guard,
      now: now,
    );
    expect(ranked.map((r) => r.alert.id), ['lejos-shake', 'cerca']);
  });

  test('cada minuto de espera equivale a 100 m más cerca', () {
    // A: ~555 m, 0 min → score 555. B: ~888 m, 5 min → score 388.
    final ranked = rankAlertsForGuard(
      alerts: [alert('A', 0.005, 0), alert('B', 0.008, 5)],
      guardLocation: guard,
      now: now,
    );
    expect(ranked.first.alert.id, 'B');
  });

  test('ignora alertas sin ubicación', () {
    final sinUbicacion = Alert(
      id: 'x',
      userId: 'u',
      status: AlertStatus.pendingLocation,
      triggerMethod: TriggerMethod.tap,
      triggeredAt: now,
    );
    expect(rankAlertsForGuard(alerts: [sinUbicacion], guardLocation: guard, now: now), isEmpty);
  });
}
