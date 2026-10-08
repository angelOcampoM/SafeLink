import '../../data/models/alert.dart';
import '../../data/models/enums.dart';
import '../../data/models/user.dart';

/// Reglas de negocio puras (secciones 4.5, 6.5 y 6.6).
abstract final class AlertRules {
  static const _transitions = <AlertStatus, Set<AlertStatus>>{
    AlertStatus.pendingLocation: {AlertStatus.searching},
    AlertStatus.searching: {AlertStatus.inProgress, AlertStatus.noResponse},
    AlertStatus.noResponse: {AlertStatus.escalated},
    AlertStatus.inProgress: {AlertStatus.guardArrived},
    AlertStatus.guardArrived: {AlertStatus.closed, AlertStatus.escalated},
    AlertStatus.escalated: {AlertStatus.resolvedByAdmin},
    AlertStatus.closed: {},
    AlertStatus.resolvedByAdmin: {},
  };

  static bool canTransition(AlertStatus from, AlertStatus to) => _transitions[from]!.contains(to);

  /// U-09: solo el usuario cierra, solo con guardia asignado y ya llegado.
  static bool canUserConfirm(Alert a) => a.status == AlertStatus.guardArrived && a.guardId != null;

  /// A-08: aplica una resolución de falsa alarma al usuario.
  static AppUser applyFalseAlarm(
    AppUser user, {
    required DateTime now,
    required int limit,
    required int blockDays,
  }) {
    final count = user.falseAlarmCount + 1;
    return user.copyWith(
      falseAlarmCount: count,
      blockedUntil: count >= limit ? now.add(Duration(days: blockDays)) : null,
    );
  }
}
