import 'package:go_router/go_router.dart';

import '../../data/models/enums.dart';
import '../../features/admin/dashboard/admin_dashboard_page.dart';
import '../../features/admin/escalated/admin_escalated_page.dart';
import '../../features/admin/guards/admin_guards_page.dart';
import '../../features/admin/history/admin_history_page.dart';
import '../../features/admin/shell/admin_shell.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/auth/session_controller.dart';
import '../../features/dev/style_guide_page.dart';
import '../../features/guard/alert_detail/guard_alert_detail_page.dart';
import '../../features/guard/alert_list/guard_alert_list_page.dart';
import '../../features/guard/navigation/guard_navigation_page.dart';
import '../../features/user/alert_status/alert_status_page.dart';
import '../../features/user/blocked/blocked_page.dart';
import '../../features/user/home/user_home_page.dart';
import '../../features/user/settings/settings_page.dart';
import 'app_routes.dart';

String homeFor(UserRole role) => switch (role) {
      UserRole.protectedUser => AppRoutes.userHome,
      UserRole.guard => AppRoutes.guardHome,
      UserRole.admin => AppRoutes.adminDashboard,
    };

GoRouter buildRouter(SessionController session) {
  const public = {AppRoutes.login, AppRoutes.register, AppRoutes.styleGuide};

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.matchedLocation;
      final user = session.user;

      if (user == null) return public.contains(path) ? null : AppRoutes.login;
      if (path == AppRoutes.login || path == AppRoutes.register) return homeFor(user.role);
      if (path == AppRoutes.styleGuide) return null;

      // Cada rol solo entra a su sección (los permisos reales los valida la API).
      final prefix = homeFor(user.role);
      if (!path.startsWith(prefix)) return prefix;

      // Usuario bloqueado → aviso en lugar del botón (sección 6.6).
      if (user.role == UserRole.protectedUser) {
        final blocked = user.isBlockedAt(DateTime.now());
        if (blocked && path != AppRoutes.userBlocked) return AppRoutes.userBlocked;
        if (!blocked && path == AppRoutes.userBlocked) return AppRoutes.userHome;
      }
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginPage()),
      GoRoute(path: AppRoutes.register, builder: (_, __) => const RegisterPage()),
      GoRoute(path: AppRoutes.styleGuide, builder: (_, __) => const StyleGuidePage()),

      // ── Usuario protegido ──
      GoRoute(
        path: AppRoutes.userHome,
        builder: (_, __) => const UserHomePage(),
        routes: [
          GoRoute(path: 'alert', builder: (_, __) => const AlertStatusPage()),
          GoRoute(path: 'settings', builder: (_, __) => const SettingsPage()),
          GoRoute(path: 'blocked', builder: (_, __) => const BlockedPage()),
        ],
      ),

      // ── Guardia ──
      GoRoute(
        path: AppRoutes.guardHome,
        builder: (_, __) => const GuardAlertListPage(),
        routes: [
          GoRoute(
            path: 'alerts/:id',
            builder: (_, s) => GuardAlertDetailPage(alertId: s.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'navigate',
                builder: (_, s) => GuardNavigationPage(alertId: s.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),

      // ── Administrador (barra inferior) ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AdminShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminDashboard, builder: (_, __) => const AdminDashboardPage())]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminGuards, builder: (_, __) => const AdminGuardsPage())]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminEscalated, builder: (_, __) => const AdminEscalatedPage())]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminHistory, builder: (_, __) => const AdminHistoryPage())]),
        ],
      ),
    ],
  );
}
