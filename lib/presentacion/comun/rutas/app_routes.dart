// CAPA: PRESENTACIÓN — rutas
// Usar SIEMPRE estas constantes: `context.go(AppRoutes.guardHome)`.
// No hace: no decide a dónde redirigir (eso es app_router.dart).

abstract final class AppRoutes {
  // Compartidas
  static const login = '/login';
  static const register = '/register';
  static const styleGuide = '/dev/styles';

  // Usuario protegido
  static const userHome = '/user';
  static const userPermissions = '/user/permissions';
  static const userAlert = '/user/alert';
  static const userSettings = '/user/settings';
  static const userBlocked = '/user/blocked';
  static const userHistory = '/user/history';

  // Guardia (pestañas de la barra inferior: Inicio, Alertas, Historial)
  /// Pestaña Inicio. También es el destino tras el login (`inicioPara`).
  static const guardHome = '/guard';
  static const guardAlerts = '/guard/alerts';
  static const guardHistory = '/guard/history';
  // Flujo de atención: pantalla completa, sin la barra inferior.
  static String guardIncoming(String id) => '/guard/incoming/$id';
  static String guardAlertDetail(String id) => '/guard/alerts/$id';
  static String guardNavigation(String id) => '/guard/alerts/$id/navigate';

  // Administrador (pestañas de la barra inferior)
  static const adminDashboard = '/admin';
  static const adminGuards = '/admin/guards';
  static const adminGuardNew = '/admin/guards/new';
  static String adminGuardEdit(String id) => '/admin/guards/$id/edit';
  static String adminGuardCoverage(String id) => '/admin/guards/$id/coverage';
  static const adminEscalated = '/admin/escalated';
  static const adminHistory = '/admin/history';
}
