import 'dart:async';

import '../../core/constants/app_config.dart';
import '../models/models.dart';
import 'mock_seed.dart';

/// "Servidor" en memoria compartido por todos los repositorios mock, para
/// que lo que hace un rol se vea reflejado en los otros (el admin ve la
/// alerta que disparó el usuario, etc.). Se reinicia al cerrar la app.
class MockBackend {
  MockBackend({this.config = AppConfig.defaults, DateTime? now}) {
    final seed = MockSeed(now ?? DateTime.now()).build();
    for (final u in seed.users) {
      users[u.id] = u;
      passwords[u.id] = MockSeed.password;
    }
    for (final g in seed.guards) {
      guardProfiles[g.userId] = g;
    }
    alerts.addAll(seed.alerts);
  }

  final AppConfig config;

  final users = <String, AppUser>{};
  final passwords = <String, String>{};
  final guardProfiles = <String, GuardProfile>{};
  final alerts = <Alert>[];

  String? currentUserId;

  /// Latencia simulada de red, para ver estados de carga en la UI.
  Duration latency = const Duration(milliseconds: 450);

  final _changes = StreamController<void>.broadcast();

  /// Emite el valor actual y lo vuelve a emitir cada vez que cambian datos.
  Stream<T> watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  void notify() => _changes.add(null);

  Future<void> delay() => Future<void>.delayed(latency);

  AppUser get me {
    final id = currentUserId;
    if (id == null) throw StateError('No hay sesión');
    return users[id]!;
  }

  Alert alertById(String id) => alerts.firstWhere((a) => a.id == id);

  void replaceAlert(Alert updated) {
    final i = alerts.indexWhere((a) => a.id == updated.id);
    alerts[i] = updated;
    notify();
  }

  Guard guardById(String id) => Guard(user: users[id]!, profile: guardProfiles[id]!);

  // ── Simulaciones de tiempo real ───────────────────────────────────
  final _timers = <String, Timer>{};

  /// Simula que un guardia acepta, se acerca y llega (flujo del usuario).
  void simulateGuardResponse(String alertId) {
    _timers[alertId]?.cancel();
    var ticks = 0;
    _timers[alertId] = Timer.periodic(const Duration(seconds: 2), (t) {
      ticks++;
      final a = alertById(alertId);
      if (a.status == AlertStatus.searching && ticks >= 2) {
        final g = guardById('grd-1');
        replaceAlert(a.copyWith(
          status: AlertStatus.inProgress,
          guardId: g.user.id,
          guardName: g.user.name,
          acceptedAt: DateTime.now(),
          etaSeconds: 300,
        ));
      } else if (a.status == AlertStatus.inProgress) {
        final eta = (a.etaSeconds ?? 0) - 40;
        if (eta <= 0) {
          replaceAlert(a.copyWith(status: AlertStatus.guardArrived, arrivedAt: DateTime.now(), etaSeconds: 0));
          t.cancel();
        } else {
          replaceAlert(a.copyWith(etaSeconds: eta));
        }
      } else if (!a.status.isActive) {
        t.cancel();
      }
    });
  }

  /// Simula que el usuario confirma la atención (flujo del guardia).
  void simulateUserConfirmation(String alertId) {
    _timers[alertId]?.cancel();
    _timers[alertId] = Timer(const Duration(seconds: 8), () {
      final a = alertById(alertId);
      if (a.status == AlertStatus.guardArrived) {
        replaceAlert(a.copyWith(status: AlertStatus.closed, closedAt: DateTime.now()));
      }
    });
  }

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _changes.close();
  }
}
