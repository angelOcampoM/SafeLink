// U-01 Permisos — al terminar el registro la app muestra los accesos que pide
// antes de dejar entrar al inicio, y solo esa vez.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/main.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  Future<void> abrirRegistro(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(SafeLinkApp(dependencias: Dependencias.crear(usarNube: false), simular: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();
  }

  Future<void> llenarYRegistrar(WidgetTester tester) async {
    const datos = ['Ana López Ruiz', 'ana@safelink.mx', '7771234567', 'SafeLink1', 'SafeLink1'];
    for (var i = 0; i < datos.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), datos[i]);
    }
    await tester.tap(find.text('Registrarme'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('tras registrarse muestra los tres permisos y su razón de uso', (tester) async {
    await abrirRegistro(tester);
    await llenarYRegistrar(tester);

    expect(find.text('Permisos para protegerte'), findsOneWidget);
    expect(find.text('Cámara'), findsOneWidget);
    expect(find.text('Ubicación'), findsOneWidget);
    expect(find.text('Notificaciones'), findsOneWidget);
    expect(find.textContaining('Puedes cambiar estos permisos'), findsOneWidget);
  });

  testWidgets('"Continuar" lleva al inicio y los permisos no se vuelven a pedir', (tester) async {
    await abrirRegistro(tester);
    await llenarYRegistrar(tester);

    await tester.tap(find.text('Continuar'));
    // El inicio late en bucle (EmergencyButton): pumpAndSettle nunca terminaría.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Toca o mantén presionado'), findsOneWidget);
    expect(find.text('Permisos para protegerte'), findsNothing);
  });
}
