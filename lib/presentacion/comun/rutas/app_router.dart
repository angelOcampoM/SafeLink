// CAPA: PRESENTACIÓN — router (go_router)
// Escucha la sesión para redirigir por rol y crea cada Page con el ViewModel
// que le da la FabricaViewModels.
// No hace: no conoce implementaciones de datos ni valida permisos reales (eso es de la API).

import 'package:go_router/go_router.dart';

import '../../../dominio/enums.dart';
import '../../admin/admin_shell.dart';
import '../../admin/cobertura_guardia_page.dart';
import '../../admin/editar_guardia_page.dart';
import '../../admin/escaladas_page.dart';
import '../../admin/guardias_page.dart';
import '../../admin/historial_page.dart';
import '../../admin/panel_page.dart';
import '../../auth/login_page.dart';
import '../../auth/registro_page.dart';
import '../../dev/guia_estilos_page.dart';
import '../../guardia/alerta_entrante_page.dart';
import '../../guardia/detalle_alerta_page.dart';
import '../../guardia/historial_guardia_page.dart';
import '../../guardia/listado_alertas_page.dart';
import '../../guardia/navegacion_page.dart';
import '../../sesion/sesion_view_model.dart';
import '../../usuario/bloqueado_page.dart';
import '../../usuario/configuracion_page.dart';
import '../../usuario/estado_alerta_page.dart';
import '../../usuario/historial_usuario_page.dart';
import '../../usuario/inicio_page.dart';
import 'app_routes.dart';
import 'fabrica_view_models.dart';

String inicioPara(RolUsuario rol) => switch (rol) {
      RolUsuario.usuarioProtegido => AppRoutes.userHome,
      RolUsuario.guardia => AppRoutes.guardHome,
      RolUsuario.admin => AppRoutes.adminDashboard,
    };

GoRouter crearRouter(SesionViewModel sesion, FabricaViewModels f) {
  const publicas = {AppRoutes.login, AppRoutes.register, AppRoutes.styleGuide};

  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: sesion,
    redirect: (context, state) {
      final ruta = state.matchedLocation;
      final usuario = sesion.usuario;

      if (usuario == null) return publicas.contains(ruta) ? null : AppRoutes.login;
      if (ruta == AppRoutes.login || ruta == AppRoutes.register) return inicioPara(usuario.rol);
      if (ruta == AppRoutes.styleGuide) return null;

      // Cada rol solo entra a su sección (los permisos reales los valida la API).
      final prefijo = inicioPara(usuario.rol);
      if (!ruta.startsWith(prefijo)) return prefijo;

      // Usuario bloqueado → aviso en lugar del botón (sección 6.6).
      if (usuario.rol == RolUsuario.usuarioProtegido) {
        if (sesion.bloqueado && ruta != AppRoutes.userBlocked) return AppRoutes.userBlocked;
        if (!sesion.bloqueado && ruta == AppRoutes.userBlocked) return AppRoutes.userHome;
      }
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.login, builder: (_, __) => LoginPage(viewModel: f.login())),
      GoRoute(path: AppRoutes.register, builder: (_, __) => RegistroPage(viewModel: f.registro())),
      GoRoute(path: AppRoutes.styleGuide, builder: (_, __) => const GuiaEstilosPage()),

      // ── Usuario protegido ──
      GoRoute(
        path: AppRoutes.userHome,
        builder: (_, __) => InicioPage(viewModel: f.inicio()),
        routes: [
          GoRoute(path: 'alert', builder: (_, __) => EstadoAlertaPage(viewModel: f.estadoAlerta())),
          GoRoute(path: 'settings', builder: (_, __) => ConfiguracionPage(viewModel: f.configuracion())),
          GoRoute(path: 'history', builder: (_, __) => HistorialUsuarioPage(viewModel: f.historialUsuario())),
          GoRoute(path: 'blocked', builder: (_, __) => BloqueadoPage(sesion: sesion)),
        ],
      ),

      // ── Guardia ──
      GoRoute(
        path: AppRoutes.guardHome,
        builder: (_, __) => ListadoAlertasPage(viewModel: f.listadoAlertas()),
        routes: [
          GoRoute(path: 'history', builder: (_, __) => HistorialGuardiaPage(viewModel: f.historialGuardia())),
          GoRoute(
            path: 'incoming/:id',
            builder: (_, s) => AlertaEntrantePage(viewModel: f.alertaEntrante(s.pathParameters['id']!)),
          ),
          GoRoute(
            path: 'alerts/:id',
            builder: (_, s) => DetalleAlertaPage(viewModel: f.detalleAlerta(s.pathParameters['id']!)),
            routes: [
              GoRoute(
                path: 'navigate',
                builder: (_, s) => NavegacionPage(viewModel: f.navegacion(s.pathParameters['id']!)),
              ),
            ],
          ),
        ],
      ),

      // ── Administrador (barra inferior) ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AdminShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminDashboard, builder: (_, __) => PanelPage(viewModel: f.panel()))]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.adminGuards,
                builder: (_, __) => GuardiasPage(viewModel: f.guardias()),
                routes: [
                  GoRoute(path: 'new', builder: (_, __) => EditarGuardiaPage(viewModel: f.editarGuardia())),
                  GoRoute(
                    path: ':id/edit',
                    builder: (_, s) => EditarGuardiaPage(viewModel: f.editarGuardia(id: s.pathParameters['id'])),
                  ),
                  GoRoute(
                    path: ':id/coverage',
                    builder: (_, s) => CoberturaGuardiaPage(viewModel: f.coberturaGuardia(s.pathParameters['id']!)),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminEscalated, builder: (_, __) => EscaladasPage(viewModel: f.escaladas()))]),
          StatefulShellBranch(routes: [GoRoute(path: AppRoutes.adminHistory, builder: (_, __) => HistorialPage(viewModel: f.historial()))]),
        ],
      ),
    ],
  );
}
