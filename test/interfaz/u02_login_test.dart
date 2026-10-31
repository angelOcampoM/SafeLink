// U-02 Inicio de sesión — prueba de interfaz con la app completa armada en memoria.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/main.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  Widget app() => SafeLinkApp(dependencias: Dependencias.crear(usarNube: false), simular: false);

  testWidgets('muestra errores de validación con campos vacíos', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('credenciales incorrectas muestran aviso', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'usuario@safelink.mx');
    await tester.enterText(find.byType(TextFormField).at(1), 'incorrecta');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
  });

  testWidgets('el primer inicio de sesión pide permisos y después lleva al botón de alerta', (tester) async {
    tester.view.physicalSize = const Size(1800, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'usuario@safelink.mx');
    await tester.enterText(find.byType(TextFormField).at(1), 'SafeLink1');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Permisos para protegerte'), findsOneWidget);

    await tester.tap(find.text('Continuar'));
    // El inicio late en bucle (EmergencyButton): pumpAndSettle nunca terminaría.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Toca o mantén presionado'), findsOneWidget);
    expect(find.text('Permisos para protegerte'), findsNothing);
  });
}
