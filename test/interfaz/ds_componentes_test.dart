// Sistema de diseño — pruebas de interfaz de los componentes compartidos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';
import 'package:safelink/presentacion/comun/widgets/widgets.dart';

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.dark(), home: Scaffold(body: Center(child: child)));

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  testWidgets('SlButton llama a onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(SlButton(label: 'Aceptar', onPressed: () => taps++)));
    await tester.tap(find.text('Aceptar'));
    expect(taps, 1);
  });

  testWidgets('SlButton cumple el objetivo táctil de 56 px', (tester) async {
    await tester.pumpWidget(wrap(SlButton(label: 'Aceptar', onPressed: () {})));
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(AppSizes.touchTarget));
  });

  testWidgets('SlButton en carga no responde y muestra indicador', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(SlButton(label: 'Guardar', loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    expect(taps, 0);
  });

  testWidgets('StatusChip muestra el texto en español de cada estado', (tester) async {
    await tester.pumpWidget(wrap(Wrap(children: [for (final s in EstadoAlerta.values) StatusChip(s)])));
    expect(find.text('Buscando guardia'), findsOneWidget);
    expect(find.text('Guardia en el lugar'), findsOneWidget);
    expect(find.text('Resuelta por administrador'), findsOneWidget);
  });

  testWidgets('TriggerChip marca la agitación como urgente', (tester) async {
    await tester.pumpWidget(wrap(const TriggerChip(MetodoDisparo.agitacion)));
    expect(find.text('Urgente · Agitación'), findsOneWidget);
  });

  testWidgets('SlTextField de contraseña permite mostrar/ocultar', (tester) async {
    await tester.pumpWidget(wrap(const SlTextField(label: 'Contraseña', obscure: true)));
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });

  testWidgets('SlTextField muestra el error que le pasa el ViewModel', (tester) async {
    await tester.pumpWidget(wrap(const SlTextField(label: 'Correo', errorText: 'Correo no válido')));
    expect(find.text('Correo no válido'), findsOneWidget);
  });

  testWidgets('SlStateView pinta los cuatro estados y "Reintentar" en error', (tester) async {
    var reintentos = 0;
    Widget vista(EstadoVista<String> e) => wrap(SlStateView<String>(
          estado: e,
          onRetry: () => reintentos++,
          empty: const EmptyState(icon: Icons.inbox_outlined, title: 'Vacío'),
          builder: (_, d) => Text(d),
        ),);

    await tester.pumpWidget(vista(const Cargando()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(vista(const Vacio()));
    expect(find.text('Vacío'), findsOneWidget);

    await tester.pumpWidget(vista(const ErrorVista('Sin conexión')));
    expect(find.text('Sin conexión'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(reintentos, 1);

    await tester.pumpWidget(vista(const Listo('Hola')));
    expect(find.text('Hola'), findsOneWidget);
  });
}
