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

  // ── G-01 · La pantalla de inicio de sesión y el rechazo de accesos ──────

  testWidgets('G-01: el login no ofrece registrarse como guardia ni elegir rol', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Lo único que se puede crear desde aquí es una cuenta de usuario protegido.
    expect(find.text('Crear cuenta'), findsOneWidget);
    expect(find.textContaining('Solo los usuarios protegidos'), findsOneWidget);
    expect(find.textContaining('guardia', findRichText: true), findsNothing, reason: 'no hay alta de guardias');
    expect(find.byType(DropdownButton<String>), findsNothing, reason: 'no hay selector de rol');
    expect(find.text('Rol'), findsNothing);
  });

  testWidgets('G-01: un guardia dado de baja recibe un error y no entra', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // luis.nava@safelink.mx existe en la semilla pero está dado de baja.
    await tester.enterText(find.byType(TextFormField).at(0), 'luis.nava@safelink.mx');
    await tester.enterText(find.byType(TextFormField).at(1), 'SafeLink1');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
    expect(find.text('Bienvenido de nuevo'), findsOneWidget, reason: 'sigue en el login');
  });
}
