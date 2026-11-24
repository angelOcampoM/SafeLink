// U-07 (integración) — mientras la alerta está activa, cada posición del
// sensor se guarda en el repositorio; al cerrarse, deja de guardarse.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/datos/memoria_sesion_guardada.dart';
import 'package:safelink/datos/sensores_simulados.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';
import 'package:safelink/presentacion/usuario/seguimiento_ubicacion.dart';

import 'espias.dart';

/// Espía con una alerta activa que se puede abrir y cerrar a voluntad.
class AlertaUsuarioConStream extends AlertaUsuarioEspia {
  final _control = StreamController<Alerta?>.broadcast();

  @override
  Stream<Alerta?> escucharAlertaActiva() => _control.stream;

  void emitir(Alerta? a) => _control.add(a);
  void cerrar() => _control.close();
}

void main() {
  late AlertaUsuarioConStream alertas;
  late UbicacionSimulada ubicacion;
  late SeguimientoUbicacion seguimiento;

  setUp(() {
    alertas = AlertaUsuarioConStream();
    ubicacion = UbicacionSimulada(inicial: puntoAlerta);
    seguimiento = SeguimientoUbicacion(
      alertas: alertas,
      ubicacion: ubicacion,
      sesion: SesionViewModel(AuthEspia(usuarioActual: usuarioPrueba()), MemoriaSesionGuardada()),
    );
    seguimiento.iniciar();
  });

  tearDown(() {
    seguimiento.dispose();
    ubicacion.dispose();
    alertas.cerrar();
  });

  Future<void> asentar() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('sin alerta activa no se transmite nada', () async {
    alertas.emitir(null);
    await asentar();
    ubicacion.mover();
    await asentar();

    expect(seguimiento.transmitiendo, isFalse);
    expect(alertas.ubicacionesEnviadas, isEmpty);
  });

  test('con la alerta activa cada posición sucesiva se guarda', () async {
    alertas.emitir(alertaPrueba());
    await asentar();

    expect(seguimiento.transmitiendo, isTrue);
    ubicacion.mover();
    ubicacion.mover();
    ubicacion.mover();
    await asentar();

    expect(alertas.ubicacionesEnviadas, hasLength(3));
    expect(alertas.ubicacionesEnviadas.first.lat, greaterThan(puntoAlerta.lat));
  });

  test('transmite sin importar el método de disparo', () async {
    alertas.emitir(alertaPrueba());
    await asentar();
    ubicacion.mover();
    await asentar();

    expect(alertas.ubicacionesEnviadas, hasLength(1));
  });

  test('al cerrarse la alerta deja de guardarse la ubicación', () async {
    alertas.emitir(alertaPrueba());
    await asentar();
    ubicacion.mover();
    await asentar();
    expect(alertas.ubicacionesEnviadas, hasLength(1));

    alertas.emitir(alertaPrueba(estado: EstadoAlerta.cerrada));
    await asentar();
    ubicacion.mover();
    ubicacion.mover();
    await asentar();

    expect(seguimiento.transmitiendo, isFalse);
    expect(alertas.ubicacionesEnviadas, hasLength(1), reason: 'no se guardó nada después del cierre');
  });

  test('la transmisión sigue a la alerta activa, no a la pantalla abierta', () async {
    alertas.emitir(alertaPrueba());
    await asentar();
    final id = seguimiento.alertaSeguida;

    // Vuelve a emitir la misma alerta (la vista se reconstruyó, por ejemplo).
    alertas.emitir(alertaPrueba());
    await asentar();

    expect(seguimiento.alertaSeguida, id, reason: 'no se resuscribe ni duplica envíos');
    ubicacion.mover();
    await asentar();
    expect(alertas.ubicacionesEnviadas, hasLength(1));
  });
}
