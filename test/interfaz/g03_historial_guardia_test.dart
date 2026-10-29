// G-03 Historial del guardia con filtros en la app real (memoria, sin simulaciones).
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

  Future<void> abrirHistorial(WidgetTester tester, String correo) async {
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
    await deps.sesion.iniciarSesion(correo, 'SafeLink1');
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await esperar(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(AppRoutes.guardHistory);
    await esperar(tester);
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await esperar(tester);
  }

  /// "N alertas · llegada promedio …" → N.
  int conteo(WidgetTester tester) {
    final t = tester.widget<Text>(find.textContaining(RegExp(r'^\d+ alertas?'))).data!;
    return int.parse(t.split(' ').first);
  }

  testWidgets('muestra filtros, métricas y resumen; el filtro de resultado reduce la lista', (tester) async {
    await abrirHistorial(tester, 'guardia@safelink.mx');
    expect(find.text('MIS MÉTRICAS'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Todas las fechas'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Cualquier método'), findsOneWidget);
    final total = conteo(tester);
    expect(total, greaterThan(1));

    await tocar(tester, find.widgetWithText(ChoiceChip, 'Resuelta por administrador'));
    final filtrado = conteo(tester);
    expect(filtrado, inInclusiveRange(1, total - 1));
    expect(find.byType(AlertCard), findsNWidgets(filtrado));

    await tocar(tester, find.widgetWithText(ActionChip, 'Limpiar'));
    expect(conteo(tester), total);
  });

  testWidgets('método de disparo desde la hoja inferior', (tester) async {
    await abrirHistorial(tester, 'guardia@safelink.mx');
    final total = conteo(tester);
    await tocar(tester, find.widgetWithText(ActionChip, 'Cualquier método'));
    await tocar(tester, find.widgetWithText(ListTile, 'Urgentes'));
    expect(find.widgetWithText(ActionChip, 'Urgentes'), findsOneWidget);
    expect(conteo(tester), lessThan(total));
  });

  testWidgets('sin resultados muestra "Sin alertas con estos filtros" y se puede limpiar', (tester) async {
    await abrirHistorial(tester, 'guardia@safelink.mx');
    final total = conteo(tester);
    // En la semilla, la única escalada de guardia@ fue por toque: escalada + urgentes = 0.
    await tocar(tester, find.widgetWithText(ChoiceChip, 'Escalada'));
    await tocar(tester, find.widgetWithText(ActionChip, 'Cualquier método'));
    await tocar(tester, find.widgetWithText(ListTile, 'Urgentes'));

    expect(conteo(tester), 0);
    expect(find.text('Sin alertas con estos filtros'), findsOneWidget);
    expect(find.text('MIS MÉTRICAS'), findsOneWidget, reason: 'las métricas siguen visibles');

    await tocar(tester, find.text('Limpiar filtros'));
    expect(conteo(tester), total);
  });

  testWidgets('un guardia sin historial ve "Aún no atiendes alertas"', (tester) async {
    await abrirHistorial(tester, 'sofia.rendon@safelink.mx');
    expect(find.text('Aún no atiendes alertas'), findsOneWidget);
    expect(find.text('Sin alertas con estos filtros'), findsNothing);
  });
}
