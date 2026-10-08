// U-02 Inicio de sesión — prueba de interfaz con datos mock.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/app.dart';
import 'package:safelink/core/theme/theme.dart';
import 'package:safelink/data/dependencies.dart';

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  testWidgets('muestra errores de validación con campos vacíos', (tester) async {
    await tester.pumpWidget(SafeLinkApp(deps: AppDependencies()));
    await tester.pumpAndSettle();

    expect(find.text('Inicia sesión'), findsOneWidget);
    await tester.tap(find.text('Entrar'));
    await tester.pump();

    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
  });

  testWidgets('credenciales incorrectas muestran aviso', (tester) async {
    await tester.pumpWidget(SafeLinkApp(deps: AppDependencies()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'usuario@safelink.mx');
    await tester.enterText(find.byType(TextFormField).at(1), 'incorrecta');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
  });
}
