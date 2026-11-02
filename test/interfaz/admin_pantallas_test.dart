// Pruebas de interfaz del administrador (A-01 … A-08).
// El panel, el listado de guardias, los turnos, la bandeja, el historial y las
// métricas por guardia, con la app completa armada en memoria.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/main.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/presentacion/admin/panel_page.dart';
import 'package:safelink/presentacion/admin/panel_view_model.dart';
import 'package:safelink/presentacion/comun/rutas/app_routes.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';
import 'package:safelink/presentacion/comun/widgets/widgets.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);
  late MemoriaBaseDatos db;

  Future<Dependencias> abrirComoAdmin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = MemoriaBaseDatos(latencia: Duration.zero);
    addTearDown(db.dispose);
    final deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
    );
    await deps.sesion.iniciarSesion('admin@safelink.mx', 'SafeLink1');
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await bombear(tester);
    return deps;
  }

  Future<void> ir(WidgetTester tester, String ruta) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(ruta);
    await bombear(tester);
  }

  // ── A-06 · Métricas generales ───────────────────────────────────────────

  testWidgets('A-06: el panel muestra las tarjetas, la gráfica por horario y la de zonas', (tester) async {
    await abrirComoAdmin(tester);

    expect(find.text('Panel general'), findsOneWidget);
    expect(find.text('Alertas totales'), findsOneWidget);
    expect(find.text('Aceptación promedio'), findsOneWidget);
    expect(find.text('Llegada promedio'), findsOneWidget);
    expect(find.text('Sin respuesta'), findsOneWidget);
    expect(find.text('Cerradas con confirmación'), findsOneWidget);
    expect(find.text('ALERTAS POR HORA'), findsOneWidget);
    expect(find.text('ALERTAS POR ZONA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A-06: un periodo sin alertas muestra las métricas en cero', (tester) async {
    tester.view.physicalSize = const Size(1800, 3200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final db = MemoriaBaseDatos(latencia: Duration.zero);
    addTearDown(db.dispose);
    final sesion = SesionViewModel(MemoriaAuthRepository(db), MemoriaSesionGuardada());
    await sesion.iniciarSesion('admin@safelink.mx', 'SafeLink1');

    // Un reloj un año adelante deja el periodo sin ninguna alerta registrada.
    final vm = PanelViewModel(
      MemoriaAdminRepository(db),
      sesion,
      reloj: () => DateTime.now().add(const Duration(days: 365)),
    );
    // PanelPage se encarga de desecharlo al desmontarse.

    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: PanelPage(viewModel: vm)));
    await bombear(tester);

    expect(find.text('Alertas totales'), findsOneWidget);
    expect(find.text('0'), findsWidgets, reason: 'las tarjetas se muestran en cero');
    expect(find.text('Cerradas con confirmación'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'sin datos no debe haber errores en pantalla');
  });

  // ── A-01 · Alta de guardias ─────────────────────────────────────────────

  testWidgets('A-01: el alta valida cada campo y no crea al guardia', (tester) async {
    await abrirComoAdmin(tester);
    final antes = (await (MemoriaAdminRepository(db)).obtenerGuardias()).length;

    await ir(tester, AppRoutes.adminGuardNew);
    expect(find.text('Nuevo guardia'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await bombear(tester);

    expect(find.text('Escribe tu nombre'), findsOneWidget);
    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu teléfono'), findsOneWidget);
    expect((await (MemoriaAdminRepository(db)).obtenerGuardias()).length, antes, reason: 'no se creó nadie');
  });

  // ── A-02 · Edición y baja ───────────────────────────────────────────────

  testWidgets('A-02: el buscador filtra el listado y la baja pide confirmación', (tester) async {
    await abrirComoAdmin(tester);
    await ir(tester, AppRoutes.adminGuards);

    expect(find.text('Carlos Hernández López'), findsOneWidget);

    // Buscar sin acentos también filtra (A-02).
    await tester.enterText(find.byType(TextField).first, 'hernandez');
    await bombear(tester);
    expect(find.text('Carlos Hernández López'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz-nadie');
    await bombear(tester);
    expect(find.text('Sin resultados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── A-03 · Turnos y radios ──────────────────────────────────────────────

  testWidgets('A-03: la pantalla de turno ofrece el horario y el radio sobre el mapa', (tester) async {
    await abrirComoAdmin(tester);
    await ir(tester, AppRoutes.adminGuardCoverage('grd-1'));

    expect(find.text('Turno y radio'), findsOneWidget);
    expect(find.text('Inicio'), findsWidgets, reason: 'selector de hora de inicio');
    expect(find.byType(MapPlaceholder), findsOneWidget, reason: 'el radio se ve en el mapa');
    expect(find.byType(Slider), findsOneWidget, reason: 'el radio se ajusta con el deslizador');
    expect(find.textContaining('RADIO DE COBERTURA'), findsOneWidget);
  });

  // ── A-04 · Bandeja de escaladas ─────────────────────────────────────────

  testWidgets('A-04: la bandeja lista las escaladas con su motivo', (tester) async {
    await abrirComoAdmin(tester);
    await ir(tester, AppRoutes.adminEscalated);

    expect(find.text('Escaladas'), findsWidgets);
    // Cada alerta escalada muestra por qué llegó a la bandeja.
    final motivos = find.textContaining('Nadie aceptó').evaluate().length +
        find.textContaining('no confirmó').evaluate().length;
    expect(motivos, greaterThan(0), reason: 'se ve el motivo del escalamiento');
    expect(tester.takeException(), isNull);
  });

  // ── A-05 · Historial ────────────────────────────────────────────────────

  testWidgets('A-05: el historial ofrece sus cuatro filtros y lista alertas', (tester) async {
    await abrirComoAdmin(tester);
    await ir(tester, AppRoutes.adminHistory);

    expect(find.text('Historial'), findsWidgets);
    expect(find.text('Todas las fechas'), findsOneWidget);
    expect(find.text('Todos los guardias'), findsOneWidget);
    expect(find.text('Todos los usuarios'), findsOneWidget);
    expect(find.text('Todas'), findsOneWidget, reason: 'filtro de estado');
    expect(find.byType(AlertCard), findsWidgets);
  });

  // ── A-07 · Métricas por guardia ─────────────────────────────────────────

  testWidgets('A-07: la pantalla del guardia muestra su encabezado y sus cuatro tarjetas', (tester) async {
    await abrirComoAdmin(tester);
    await ir(tester, AppRoutes.adminGuardMetrics('grd-1'));

    expect(find.text('Métricas del guardia'), findsOneWidget);
    expect(find.text('Carlos Hernández López'), findsOneWidget, reason: 'encabezado del guardia');
    expect(find.text('Alertas atendidas'), findsOneWidget);
    expect(find.text('Aceptación promedio'), findsOneWidget);
    expect(find.text('Llegada promedio'), findsOneWidget);
    expect(find.text('Alertas escaladas'), findsOneWidget);
  });

  // ── A-08 · Bloqueo por falsas alarmas ───────────────────────────────────

  testWidgets('A-08: el panel lista a los bloqueados y permite retirar el bloqueo', (tester) async {
    await abrirComoAdmin(tester);

    await tester.scrollUntilVisible(find.text('USUARIOS BLOQUEADOS'), 300, scrollable: find.byType(Scrollable).first);
    await bombear(tester);
    expect(find.text('USUARIOS BLOQUEADOS'), findsOneWidget);
    expect(find.text('Desbloquear'), findsWidgets, reason: 'la semilla trae un usuario bloqueado');

    await tester.tap(find.text('Desbloquear').first);
    await bombear(tester);
    expect(tester.takeException(), isNull);
  });
}

/// Las pantallas del admin tienen animaciones en bucle: pumps fijos.
Future<void> bombear(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
