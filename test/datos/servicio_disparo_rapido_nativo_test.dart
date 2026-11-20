// U-05 · El servicio real de Android, con los canales nativos simulados.
// Lo que estas pruebas fijan es el contrato con Kotlin: qué se le manda, qué se espera
// de vuelta y que una plataforma sin implementación nativa no tire la app.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/servicio_disparo_rapido_nativo.dart';
import 'package:safelink/dominio/regla_doble_clic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canalMetodos = MethodChannel('prueba/volumen');
  const nombreEventos = 'prueba/volumen_eventos';
  const canalEventos = EventChannel(nombreEventos);

  late List<MethodCall> llamadas;
  /// Lo que responde el falso nativo a `accesibilidadActiva`.
  late bool accesibilidadNativa;

  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Empuja un evento por el EventChannel como lo haría Kotlin.
  Future<void> emitir(Object? evento) async {
    await mensajero.handlePlatformMessage(
      nombreEventos,
      const StandardMethodCodec().encodeSuccessEnvelope(evento),
      (_) {},
    );
  }

  setUp(() {
    llamadas = [];
    accesibilidadNativa = true;
    mensajero.setMockMethodCallHandler(canalMetodos, (llamada) async {
      llamadas.add(llamada);
      if (llamada.method == 'accesibilidadActiva') return accesibilidadNativa;
      return null;
    });
    // El EventChannel se "abre" respondiendo a listen/cancel.
    mensajero.setMockMethodCallHandler(const MethodChannel(nombreEventos), (_) async => null);
  });

  tearDown(() {
    mensajero.setMockMethodCallHandler(canalMetodos, null);
    mensajero.setMockMethodCallHandler(const MethodChannel(nombreEventos), null);
  });

  ServicioDisparoRapidoNativo crear({Duration? ventana}) => ServicioDisparoRapidoNativo(
        metodos: canalMetodos,
        eventos: canalEventos,
        ventana: ventana ?? ReglaDobleClic.ventanaPorDefecto,
      );

  test('nace apagado, igual que el simulado', () {
    final servicio = crear();
    expect(servicio.enEjecucion, isFalse);
    expect(servicio.notificacionVisible, isFalse);
  });

  test('iniciar le manda a Kotlin la misma ventana que usa la regla del dominio', () async {
    final servicio = crear();
    await servicio.iniciar();

    expect(llamadas.map((l) => l.method), contains('iniciar'));
    final iniciar = llamadas.firstWhere((l) => l.method == 'iniciar');
    expect(iniciar.arguments, {'ventanaMs': ReglaDobleClic.ventanaPorDefecto.inMilliseconds});
    expect(servicio.enEjecucion, isTrue);
    expect(servicio.notificacionVisible, isTrue);
    await servicio.dispose();
  });

  test('una ventana distinta llega tal cual al nativo', () async {
    final servicio = crear(ventana: const Duration(milliseconds: 900));
    await servicio.iniciar();
    final iniciar = llamadas.firstWhere((l) => l.method == 'iniciar');
    expect(iniciar.arguments, {'ventanaMs': 900});
    await servicio.dispose();
  });

  test('iniciar dos veces no vuelve a llamar al nativo', () async {
    final servicio = crear();
    await servicio.iniciar();
    await servicio.iniciar();
    expect(llamadas.where((l) => l.method == 'iniciar'), hasLength(1));
    await servicio.dispose();
  });

  test('cada pulsación del nativo sale por el stream con su hora', () async {
    final servicio = crear();
    await servicio.iniciar();
    final recibidas = <DateTime>[];
    final sub = servicio.pulsaciones.listen(recibidas.add);

    await emitir({'tipo': 'pulsacion', 'timestamp': 1_700_000_000_000});
    await emitir({'tipo': 'pulsacion', 'timestamp': 1_700_000_000_400});
    await Future<void>.delayed(Duration.zero);

    expect(recibidas, hasLength(2));
    expect(recibidas.first.millisecondsSinceEpoch, 1_700_000_000_000);
    expect(recibidas.last.millisecondsSinceEpoch, 1_700_000_000_400);
    await sub.cancel();
    await servicio.dispose();
  });

  test('el nativo decide el doble clic: aquí solo viajan pulsaciones sueltas', () async {
    // Dos pulsaciones dentro de la ventana son un doble clic para ReglaDobleClic,
    // que es quien decide; el servicio no interpreta nada.
    final servicio = crear();
    await servicio.iniciar();
    final regla = ReglaDobleClic();
    final disparos = <DateTime>[];
    final sub = servicio.pulsaciones.listen((cuando) {
      if (regla.registrar(cuando)) disparos.add(cuando);
    });

    await emitir({'tipo': 'pulsacion', 'timestamp': 1_700_000_000_000});
    await emitir({'tipo': 'pulsacion', 'timestamp': 1_700_000_000_300});
    await emitir({'tipo': 'pulsacion', 'timestamp': 1_700_000_900_000}); // suelta, muy tarde
    await Future<void>.delayed(Duration.zero);

    expect(disparos, hasLength(1), reason: 'tres pulsaciones = un doble clic y una suelta');
    await sub.cancel();
    await servicio.dispose();
  });

  test('un evento de otro tipo o mal formado se ignora', () async {
    final servicio = crear();
    await servicio.iniciar();
    final recibidas = <DateTime>[];
    final sub = servicio.pulsaciones.listen(recibidas.add);

    await emitir({'tipo': 'otra_cosa', 'timestamp': 1});
    await emitir('texto suelto');
    await emitir(null);
    await Future<void>.delayed(Duration.zero);

    expect(recibidas, isEmpty);
    await sub.cancel();
    await servicio.dispose();
  });

  test('con el servicio detenido no llega nada, igual que en el teléfono', () async {
    final servicio = crear();
    await servicio.iniciar();
    final recibidas = <DateTime>[];
    final sub = servicio.pulsaciones.listen(recibidas.add);

    await servicio.detener();
    expect(servicio.enEjecucion, isFalse);
    expect(llamadas.map((l) => l.method), contains('detener'));

    await emitir({'tipo': 'pulsacion', 'timestamp': 1_700_000_000_000});
    await Future<void>.delayed(Duration.zero);
    expect(recibidas, isEmpty);

    await sub.cancel();
    await servicio.dispose();
  });

  test('listoEnElSistema refleja si el servicio de accesibilidad está encendido', () async {
    final servicio = crear();
    expect(await servicio.listoEnElSistema(), isTrue);
    accesibilidadNativa = false;
    expect(await servicio.listoEnElSistema(), isFalse);
  });

  test('abrirAjustesDelSistema abre los Ajustes de accesibilidad', () async {
    final servicio = crear();
    await servicio.abrirAjustesDelSistema();
    expect(llamadas.map((l) => l.method), contains('abrirAjustesAccesibilidad'));
  });

  group('sin implementación nativa (plataforma sin el servicio)', () {
    setUp(() {
      // Sin manejador, el canal lanza MissingPluginException.
      mensajero.setMockMethodCallHandler(canalMetodos, null);
    });

    test('iniciar no revienta y deja el servicio apagado', () async {
      final servicio = crear();
      await servicio.iniciar();
      expect(servicio.enEjecucion, isFalse);
      expect(servicio.notificacionVisible, isFalse);
    });

    test('detener, listoEnElSistema y abrir ajustes tampoco revientan', () async {
      final servicio = crear();
      await servicio.detener();
      expect(await servicio.listoEnElSistema(), isFalse);
      await servicio.abrirAjustesDelSistema();
    });
  });

  test('un error del nativo apaga el servicio en lugar de dejarlo a medias', () async {
    mensajero.setMockMethodCallHandler(canalMetodos, (llamada) async {
      llamadas.add(llamada);
      throw PlatformException(code: 'SIN_SERVICIO');
    });
    final servicio = crear();
    await servicio.iniciar();
    expect(servicio.enEjecucion, isFalse);
  });
}
