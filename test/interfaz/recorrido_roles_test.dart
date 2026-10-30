// Recorrido de humo: cada rol abre todas sus pantallas en la app real (memoria,
// sin latencia ni simulaciones) y ninguna lanza excepciones de layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/main.dart';
import 'package:safelink/presentacion/comun/rutas/app_routes.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  Future<MemoriaBaseDatos> abrir(WidgetTester tester, String correo) async {
    // La fuente de pruebas mide 1 em por glifo (más ancha que Inter): pantalla holgada.
    tester.view.physicalSize = const Size(1800, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = MemoriaBaseDatos(latencia: Duration.zero);
    final deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
    );
    await deps.sesion.iniciarSesion(correo, 'SafeLink1');
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return db;
  }

  Future<void> ir(WidgetTester tester, String ruta, String textoEsperado) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(ruta);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull, reason: ruta);
    expect(find.textContaining(textoEsperado), findsWidgets, reason: ruta);
  }

  testWidgets('usuario protegido', (tester) async {
    await abrir(tester, 'usuario@safelink.mx');
    await ir(tester, AppRoutes.userHome, 'Hola, Fernanda');
    await ir(tester, AppRoutes.userAlert, 'Sin alertas activas');
    await ir(tester, AppRoutes.userSettings, 'Alerta por agitación');
    await ir(tester, AppRoutes.userHistory, 'Mis alertas');
  });

  testWidgets('usuario bloqueado', (tester) async {
    await abrir(tester, 'bloqueado@safelink.mx');
    await ir(tester, AppRoutes.userHome, 'Tu cuenta está bloqueada');
  });

  testWidgets('guardia', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');
    await ir(tester, AppRoutes.guardHome, 'Alertas cercanas');
    await ir(tester, AppRoutes.guardHistory, 'Alertas atendidas');
    await ir(tester, AppRoutes.guardIncoming('alt-101'), 'Ver detalle');
    await ir(tester, AppRoutes.guardAlertDetail('alt-102'), 'Aceptar alerta');
    await ir(tester, AppRoutes.guardNavigation('alt-202'), 'Llegué');
  });

  testWidgets('guardia nocturno fuera de turno o en turno', (tester) async {
    await abrir(tester, 'guardia.noche@safelink.mx');
    await ir(tester, AppRoutes.guardHome, 'Alertas cercanas');
  });

  testWidgets('administrador', (tester) async {
    await abrir(tester, 'admin@safelink.mx');
    await ir(tester, AppRoutes.adminDashboard, 'Panel general');
    await tester.tap(find.text('7 días'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await ir(tester, AppRoutes.adminGuards, 'Carlos Hernández López');
    await ir(tester, AppRoutes.adminGuardNew, 'Nuevo guardia');
    await ir(tester, AppRoutes.adminGuardEdit('grd-1'), 'Editar guardia');
    await ir(tester, AppRoutes.adminGuardCoverage('grd-1'), 'Turno y radio');
    await ir(tester, AppRoutes.adminGuardMetrics('grd-1'), 'Métricas del guardia');
    await ir(tester, AppRoutes.adminEscalated, 'Escaladas');
    await ir(tester, AppRoutes.adminHistory, 'Todos los usuarios');
    await ir(tester, AppRoutes.adminAlertDetail('alt-302'), 'Detalle de la alerta');
  });
}
