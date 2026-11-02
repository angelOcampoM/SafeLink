// Pruebas de interfaz del guardia para G-04, G-05, G-06 y G-07.
// El detalle de la alerta, la aceptación y la pantalla de ruta, con la app
// completa armada en memoria.
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

  Future<Dependencias> abrirComoGuardia(WidgetTester tester) async {
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
    await deps.sesion.iniciarSesion('guardia@safelink.mx', 'SafeLink1');
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await bombear(tester);
    return deps;
  }

  Future<void> ir(WidgetTester tester, String ruta) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(ruta);
    await bombear(tester);
  }

  // ── G-04 · Detalle de la alerta ─────────────────────────────────────────

  testWidgets('G-04: el detalle muestra la foto, el mapa y el método de disparo', (tester) async {
    await abrirComoGuardia(tester);
    await ir(tester, AppRoutes.guardAlertDetail('alt-102'));

    expect(find.text('Detalle de alerta'), findsOneWidget);
    expect(find.byType(MapPlaceholder), findsOneWidget, reason: 'el mapa con el punto y el rumbo');
    expect(find.byType(TriggerChip), findsWidgets, reason: 'el método de disparo');
    expect(tester.takeException(), isNull);
  });

  testWidgets('G-04: una alerta sin foto avisa que la evidencia está incompleta', (tester) async {
    final deps = await abrirComoGuardia(tester);

    // La semilla trae alertas disparadas sin foto (evidencia incompleta).
    final sinFoto = db.alertas.firstWhere(
      (a) => a.evidenciaIncompleta && a.estado == EstadoAlerta.buscando,
    );

    await ir(tester, AppRoutes.guardAlertDetail(sinFoto.id));
    expect(find.text('Fotografía no disponible'), findsOneWidget);
    expect(deps.sesion.haySesion, isTrue);
  });

  // ── G-05 · Aceptación de alerta ─────────────────────────────────────────

  testWidgets('G-05: aceptar cambia el estado y ninguna pantalla deja cerrar la alerta', (tester) async {
    await abrirComoGuardia(tester);
    await ir(tester, AppRoutes.guardAlertDetail('alt-102'));

    expect(find.text('Aceptar alerta'), findsOneWidget);
    // El guardia nunca puede cerrar: eso es del usuario (U-09).
    expect(find.text('Ya fui atendido'), findsNothing);
    expect(find.text('Cerrar alerta'), findsNothing);

    await tester.tap(find.text('Aceptar alerta'));
    await bombear(tester);

    expect(db.alertas.firstWhere((a) => a.id == 'alt-102').estado, EstadoAlerta.enAtencion);
    expect(find.text('En camino'), findsOneWidget, reason: 'se abre la pantalla de ruta');
  });

  // ── G-06 · Ruta hacia el usuario ────────────────────────────────────────

  testWidgets('G-06: la pantalla de ruta muestra mapa, distancia y la salida a Google Maps', (tester) async {
    await abrirComoGuardia(tester);
    await ir(tester, AppRoutes.guardNavigation('alt-202'));

    expect(find.text('En camino'), findsOneWidget);
    expect(find.byType(MapPlaceholder), findsOneWidget);
    expect(find.text('Abrir en Google Maps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── G-07 · Registro de llegada ──────────────────────────────────────────

  testWidgets('G-07: "Llegué" está deshabilitado fuera de la geocerca y dice cuánto falta', (tester) async {
    await abrirComoGuardia(tester);
    await ir(tester, AppRoutes.guardNavigation('alt-202'));

    expect(find.textContaining('Llegué · faltan'), findsOneWidget, reason: 'muestra la distancia restante');

    final boton = tester.widget<SlButton>(
      find.ancestor(of: find.textContaining('Llegué'), matching: find.byType(SlButton)).first,
    );
    expect(boton.onPressed, isNull, reason: 'fuera de la geocerca no se puede marcar');
  });

  testWidgets('G-07: al entrar en la geocerca el botón se habilita y registra la llegada', (tester) async {
    await abrirComoGuardia(tester);
    await ir(tester, AppRoutes.guardNavigation('alt-202'));

    // "Simular acercamiento" mueve al guardia hasta el punto de la alerta.
    for (var i = 0; i < 12; i++) {
      final boton = find.text('Simular acercamiento (demo)');
      if (boton.evaluate().isEmpty) break;
      await tester.tap(boton);
      await bombear(tester);
      if (find.text('Llegué').evaluate().isNotEmpty) break;
    }

    expect(find.text('Llegué'), findsOneWidget, reason: 'dentro de la geocerca el texto ya no lleva distancia');
    await tester.tap(find.text('Llegué'));
    await bombear(tester);

    expect(db.alertas.firstWhere((a) => a.id == 'alt-202').llegadaEn, isNotNull);

    // Marcar la llegada programa la confirmación del usuario: se desmonta y
    // se cierra la base antes de terminar para no dejar timers vivos.
    await tester.pumpWidget(const SizedBox());
    db.dispose();
  });
}

/// Las pantallas del guardia animan en bucle: pumps fijos.
Future<void> bombear(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
