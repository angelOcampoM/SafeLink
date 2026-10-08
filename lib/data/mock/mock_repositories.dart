import '../../core/utils/alert_rules.dart';
import '../../core/utils/alert_sorting.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/metrics_calculator.dart';
import '../models/models.dart';
import '../repositories/admin_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/guard_alert_repository.dart';
import '../repositories/repository_exceptions.dart';
import '../repositories/user_alert_repository.dart';
import 'mock_backend.dart';

// ═════════════════════════════════════════════════════════════════════
// Auth
// ═════════════════════════════════════════════════════════════════════
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._db);
  final MockBackend _db;

  @override
  AppUser? get currentUser => _db.currentUserId == null ? null : _db.me;

  @override
  Future<AppUser> login({required String email, required String password}) async {
    await _db.delay();
    final user = _db.users.values.where((u) => u.email.toLowerCase() == email.trim().toLowerCase()).firstOrNull;
    if (user == null || _db.passwords[user.id] != password || !user.isActive) {
      throw const InvalidCredentialsException();
    }
    _db.currentUserId = user.id;
    return user;
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _db.delay();
    if (_db.users.values.any((u) => u.email.toLowerCase() == email.trim().toLowerCase())) {
      throw const EmailTakenException();
    }
    final user = AppUser(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim(),
      role: UserRole.protectedUser,
      createdAt: DateTime.now(),
    );
    _db.users[user.id] = user;
    _db.passwords[user.id] = password;
    _db.currentUserId = user.id;
    return user;
  }

  @override
  Future<void> logout() async {
    _db.currentUserId = null;
  }

  @override
  Future<AppUser> refreshMe() async {
    await _db.delay();
    return _db.me;
  }

  @override
  Future<AppUser> updateSettings({required bool shakeEnabled}) async {
    await _db.delay();
    final updated = _db.me.copyWith(shakeEnabled: shakeEnabled);
    _db.users[updated.id] = updated;
    return updated;
  }
}

// ═════════════════════════════════════════════════════════════════════
// Usuario protegido
// ═════════════════════════════════════════════════════════════════════
class MockUserAlertRepository implements UserAlertRepository {
  MockUserAlertRepository(this._db);
  final MockBackend _db;

  @override
  Future<Alert> createAlert({
    required TriggerMethod triggerMethod,
    required DateTime triggeredAt,
    GeoPoint? location,
    int? heading,
    String? photoPath,
  }) async {
    await _db.delay();
    final me = _db.me;
    if (me.isBlockedAt(DateTime.now())) throw const UserBlockedException();

    final alert = Alert(
      id: 'alt-${DateTime.now().millisecondsSinceEpoch}',
      userId: me.id,
      userName: me.name,
      userPhone: me.phone,
      status: location == null ? AlertStatus.pendingLocation : AlertStatus.searching,
      triggerMethod: triggerMethod,
      triggeredAt: triggeredAt,
      location: location,
      heading: heading,
      photoUrl: photoPath == null ? null : 'https://picsum.photos/seed/${me.id}/640/420',
      evidenceIncomplete: photoPath == null,
    );
    _db.alerts.add(alert);
    _db.notify();
    if (alert.status == AlertStatus.searching) _db.simulateGuardResponse(alert.id);
    return alert;
  }

  @override
  Stream<Alert?> watchActiveAlert() {
    final userId = _db.me.id;
    return _db.watch(() => _db.alerts.where((a) => a.userId == userId && a.status.isActive).lastOrNull);
  }

  @override
  Future<void> sendLocation(String alertId, GeoPoint location) async {
    final a = _db.alertById(alertId);
    if (a.status == AlertStatus.pendingLocation) {
      _db.replaceAlert(a.copyWith(status: AlertStatus.searching, location: location));
      _db.simulateGuardResponse(alertId);
    } else {
      _db.replaceAlert(a.copyWith(location: location));
    }
  }

  @override
  Future<Alert> confirmAttention(String alertId) async {
    await _db.delay();
    final a = _db.alertById(alertId);
    if (!AlertRules.canUserConfirm(a)) {
      throw const InvalidStateException('Solo puedes confirmar cuando el guardia ya llegó');
    }
    final closed = a.copyWith(status: AlertStatus.closed, closedAt: DateTime.now());
    _db.replaceAlert(closed);
    return closed;
  }
}

// ═════════════════════════════════════════════════════════════════════
// Guardia
// ═════════════════════════════════════════════════════════════════════
class MockGuardAlertRepository implements GuardAlertRepository {
  MockGuardAlertRepository(this._db);
  final MockBackend _db;

  Guard get _me => _db.guardById(_db.me.id);

  @override
  Future<Guard> getMyProfile() async {
    await _db.delay();
    return _me;
  }

  @override
  Stream<List<RankedAlert>> watchAvailableAlerts() {
    return _db.watch(() {
      final g = _me;
      final now = DateTime.now();
      if (!g.isAvailableAt(now)) return <RankedAlert>[];
      final candidates = _db.alerts.where(
        (a) =>
            a.status == AlertStatus.searching &&
            a.location != null &&
            GeoUtils.isInsideCoverage(g.profile.coverageCenter!, g.profile.coverageRadiusMeters!, a.location!),
      );
      return rankAlertsForGuard(
        alerts: candidates.toList(),
        guardLocation: g.profile.lastLocation ?? g.profile.coverageCenter!,
        now: now,
        metersPerWaitingMinute: _db.config.priorityMetersPerWaitingMinute,
      );
    });
  }

  @override
  Future<Alert> getAlert(String alertId) async {
    await _db.delay();
    return _db.alertById(alertId);
  }

  @override
  Stream<Alert> watchAlert(String alertId) => _db.watch(() => _db.alertById(alertId));

  @override
  Future<Alert> acceptAlert(String alertId) async {
    await _db.delay();
    final a = _db.alertById(alertId);
    if (a.status != AlertStatus.searching) throw const AlertTakenException();
    final me = _me;
    final accepted = a.copyWith(
      status: AlertStatus.inProgress,
      guardId: me.user.id,
      guardName: me.user.name,
      acceptedAt: DateTime.now(),
    );
    _db.replaceAlert(accepted);
    return accepted;
  }

  @override
  Future<void> updateMyLocation(GeoPoint location) async {
    final id = _db.me.id;
    _db.guardProfiles[id] = _db.guardProfiles[id]!.copyWith(lastLocation: location);
    _db.notify();
  }

  @override
  Future<Alert> markArrived(String alertId) async {
    await _db.delay();
    final a = _db.alertById(alertId);
    final here = _me.profile.lastLocation;
    final radius = _db.config.geofenceRadiusMeters;
    if (here == null || a.location == null) throw const OutsideGeofenceException(double.infinity);
    final d = GeoUtils.distanceMeters(here, a.location!);
    if (d > radius) throw OutsideGeofenceException(d - radius);
    final arrived = a.copyWith(status: AlertStatus.guardArrived, arrivedAt: DateTime.now());
    _db.replaceAlert(arrived);
    _db.simulateUserConfirmation(alertId);
    return arrived;
  }
}

// ═════════════════════════════════════════════════════════════════════
// Administrador
// ═════════════════════════════════════════════════════════════════════
class MockAdminRepository implements AdminRepository {
  MockAdminRepository(this._db);
  final MockBackend _db;

  @override
  Future<List<Guard>> getGuards({String search = ''}) async {
    await _db.delay();
    final q = search.trim().toLowerCase();
    final list = _db.guardProfiles.keys
        .map(_db.guardById)
        .where((g) => q.isEmpty || g.user.name.toLowerCase().contains(q) || g.user.email.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        if (a.user.isActive != b.user.isActive) return a.user.isActive ? -1 : 1;
        return a.user.name.compareTo(b.user.name);
      });
    return list;
  }

  @override
  Future<Guard> createGuard({required String name, required String email, required String phone}) async {
    await _db.delay();
    if (_db.users.values.any((u) => u.email.toLowerCase() == email.toLowerCase())) {
      throw const EmailTakenException();
    }
    final id = 'grd-${DateTime.now().millisecondsSinceEpoch}';
    _db.users[id] = AppUser(id: id, name: name, email: email, phone: phone, role: UserRole.guard, createdAt: DateTime.now());
    _db.passwords[id] = 'SafeLink1';
    _db.guardProfiles[id] = GuardProfile(
      userId: id,
      shiftStart: '08:00',
      shiftEnd: '16:00',
      coverageCenter: null,
      coverageRadiusMeters: null,
    );
    _db.notify();
    return _db.guardById(id);
  }

  @override
  Future<Guard> updateGuard(String guardId, {String? name, String? email, String? phone}) async {
    await _db.delay();
    _db.users[guardId] = _db.users[guardId]!.copyWith(name: name, email: email, phone: phone);
    _db.notify();
    return _db.guardById(guardId);
  }

  @override
  Future<void> deactivateGuard(String guardId) async {
    await _db.delay();
    _db.users[guardId] = _db.users[guardId]!.copyWith(isActive: false);
    _db.notify();
  }

  @override
  Future<Guard> updateCoverage(
    String guardId, {
    required String shiftStart,
    required String shiftEnd,
    required GeoPoint center,
    required int radiusMeters,
  }) async {
    await _db.delay();
    _db.guardProfiles[guardId] = _db.guardProfiles[guardId]!.copyWith(
      shiftStart: shiftStart,
      shiftEnd: shiftEnd,
      coverageCenter: center,
      coverageRadiusMeters: radiusMeters,
    );
    _db.notify();
    return _db.guardById(guardId);
  }

  @override
  Stream<List<Alert>> watchEscalatedAlerts() => _db.watch(
        () => _db.alerts.where((a) => a.status == AlertStatus.escalated).toList()
          ..sort((a, b) => a.triggeredAt.compareTo(b.triggeredAt)),
      );

  @override
  Future<Alert> resolveAlert(String alertId, Resolution resolution) async {
    await _db.delay();
    final a = _db.alertById(alertId);
    final resolved = a.copyWith(status: AlertStatus.resolvedByAdmin, resolution: resolution, closedAt: DateTime.now());
    if (resolution == Resolution.falseAlarm) {
      _db.users[a.userId] = AlertRules.applyFalseAlarm(
        _db.users[a.userId]!,
        now: DateTime.now(),
        limit: _db.config.falseAlarmLimit,
        blockDays: _db.config.blockDurationDays,
      );
    }
    _db.replaceAlert(resolved);
    return resolved;
  }

  @override
  Future<List<Alert>> getHistory(AlertHistoryFilter f) async {
    await _db.delay();
    return _db.alerts
        .where((a) =>
            (f.from == null || !a.triggeredAt.isBefore(f.from!)) &&
            (f.to == null || a.triggeredAt.isBefore(f.to!)) &&
            (f.guardId == null || a.guardId == f.guardId) &&
            (f.userId == null || a.userId == f.userId) &&
            (f.status == null || a.status == f.status))
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
  }

  @override
  Future<GeneralMetrics> getMetrics({DateTime? from, DateTime? to}) async {
    final list = await getHistory(AlertHistoryFilter(from: from, to: to));
    return MetricsCalculator.general(list);
  }

  @override
  Future<GuardMetrics> getGuardMetrics(String guardId, {DateTime? from, DateTime? to}) async {
    final list = await getHistory(AlertHistoryFilter(from: from, to: to, guardId: guardId));
    return MetricsCalculator.forGuard(guardId, list);
  }

  @override
  Future<List<AppUser>> getBlockedUsers() async {
    await _db.delay();
    final now = DateTime.now();
    return _db.users.values.where((u) => u.isBlockedAt(now)).toList();
  }

  @override
  Future<void> unblockUser(String userId) async {
    await _db.delay();
    _db.users[userId] = _db.users[userId]!.copyWith(clearBlock: true, falseAlarmCount: 0);
    _db.notify();
  }
}
