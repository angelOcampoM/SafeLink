// Pruebas de interfaz de G-04: la foto se amplía a pantalla completa y el
// detalle indica qué dato falta. Widgets puros, sin la app completa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/tema/theme.dart';
import 'package:safelink/presentacion/guardia/widgets/widgets_guardia.dart';

const _url = 'https://ejemplo.mx/foto.jpg';
const _etiqueta = 'Fotografía del entorno de la alerta';

Widget envolver(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(padding: AppSpacing.screen, child: child)),
    );

/// Deja la imagen en la caché de Flutter para que `Image.network` no salga a la
/// red. Decodificar una imagen es trabajo real: va con `runAsync`.
Future<void> fotoEnCache(WidgetTester tester, String url) async {
  await tester.runAsync(() async {
    final imagen = await createTestImage(width: 4, height: 3);
    imageCache.putIfAbsent(
      NetworkImage(url),
      () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: imagen))),
    );
  });
}

/// Rutas, Hero y visor animan: pumps fijos en vez de `pumpAndSettle`.
Future<void> bombear(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Alerta alerta({PuntoGeo? ubicacion, int? rumbo}) => Alerta(
      id: 'alt-x',
      usuarioId: 'usr-1',
      nombreUsuario: 'Rosa María Díaz',
      estado: EstadoAlerta.pendienteUbicacion,
      metodo: MetodoDisparo.toque,
      disparadaEn: DateTime(2026, 11, 28, 10, 30),
      ubicacion: ubicacion,
      rumbo: rumbo,
    );

void main() {
  setUpAll(AppTypography.useSystemFontForTests);

  // Cada prueba parte de una caché de imágenes vacía: si no, la foto de una
  // prueba "cargaría" en la siguiente sin pasar por la red.
  setUp(() {
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  // ── G-04, criterio 3: la foto se amplía ──────────────────────────────────

  testWidgets('G-04: la foto se amplía a pantalla completa y se cierra', (tester) async {
    await fotoEnCache(tester, _url);
    final semantica = tester.ensureSemantics();

    await tester.pumpWidget(envolver(const FotoEvidencia(url: _url, heroTag: 'foto-alt-1')));
    await bombear(tester);

    expect(find.bySemanticsLabel('Ampliar fotografía'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Ampliar fotografía'));
    await bombear(tester);

    expect(find.byType(VisorFoto), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget, reason: 'el visor permite zoom');
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.bySemanticsLabel(_etiqueta), findsOneWidget, reason: 'lector de pantalla');

    // D23: el visor solo muestra la foto.
    expect(find.text('Compartir'), findsNothing);
    expect(find.text('Guardar'), findsNothing);

    await tester.tap(find.byTooltip('Cerrar'));
    await bombear(tester);

    expect(find.byType(VisorFoto), findsNothing);
    expect(find.byType(FotoEvidencia), findsOneWidget, reason: 'vuelve al detalle');
    semantica.dispose();
  });

  testWidgets('G-04: el doble toque acerca la foto y la vuelve a alejar', (tester) async {
    await fotoEnCache(tester, _url);
    await tester.pumpWidget(envolver(const FotoEvidencia(url: _url, heroTag: 'foto-alt-1')));
    await bombear(tester);

    await tester.tap(find.byType(InkWell));
    await bombear(tester);

    final visor = find.byType(InteractiveViewer);
    expect(visor, findsOneWidget);
    double escala() =>
        tester.widget<InteractiveViewer>(visor).transformationController!.value.getMaxScaleOnAxis();
    expect(escala(), 1.0);

    final centro = tester.getCenter(visor);
    await tester.tapAt(centro);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centro);
    await tester.pump();
    expect(escala(), 2.0, reason: 'el doble toque acerca');

    await tester.tapAt(centro);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centro);
    await tester.pump();
    expect(escala(), 1.0, reason: 'otro doble toque vuelve a la foto completa');

    // Deja vencer el temporizador del reconocedor de doble toque.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('G-04: la miniatura es un solo nodo "Ampliar fotografía"', (tester) async {
    await fotoEnCache(tester, _url);
    final semantica = tester.ensureSemantics();

    await tester.pumpWidget(envolver(const FotoEvidencia(url: _url, heroTag: 'foto-alt-1')));
    await bombear(tester);

    expect(find.bySemanticsLabel('Ampliar fotografía').evaluate().length, 1, reason: 'un solo nodo para el lector');
    semantica.dispose();
  });

  testWidgets('G-04: sin foto no se puede ampliar y el aviso no cambia', (tester) async {
    await tester.pumpWidget(envolver(const FotoEvidencia(url: null)));

    expect(find.text('Fotografía no disponible'), findsOneWidget);
    expect(find.descendant(of: find.byType(FotoEvidencia), matching: find.byType(InkWell)), findsNothing);
    expect(find.byType(VisorFoto), findsNothing);
  });

  testWidgets('G-04: si la foto no carga, avisa y no se puede ampliar', (tester) async {
    await tester.pumpWidget(envolver(const FotoEvidencia(url: _url)));
    // El cliente HTTP falso de las pruebas responde fuera del reloj simulado.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await bombear(tester);

    expect(find.text('No se pudo cargar la foto'), findsOneWidget);
    expect(find.descendant(of: find.byType(FotoEvidencia), matching: find.byType(InkWell)), findsNothing);
    expect(find.byType(VisorFoto), findsNothing);
  });

  // ── G-04, criterio 4: se indica qué dato falta ───────────────────────────

  testWidgets('G-04: sin ubicación la tarjeta dice "Ubicación no disponible"', (tester) async {
    final a = alerta(rumbo: 40);
    await tester.pumpWidget(envolver(TarjetaDatosAlerta(alerta: a, ahora: a.disparadaEn)));

    expect(find.text('Ubicación no disponible'), findsOneWidget);
    expect(find.text('Distancia'), findsNothing);
    expect(find.text('Rumbo no disponible'), findsNothing, reason: 'el rumbo sí existe');
  });

  testWidgets('G-04: con ubicación la tarjeta muestra la distancia como hoy', (tester) async {
    final a = alerta(ubicacion: const PuntoGeo(18.92, -99.23), rumbo: 40);
    await tester.pumpWidget(envolver(TarjetaDatosAlerta(alerta: a, ahora: a.disparadaEn, distancia: 640)));

    expect(find.text('Distancia'), findsOneWidget);
    expect(find.text('640 m'), findsOneWidget);
    expect(find.text('Ubicación no disponible'), findsNothing);
  });

  testWidgets('G-04: sin rumbo sigue el aviso "Rumbo no disponible"', (tester) async {
    final a = alerta(ubicacion: const PuntoGeo(18.92, -99.23));
    await tester.pumpWidget(envolver(TarjetaDatosAlerta(alerta: a, ahora: a.disparadaEn, distancia: 640)));

    expect(find.text('Rumbo no disponible'), findsOneWidget);
    expect(find.text('Distancia'), findsOneWidget);
  });
}
