// G-03 Una misma alerta de principio a fin (app real en memoria, sin simulaciones de fondo):
// Alertas → entrante → detalle → aceptar → acercarse y "Llegué" → el usuario confirma →
// sale de Alertas y aparece en Historial y en el dashboard (pestañas que ya estaban abiertas).
// Otro guardia no ve cambios; ignoradas y escaladas sin respuesta no llegan al historial.
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

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await esperar(tester);
  }

  Future<void> pestana(WidgetTester tester, String etiqueta) =>
      tocar(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text(etiqueta)));

  String valor(WidgetTester tester, String etiqueta) => tester.widget<MetricTile>(find.widgetWithText(MetricTile, etiqueta)).value;

  /// "N alertas · llegada promedio …" del resumen del historial → N.
  int conteoHistorial(WidgetTester tester) =>
      int.parse(tester.widget<Text>(find.textContaining(RegExp(r'^\d+ alertas?'))).data!.split(' ').first);

  Finder tarjeta(String id) => find.byWidgetPredicate((w) => w is AlertCard && w.alert.id == id);

  testWidgets('una alerta atendida pasa de Alertas a Historial y al dashboard con los mismos datos', (tester) async {
    tester.view.physicalSize = const Size(1800, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var desfase = Duration.zero; // para que A-04 vea pasar el tiempo
    final db = MemoriaBaseDatos(latencia: Duration.zero, reloj: () => DateTime.now().add(desfase));
    addTearDown(db.dispose);
    final deps = Dependencias(
      auth: MemoriaAuthRepository(db),
      alertasUsuario: MemoriaAlertaUsuarioRepository(db),
      alertasGuardia: MemoriaAlertaGuardiaRepository(db),
      admin: MemoriaAdminRepository(db),
    );
    final repo = MemoriaAlertaGuardiaRepository(db);

    /// Consulta como otro guardia sin cambiar la pantalla (la base solo sabe del usuario en sesión).
    Future<T> como<T>(String guardiaId, Future<T> Function() consulta) async {
      final anterior = db.usuarioActualId;
      db.usuarioActualId = guardiaId;
      try {
        return await consulta();
      } finally {
        db.usuarioActualId = anterior;
      }
    }

    Future<Set<String>> disponiblesDe(String g) => como(g, () async => {for (final p in await repo.escucharAlertasDisponibles().first) p.alerta.id});
    Future<Set<String>> historialDe(String g) => como(g, () async => {for (final a in await repo.obtenerMiHistorial()) a.id});

    final daniela = (disponibles: await disponiblesDe('grd-2'), historial: await historialDe('grd-2'));

    await deps.sesion.iniciarSesion('guardia@safelink.mx', 'SafeLink1');
    await tester.pumpWidget(SafeLinkApp(dependencias: deps, simular: false));
    await esperar(tester);

    // Las tres pestañas quedan abiertas (con datos de antes) antes de atender la alerta.
    final atendidasAntes = int.parse(valor(tester, 'Atendidas'));
    await pestana(tester, 'Historial');
    final historialAntes = conteoHistorial(tester);
    await pestana(tester, 'Alertas');

    final original = tester.widget<AlertCard>(find.byType(AlertCard).first).alert;
    final id = original.id;

    // Entrante → detalle → aceptar.
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push(AppRoutes.guardIncoming(id));
    await esperar(tester);
    expect(find.text('Alerta entrante'), findsOneWidget);
    await tocar(tester, find.text('Ver detalle'));
    expect(find.text('Detalle de alerta'), findsOneWidget);
    await tocar(tester, find.text('Aceptar alerta'));
    expect(find.text('En camino'), findsOneWidget);
    expect(db.alertaPorId(id).estado, EstadoAlerta.enAtencion);

    // Acercarse hasta la geocerca y marcar llegada.
    for (var i = 0; i < 15 && find.text('Llegué').evaluate().isEmpty; i++) {
      await tocar(tester, find.text('Simular acercamiento (demo)'));
    }
    await tocar(tester, find.text('Llegué'));
    expect(db.alertaPorId(id).estado, EstadoAlerta.guardiaEnLugar);

    // El usuario confirma (simulación existente: 8 s después de "Llegué").
    await tester.pump(const Duration(seconds: 9));
    await esperar(tester);
    final cerrada = db.alertaPorId(id);
    expect(cerrada.estado, EstadoAlerta.cerrada);
    expect(cerrada.guardiaId, 'grd-1');

    // Volver al listado: ya no está.
    await tocar(tester, find.text('Volver al listado'));
    expect(find.text('Alertas cercanas'), findsOneWidget);
    expect(tarjeta(id), findsNothing);

    // Historial (abierto desde antes): aparece con el mismo id, usuario, método, foto y hora.
    await pestana(tester, 'Historial');
    expect(conteoHistorial(tester), historialAntes + 1);
    expect(tarjeta(id), findsOneWidget);
    final enHistorial = tester.widget<AlertCard>(tarjeta(id)).alert;
    expect(enHistorial.usuarioId, original.usuarioId);
    expect(enHistorial.nombreUsuario, original.nombreUsuario);
    expect(enHistorial.metodo, original.metodo);
    expect(enHistorial.fotoUrl, original.fotoUrl);
    expect(enHistorial.disparadaEn, original.disparadaEn);
    expect(enHistorial.estado, EstadoAlerta.cerrada);

    // Dashboard (abierto desde antes): cuenta como atendida hoy y es la última.
    await pestana(tester, 'Inicio');
    expect(int.parse(valor(tester, 'Atendidas')), atendidasAntes + 1);
    expect(tester.widget<AlertCard>(find.byType(AlertCard)).alert.id, id);

    // La otra guardia no ve ningún cambio.
    expect(await disponiblesDe('grd-2'), daniela.disponibles);
    expect(await historialDe('grd-2'), daniela.historial);

    // Una alerta ignorada sale del listado y nunca llega al historial.
    await pestana(tester, 'Alertas');
    final ignorada = tester.widget<AlertCard>(find.byType(AlertCard).first).alert.id;
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push(AppRoutes.guardIncoming(ignorada));
    await esperar(tester);
    await tocar(tester, find.text('Ignorar'));
    expect(tarjeta(ignorada), findsNothing);

    // Las que nadie aceptó escalan "sin respuesta" (A-04) sin guardia: tampoco entran al historial.
    final pendientes = {for (final p in await repo.escucharAlertasDisponibles().first) p.alerta.id, ignorada};
    db.revisarEscalamientos();
    desfase += Duration(seconds: db.config.segundosEscalamientoDemo + 1);
    db.revisarEscalamientos();
    for (final p in pendientes) {
      expect(db.alertaPorId(p).razonEscalamiento, RazonEscalamiento.sinRespuesta, reason: p);
      expect(db.alertaPorId(p).guardiaId, isNull, reason: p);
    }
    await pestana(tester, 'Historial');
    expect(conteoHistorial(tester), historialAntes + 1);
    expect((await repo.obtenerMiHistorial()).map((a) => a.id).toSet().intersection(pendientes), isEmpty);
  });

  test('el dashboard, el historial y obtenerMisMetricas() salen de la misma lista', () async {
    for (final g in ['grd-1', 'grd-2', 'grd-3', 'grd-6', 'grd-8']) {
      final db = MemoriaBaseDatos(latencia: Duration.zero)..usuarioActualId = g;
      final repo = MemoriaAlertaGuardiaRepository(db);
      final historial = await repo.obtenerMiHistorial();
      final metricas = await repo.obtenerMisMetricas();
      // Lo que calcula el dashboard para "todo el historial".
      final delDashboard = ReglaMetricas.deGuardia(g, historial);
      expect(metricas.atendidas, delDashboard.atendidas, reason: g);
      expect(metricas.atendidas, historial.where((a) => a.llegadaEn != null).length, reason: g);
      expect(metricas.promedioAceptacionSeg, delDashboard.promedioAceptacionSeg, reason: g);
      expect(metricas.promedioLlegadaSeg, delDashboard.promedioLlegadaSeg, reason: g);
      expect(metricas.escaladas, delDashboard.escaladas, reason: g);
      expect(historial.every((a) => !a.estado.activa && a.guardiaId == g), isTrue, reason: g);
      db.dispose();
    }
  });
}
