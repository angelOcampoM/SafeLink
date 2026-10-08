/// Rutas de la app. Usar SIEMPRE estas constantes: `context.go(AppRoutes.guardHome)`.
abstract final class AppRoutes {
  // Compartidas
  static const login = '/login';
  static const register = '/register';
  static const styleGuide = '/dev/styles';

  // Usuario protegido
  static const userHome = '/user';
  static const userAlert = '/user/alert';
  static const userSettings = '/user/settings';
  static const userBlocked = '/user/blocked';

  // Guardia
  static const guardHome = '/guard';
  static String guardAlertDetail(String id) => '/guard/alerts/$id';
  static String guardNavigation(String id) => '/guard/alerts/$id/navigate';

  // Administrador (pestañas de la barra inferior)
  static const adminDashboard = '/admin';
  static const adminGuards = '/admin/guards';
  static const adminEscalated = '/admin/escalated';
  static const adminHistory = '/admin/history';
}
