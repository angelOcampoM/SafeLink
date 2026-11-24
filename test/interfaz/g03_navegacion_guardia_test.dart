// G-03 Navegación del guardia: barra inferior con Inicio, Alertas e Historial.
// Cambia entre pestañas, la barra no aparece en el flujo de atención y cada
// pestaña conserva su estado (app real en memoria, sin latencia ni simulaciones).
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
import 'package:safelink/presentacion/comun/widgets/widgets.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  }

  Future<MemoriaBaseDatos> abrir(WidgetTester tester, String correo) async {
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
    await esperar(tester);
    return db;
  }

  Finder pestana(String etiqueta) => find.descendant(of: find.byType(NavigationBar), matching: find.text(etiqueta));

  Future<void> tocarPestana(WidgetTester tester, String etiqueta) async {
    await tester.tap(pestana(etiqueta));
    await esperar(tester);
  }

  GoRouter router(WidgetTester tester) => GoRouter.of(tester.element(find.byType(Scaffold).first));

  testWidgets('el guardia entra a Inicio y cambia entre las 3 pestañas', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('MI TURNO'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsOneWidget);

    await tocarPestana(tester, 'Alertas');
    expect(find.text('Alertas cercanas'), findsOneWidget);
    expect(find.byTooltip('Cerrar sesión'), findsNothing);

    await tocarPestana(tester, 'Historial');
    expect(find.widgetWithText(AppBar, 'Historial'), findsOneWidget);

    await tocarPestana(tester, 'Inicio');
    expect(find.text('MI TURNO'), findsOneWidget);
  });

  testWidgets('"Ver alertas" en Inicio cambia a la pestaña Alertas', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');
    await tester.tap(find.text('Ver alertas'));
    await esperar(tester);
    expect(find.text('Alertas cercanas'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('la barra no aparece en entrante, detalle ni navegación', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');

    for (final ruta in [
      AppRoutes.guardIncoming('alt-101'),
      AppRoutes.guardAlertDetail('alt-102'),
      AppRoutes.guardNavigation('alt-202'),
    ]) {
      router(tester).go(ruta);
      await esperar(tester);
      expect(find.byType(NavigationBar), findsNothing, reason: ruta);
    }
  });

  testWidgets('abrir el detalle desde Alertas y volver regresa a la pestaña con la barra', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');
    await tocarPestana(tester, 'Alertas');

    await tester.tap(find.byType(AlertCard).first);
    await esperar(tester);
    expect(find.text('Detalle de alerta'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    router(tester).pop();
    await esperar(tester);
    expect(find.text('Alertas cercanas'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('la pestaña Alertas conserva su estado al cambiar de pestaña', (tester) async {
    final db = await abrir(tester, 'guardia@safelink.mx');
    await tocarPestana(tester, 'Alertas');

    db.simularNuevaAlerta();
    await esperar(tester);
    expect(find.text('Alerta entrante'), findsOneWidget);

    await tocarPestana(tester, 'Inicio');
    await tocarPestana(tester, 'Alertas');
    expect(find.text('Alerta entrante'), findsOneWidget, reason: 'el ViewModel del listado no se recrea');
  });
}
