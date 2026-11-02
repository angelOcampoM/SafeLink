// G-03 Dashboard de Inicio del guardia en la app real (memoria, sin simulaciones):
// guardia en turno, andres.figueroa fuera de turno y sofia.rendon sin zona.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_admin_repository.dart';
import 'package:safelink/datos/memoria_alerta_guardia_repository.dart';
import 'package:safelink/datos/memoria_alerta_usuario_repository.dart';
import 'package:safelink/datos/memoria_auth_repository.dart';
import 'package:safelink/datos/memoria_base_datos.dart';
import 'package:safelink/main.dart';
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

  Future<void> abrir(WidgetTester tester, String correo) async {
    tester.view.physicalSize = const Size(1800, 4800);
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
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.tap(f);
    await esperar(tester);
  }

  /// Valor del MetricTile con esa etiqueta.
  String valor(WidgetTester tester, String etiqueta) => tester.widget<MetricTile>(find.widgetWithText(MetricTile, etiqueta)).value;

  testWidgets('guardia en turno: turno, disponibles, métricas por periodo, gráfica y última alerta', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');

    expect(find.text('En turno'), findsOneWidget);
    expect(find.text('Termina en'), findsOneWidget);
    expect(find.text('Ubicación actualizada'), findsOneWidget);
    expect(find.text('ALERTAS DISPONIBLES'), findsOneWidget);
    expect(valor(tester, 'Disponibles ahora'), '4');
    expect(valor(tester, 'Urgentes'), '1');
    expect(find.text('No estás recibiendo alertas'), findsNothing);

    expect(find.text('MIS MÉTRICAS · HOY'), findsOneWidget);
    expect(find.text('MIS ALERTAS POR HORA'), findsOneWidget);
    final hoy = int.parse(valor(tester, 'Atendidas'));

    await tocar(tester, find.widgetWithText(ChoiceChip, '30 días'));
    expect(find.text('MIS MÉTRICAS · 30 DÍAS'), findsOneWidget);
    expect(int.parse(valor(tester, 'Atendidas')), greaterThan(hoy));
    expect(find.text('Cerradas con confirmación'), findsOneWidget);

    expect(find.text('ÚLTIMA ALERTA ATENDIDA'), findsOneWidget);
    expect(find.byType(AlertCard), findsOneWidget);
  });

  testWidgets('"Ver historial" lleva a la pestaña Historial', (tester) async {
    await abrir(tester, 'guardia@safelink.mx');
    await tocar(tester, find.text('Ver historial'));
    expect(find.widgetWithText(AppBar, 'Historial'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('andres.figueroa fuera de turno: banner, cuánto falta y métricas visibles', (tester) async {
    await abrir(tester, 'andres.figueroa@safelink.mx');
    expect(find.text('Fuera de turno'), findsOneWidget);
    expect(find.text('No estás recibiendo alertas'), findsOneWidget);
    expect(find.text('Empieza en'), findsOneWidget);
    expect(find.text('ALERTAS DISPONIBLES'), findsNothing);
    expect(find.text('MIS MÉTRICAS · HOY'), findsOneWidget);
    expect(find.text('ÚLTIMA ALERTA ATENDIDA'), findsOneWidget);
  });

  testWidgets('sofia.rendon sin zona: banner, radio sin asignar y sin historial', (tester) async {
    await abrir(tester, 'sofia.rendon@safelink.mx');
    expect(find.text('Sin zona'), findsOneWidget);
    expect(find.textContaining('zona asignada'), findsOneWidget);
    expect(find.text('Sin asignar'), findsOneWidget);
    expect(valor(tester, 'Atendidas'), '0');
    expect(find.textContaining('Aún no atiendes alertas'), findsOneWidget);
  });
}
