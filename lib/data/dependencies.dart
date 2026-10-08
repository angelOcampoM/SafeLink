import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/constants/app_config.dart';
import '../features/auth/session_controller.dart';
import 'mock/mock_backend.dart';
import 'mock/mock_repositories.dart';
import 'repositories/admin_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/guard_alert_repository.dart';
import 'repositories/user_alert_repository.dart';

/// Punto ÚNICO donde se decide mock vs. API real. Las vistas solo piden
/// la interfaz: `context.read<GuardAlertRepository>()`.
class AppDependencies {
  AppDependencies({this.config = AppConfig.defaults}) {
    if (!config.useMockData) {
      // TODO(api): crear ApiAuthRepository, ApiUserAlertRepository, etc.
      throw UnimplementedError('La API real aún no existe. Usa USE_MOCK=true.');
    }
    final db = MockBackend(config: config);
    backend = db;
    auth = MockAuthRepository(db);
    userAlerts = MockUserAlertRepository(db);
    guardAlerts = MockGuardAlertRepository(db);
    admin = MockAdminRepository(db);
    session = SessionController(auth);
  }

  final AppConfig config;

  /// Solo existe en modo mock (para botones "Simular ..." de la demo).
  MockBackend? backend;

  late final AuthRepository auth;
  late final UserAlertRepository userAlerts;
  late final GuardAlertRepository guardAlerts;
  late final AdminRepository admin;
  late final SessionController session;

  List<SingleChildWidget> get providers => [
        Provider<AppConfig>.value(value: config),
        Provider<AuthRepository>.value(value: auth),
        Provider<UserAlertRepository>.value(value: userAlerts),
        Provider<GuardAlertRepository>.value(value: guardAlerts),
        Provider<AdminRepository>.value(value: admin),
        ChangeNotifierProvider<SessionController>.value(value: session),
      ];
}
