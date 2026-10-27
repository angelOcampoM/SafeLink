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

    expect(find.text('Inicia sesión'), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('credenciales incorrectas muestran aviso', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'usuario@safelink.mx');
    await tester.enterText(find.byType(TextFormField).at(1), 'incorrecta');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
  });

  testWidgets('con credenciales correctas el router lleva al inicio del usuario', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'usuario@safelink.mx');
    await tester.enterText(find.byType(TextFormField).at(1), 'SafeLink1');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Hola, Fernanda'), findsOneWidget);
  });
}
