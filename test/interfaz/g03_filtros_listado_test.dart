// G-03 Filtros del listado de alertas del guardia en la app real (memoria, sin simulaciones).
// guardia@safelink.mx ve 4 alertas: 1 agitación, 2 toque y 1 mantener (sin foto).
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

  Future<void> abrirAlertas(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = MemoriaBaseDatos(latencia: Duration.zero);
    final deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
    );
    await deps.sesion.iniciarSesion('guardia@safelink.mx', 'SafeLink1');
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await esperar(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(AppRoutes.guardAlerts);
    await esperar(tester);
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await esperar(tester);
  }

  testWidgets('el chip de tipo de disparo filtra y "Limpiar" restablece', (tester) async {
    await abrirAlertas(tester);
    expect(find.text('4 alertas'), findsOneWidget);
    expect(find.byType(AlertCard), findsNWidgets(4));

    await tocar(tester, find.widgetWithText(ChoiceChip, 'Toque'));
    expect(find.text('2 de 4 alertas'), findsOneWidget);
    expect(find.byType(AlertCard), findsNWidgets(2));

    await tocar(tester, find.widgetWithText(ChoiceChip, 'Urgentes'));
    expect(find.text('1 de 4 alertas'), findsOneWidget);

    await tocar(tester, find.widgetWithText(ActionChip, 'Limpiar'));
    expect(find.text('4 alertas'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Limpiar'), findsNothing);
  });

  testWidgets('evidencia "Sin foto" desde la hoja inferior', (tester) async {
    await abrirAlertas(tester);
    await tocar(tester, find.widgetWithText(ActionChip, 'Evidencia'));
    await tocar(tester, find.widgetWithText(ListTile, 'Sin foto'));
    expect(find.text('1 de 4 alertas'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Sin foto'), findsOneWidget);
  });

  testWidgets('cambiar el orden no oculta alertas', (tester) async {
    await abrirAlertas(tester);
    await tocar(tester, find.widgetWithText(ActionChip, 'Prioridad'));
    await tocar(tester, find.widgetWithText(ListTile, 'Más cercanas'));
    expect(find.widgetWithText(ActionChip, 'Más cercanas'), findsOneWidget);
    expect(find.text('4 alertas'), findsOneWidget);
    expect(find.byType(AlertCard), findsNWidgets(4));
  });

  testWidgets('sin resultados muestra el estado vacío con "Limpiar filtros"', (tester) async {
    await abrirAlertas(tester);
    await tocar(tester, find.widgetWithText(ChoiceChip, 'Urgentes'));
    await tocar(tester, find.widgetWithText(ActionChip, 'Evidencia'));
    await tocar(tester, find.widgetWithText(ListTile, 'Sin foto'));

    expect(find.text('Sin alertas con estos filtros'), findsOneWidget);
    expect(find.text('Todo tranquilo'), findsNothing);

    await tocar(tester, find.text('Limpiar filtros'));
    expect(find.text('4 alertas'), findsOneWidget);
  });
}
