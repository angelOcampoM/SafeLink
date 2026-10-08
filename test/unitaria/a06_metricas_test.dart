// A-06 Métricas generales · A-07 Métricas por guardia.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/core/utils/metrics_calculator.dart';
import 'package:safelink/data/models/models.dart';

void main() {
  final t = DateTime(2026, 10, 7, 21, 0);

  test('con cero alertas todo vale 0 (sin dividir entre cero)', () {
    final m = MetricsCalculator.general([]);
    expect(m.totalAlerts, 0);
    expect(m.avgAcceptanceSeconds, 0);
    expect(m.noResponseRate, 0);
    expect(m.alertsByHour.length, 24);
  });

  test('promedios, tasas y conteo por hora', () {
    final alerts = [
      Alert(id: '1', userId: 'u', guardId: 'g1', status: AlertStatus.closed, triggerMethod: TriggerMethod.tap, triggeredAt: t, acceptedAt: t.add(const Duration(seconds: 60)), arrivedAt: t.add(const Duration(seconds: 360))),
      Alert(id: '2', userId: 'u', guardId: 'g1', status: AlertStatus.closed, triggerMethod: TriggerMethod.tap, triggeredAt: t, acceptedAt: t.add(const Duration(seconds: 120)), arrivedAt: t.add(const Duration(seconds: 720))),
      Alert(id: '3', userId: 'u', status: AlertStatus.escalated, escalationReason: EscalationReason.noResponse, triggerMethod: TriggerMethod.tap, triggeredAt: t),
    ];
    final m = MetricsCalculator.general(alerts);
    expect(m.avgAcceptanceSeconds, 90);
    expect(m.avgArrivalSeconds, 450);
    expect(m.noResponseRate, closeTo(1 / 3, 0.001));
    expect(m.confirmedCloseRate, closeTo(2 / 3, 0.001));
    expect(m.alertsByHour[21], 3);

    final g = MetricsCalculator.forGuard('g1', alerts);
    expect(g.attendedCount, 2);
    expect(g.escalatedCount, 0);
  });
}
