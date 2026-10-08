// U-09 Confirmación de atención · A-08 Bloqueo por falsas alarmas · 4.5 Transiciones
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/core/utils/alert_rules.dart';
import 'package:safelink/data/models/models.dart';

void main() {
  final now = DateTime(2026, 10, 7, 18);

  Alert alert(AlertStatus s, {String? guardId}) =>
      Alert(id: 'a', userId: 'u', guardId: guardId, status: s, triggerMethod: TriggerMethod.tap, triggeredAt: now);

  group('U-09 canUserConfirm', () {
    test('solo tras la llegada del guardia', () {
      expect(AlertRules.canUserConfirm(alert(AlertStatus.guardArrived, guardId: 'g')), isTrue);
      expect(AlertRules.canUserConfirm(alert(AlertStatus.inProgress, guardId: 'g')), isFalse);
    });

    test('nunca sin guardia asignado', () {
      expect(AlertRules.canUserConfirm(alert(AlertStatus.guardArrived)), isFalse);
    });
  });

  group('Transiciones (4.5)', () {
    test('válidas', () {
      expect(AlertRules.canTransition(AlertStatus.searching, AlertStatus.inProgress), isTrue);
      expect(AlertRules.canTransition(AlertStatus.guardArrived, AlertStatus.escalated), isTrue);
    });

    test('inválidas', () {
      expect(AlertRules.canTransition(AlertStatus.searching, AlertStatus.closed), isFalse);
      expect(AlertRules.canTransition(AlertStatus.closed, AlertStatus.searching), isFalse);
    });
  });

  group('A-08 applyFalseAlarm', () {
    final user = AppUser(id: 'u', name: 'Rosa', email: 'r@m.com', phone: '7772233445', role: UserRole.protectedUser, createdAt: now, falseAlarmCount: 1);

    test('debajo del límite solo incrementa', () {
      final r = AlertRules.applyFalseAlarm(user, now: now, limit: 3, blockDays: 7);
      expect(r.falseAlarmCount, 2);
      expect(r.blockedUntil, isNull);
    });

    test('al llegar al límite bloquea N días', () {
      final r = AlertRules.applyFalseAlarm(user.copyWith(falseAlarmCount: 2), now: now, limit: 3, blockDays: 7);
      expect(r.falseAlarmCount, 3);
      expect(r.blockedUntil, now.add(const Duration(days: 7)));
      expect(r.isBlockedAt(now), isTrue);
    });
  });
}
