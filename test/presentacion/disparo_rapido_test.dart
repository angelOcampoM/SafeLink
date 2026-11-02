// U-05 (integración) — el doble clic registra la alerta con su método y vibra;
// una sola pulsación no registra nada, y con el servicio apagado tampoco.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/sensores_simulados.dart';
import 'package:safelink/datos/servicio_disparo_rapido_simulado.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/usuario/captura_evidencia.dart';
import 'package:safelink/presentacion/usuario/disparo_rapido.dart';

import 'espias.dart';

void main() {
  late AlertaUsuarioEspia alertas;
  late ServicioDisparoRapidoSimulado servicio;
  late VibradorSimulado vibrador;
  late DisparoRapido disparo;

  setUp(() {
    alertas = AlertaUsuarioEspia();
    servicio = ServicioDisparoRapidoSimulado();
    vibrador = VibradorSimulado();
    disparo = DisparoRapido(
      servicio: servicio,
      vibrador: vibrador,
      alertas: alertas,
      evidencia: CapturaEvidencia(
        camara: CamaraSimulada(),
        ubicacion: UbicacionSimulada(inicial: puntoAlerta),
        brujula: BrujulaSimulada(),
      ),
      reloj: () => ahoraPrueba,
    );
  });

  tearDown(() {
    disparo.dispose();
    servicio.dispose();
  });

  /// Deja correr el stream y las capturas asíncronas.
  Future<void> asentar() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('el doble clic registra la alerta con su método y hace vibrar el teléfono', () async {
    await disparo.activar();
    servicio.pulsar(ahoraPrueba);
    servicio.pulsar(ahoraPrueba.add(const Duration(milliseconds: 200)));
    await asentar();

    expect(alertas.creadas, [MetodoDisparo.dobleClicVolumen]);
    expect(vibrador.veces, 1);
  });

  test('la alerta por doble clic viaja con la evidencia completa', () async {
    await disparo.activar();
    servicio.pulsar(ahoraPrueba);
    servicio.pulsar(ahoraPrueba.add(const Duration(milliseconds: 200)));
    await asentar();

    final e = alertas.evidencias.single;
    expect(e.rutaFoto, isNotNull);
    expect(e.ubicacion, puntoAlerta);
    expect(e.rumbo, 35);
  });

  test('una sola pulsación no registra ninguna alerta ni vibra', () async {
    await disparo.activar();
    servicio.pulsar(ahoraPrueba);
    await asentar();

    expect(alertas.creadas, isEmpty);
    expect(vibrador.veces, 0);
  });

  test('con el servicio apagado el doble clic no registra nada', () async {
    servicio.pulsar(ahoraPrueba);
    servicio.pulsar(ahoraPrueba.add(const Duration(milliseconds: 200)));
    await asentar();

    expect(disparo.activo, isFalse);
    expect(alertas.creadas, isEmpty);
  });

  test('al activar vive la notificación permanente y al desactivar se va', () async {
    expect(disparo.notificacionVisible, isFalse);

    await disparo.activar();
    expect(disparo.activo, isTrue);
    expect(disparo.notificacionVisible, isTrue, reason: 'Android la exige mientras el servicio vive');

    await disparo.desactivar();
    expect(disparo.activo, isFalse);
    expect(disparo.notificacionVisible, isFalse);
  });

  test('tras desactivar, el doble clic deja de registrar alertas', () async {
    await disparo.activar();
    await disparo.desactivar();

    servicio.pulsar(ahoraPrueba);
    servicio.pulsar(ahoraPrueba.add(const Duration(milliseconds: 200)));
    await asentar();

    expect(alertas.creadas, isEmpty);
  });

  test('la pulsación pendiente no sobrevive a apagar y encender el servicio', () async {
    await disparo.activar();
    servicio.pulsar(ahoraPrueba);
    await disparo.desactivar();
    await disparo.activar();

    servicio.pulsar(ahoraPrueba.add(const Duration(milliseconds: 100)));
    await asentar();

    expect(alertas.creadas, isEmpty, reason: 'la primera pulsación se olvidó al apagar');
  });
}
