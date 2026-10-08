import '../models/models.dart';

class AlertHistoryFilter {
  const AlertHistoryFilter({this.from, this.to, this.guardId, this.userId, this.status});
  final DateTime? from;
  final DateTime? to;
  final String? guardId;
  final String? userId;
  final AlertStatus? status;
}

/// Administración (A-01 a A-08).
abstract interface class AdminRepository {
  /// `GET /admin/guards?search=` (incluye dados de baja al final).
  Future<List<Guard>> getGuards({String search = ''});

  /// `POST /admin/guards`
  Future<Guard> createGuard({required String name, required String email, required String phone});

  /// `PATCH /admin/guards/{id}`
  Future<Guard> updateGuard(String guardId, {String? name, String? email, String? phone});

  /// `DELETE /admin/guards/{id}` — baja lógica.
  Future<void> deactivateGuard(String guardId);

  /// `PUT /admin/guards/{id}/coverage`
  Future<Guard> updateCoverage(
    String guardId, {
    required String shiftStart,
    required String shiftEnd,
    required GeoPoint center,
    required int radiusMeters,
  });

  /// `GET /admin/alerts/escalated`
  Stream<List<Alert>> watchEscalatedAlerts();

  /// `POST /admin/alerts/{id}/resolve`
  Future<Alert> resolveAlert(String alertId, Resolution resolution);

  /// `GET /admin/alerts?...`
  Future<List<Alert>> getHistory(AlertHistoryFilter filter);

  /// `GET /admin/metrics`
  Future<GeneralMetrics> getMetrics({DateTime? from, DateTime? to});

  /// `GET /admin/metrics/guards/{id}`
  Future<GuardMetrics> getGuardMetrics(String guardId, {DateTime? from, DateTime? to});

  /// `GET /admin/users/blocked`
  Future<List<AppUser>> getBlockedUsers();

  /// `DELETE /admin/users/{id}/block`
  Future<void> unblockUser(String userId);
}
