// U-03 Cuenta regresiva · U-04 Zona de descarte · U-07 Indicador de ubicación
// U-08 Sin ubicación del guardia · U-09 Confirmación de atención
// Pruebas de interfaz del usuario protegido con la app armada en memoria.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/main.dart';
import 'package:safelink/presentacion/comun/rutas/app_routes.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';
import 'package:safelink/presentacion/comun/widgets/widgets.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);
  late MemoriaBaseDatos db;

  Future<Dependencias> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    db = MemoriaBaseDatos(latencia: Duration.zero);
    final deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
    );
    await deps.sesion.iniciarSesion('usuario@safelink.mx', 'SafeLink1');
    deps.sesion.permisosVistos();
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await bombear(tester);
    return deps;
  }

  testWidgets('U-03: el toque muestra la cuenta regresiva y "Cancelar" vuelve al inicio', (tester) async {
    await abrir(tester);

    await tester.tap(find.byType(EmergencyButton));
    await bombear(tester);
    expect(find.text('La alerta se enviará'), findsOneWidget);
    expect(find.text('Enviando alerta'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await bombear(tester);
    expect(find.text('La alerta se enviará'), findsNothing);
    expect(find.text('Toca o mantén presionado'), findsOneWidget);
  });

  testWidgets('U-07 · U-08: "Buscando guardia" indica que se comparte la ubicación y no muestra mapa', (tester) async {
    final deps = await abrir(tester);
    await deps.alertasUsuario.crearAlerta(
      metodo: MetodoDisparo.toque,
      disparadaEn: DateTime.now().toUtc(),
      ubicacion: const PuntoGeo(18.84, -99.18),
      rumbo: 35,
      rutaFoto: 'demo.jpg',
    );

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(AppRoutes.userAlert);
    await bombear(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Buscando guardia'), findsOneWidget);
    expect(find.text('Compartiendo ubicación en tiempo real'), findsOneWidget);
    expect(find.text('Información enviada'), findsOneWidget);
    expect(find.byType(MapPlaceholder), findsNothing);
    // U-09: sin guardia no hay nada que confirmar.
    expect(find.text('Ya fui atendido'), findsNothing);

    // La base en memoria programa escalamientos: se cancelan antes de que termine la prueba.
    await tester.pumpWidget(const SizedBox());
    db.dispose();
  });

  // ── U-04 · Mantener presionado ──────────────────────────────────────────

  /// La zona vive siempre en el árbol y aparece con la opacidad: se mide ahí.
  double opacidadDeLaZona(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        // El bote de basura está siempre; el texto de la zona cambia.
        find.ancestor(of: find.byIcon(Icons.delete_outline_rounded), matching: find.byType(AnimatedOpacity)),
      )
      .opacity;

  testWidgets('U-04: al mantener presionado aparece la zona de descarte y se resalta al pasar encima', (tester) async {
    await abrir(tester);
    expect(opacidadDeLaZona(tester), 0, reason: 'sin mantener, la zona no se ve');

    final gesto = await tester.startGesture(tester.getCenter(find.byType(EmergencyButton)));
    await tester.pump(const Duration(milliseconds: 600)); // se reconoce el long press
    await bombear(tester);

    expect(opacidadDeLaZona(tester), 1, reason: 'al mantener, la zona aparece');
    expect(find.text('Suelta para enviar la alerta'), findsOneWidget, reason: 'el botón cambió de apariencia');
    expect(find.text('Arrastra aquí para descartar'), findsOneWidget);

    // El dedo baja hasta la zona: se resalta y cambia su texto.
    await gesto.moveTo(tester.getCenter(find.text('Arrastra aquí para descartar')));
    await bombear(tester);
    expect(find.text('Suelta para descartar'), findsOneWidget);

    await gesto.up();
    await bombear(tester);
    expect(find.text('Toca o mantén presionado'), findsOneWidget);
    db.dispose();
  });

  testWidgets('U-04: mantener presionado 30 s no dispara la alerta ni oculta la zona', (tester) async {
    final deps = await abrir(tester);
    final antes = (await deps.alertasUsuario.obtenerHistorial()).length;

    final gesto = await tester.startGesture(tester.getCenter(find.byType(EmergencyButton)));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(opacidadDeLaZona(tester), 1, reason: 'la zona sigue visible tras 30 s');
    expect(find.text('Suelta para enviar la alerta'), findsOneWidget);
    expect((await deps.alertasUsuario.obtenerHistorial()).length, antes, reason: 'no se disparó sola');

    await gesto.up();
    await bombear(tester);
    db.dispose();
  });

  // ── U-09 · Confirmación de atención ─────────────────────────────────────

  testWidgets('U-09: "Ya fui atendido" solo aparece cuando el guardia ya llegó', (tester) async {
    final deps = await abrir(tester);
    final alerta = await deps.alertasUsuario.crearAlerta(
      metodo: MetodoDisparo.toque,
      disparadaEn: DateTime.now().toUtc(),
      ubicacion: const PuntoGeo(18.84, -99.18),
      rumbo: 35,
      rutaFoto: 'demo.jpg',
    );

    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(AppRoutes.userAlert);
    await bombear(tester);
    expect(find.text('Ya fui atendido'), findsNothing, reason: 'todavía nadie la acepta');

    // El guardia acepta y marca su llegada.
    db.reemplazarAlerta(db.alertas.firstWhere((a) => a.id == alerta.id).copyWith(
          estado: EstadoAlerta.guardiaEnLugar,
          guardiaId: 'grd-1',
          nombreGuardia: 'Carlos Hernández López',
          aceptadaEn: DateTime.now(),
          llegadaEn: DateTime.now(),
          etaSegundos: 0,
        ),);
    await bombear(tester);

    expect(find.text('Ya fui atendido'), findsOneWidget);

    await tester.tap(find.text('Ya fui atendido'));
    await bombear(tester);

    expect(find.text('Toca o mantén presionado'), findsOneWidget, reason: 'vuelve al botón de alerta');

    await tester.pumpWidget(const SizedBox());
    db.dispose();
  });
}

// El inicio late en bucle (EmergencyButton): pumpAndSettle nunca terminaría.
Future<void> bombear(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
