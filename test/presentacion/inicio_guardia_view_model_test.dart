// G-03 Dashboard de Inicio del guardia: periodos, cero alertas, fuera de turno y sin zona.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/guardia/inicio_guardia_view_model.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

/// Espía con historial configurable y un listado que emite lo que mande la prueba.
class _InicioEspia extends AlertaGuardiaEspia {
  _InicioEspia({this.historial = const [], Guardia? g}) : super(alerta: alertaPrueba(), guardia: g ?? guardiaPrueba());
  final List<Alerta> historial;
  final controlador = StreamController<List<AlertaPriorizada>>();
  int suscripciones = 0;

  @override
  Future<List<Alerta>> obtenerMiHistorial() async => historial;

  @override
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles() {
    suscripciones++;
    return controlador.stream;
  }
}

/// Alerta mía: aceptada en 60 s y llegada [llegadaSeg] después.
Alerta _mia(String id, DateTime t, {EstadoAlerta e = EstadoAlerta.cerrada, int llegadaSeg = 300, RazonEscalamiento? razon}) => Alerta(
      id: id,
      usuarioId: 'x',
      guardiaId: 'u-1',
      estado: e,
      metodo: MetodoDisparo.toque,
      disparadaEn: t,
      aceptadaEn: t.add(const Duration(seconds: 60)),
      llegadaEn: t.add(Duration(seconds: 60 + llegadaSeg)),
      razonEscalamiento: razon,
    );

void main() {
  // ahoraPrueba = 26/10/2026 13:00; guardiaPrueba: turno 08:00–16:00 con zona.
  final historial = [
    _mia('hoy', DateTime(2026, 10, 26, 10), llegadaSeg: 200),
    _mia('hace3', DateTime(2026, 10, 23, 21), e: EstadoAlerta.escalada, razon: RazonEscalamiento.sinConfirmacion, llegadaSeg: 400),
    _mia('hace20', DateTime(2026, 10, 6, 22)),
  ];

  InicioGuardiaViewModel crear(_InicioEspia repo, {DateTime? ahora}) =>
      InicioGuardiaViewModel(repo, SesionViewModel(AuthEspia()), reloj: () => ahora ?? ahoraPrueba);

  test('en turno: tiempo restante, última alerta y métricas de Hoy', () async {
    final repo = _InicioEspia(historial: historial);
    final vm = crear(repo);
    await vm.cargar();

    expect(vm.estadoTurno, EstadoTurno.enTurno);
    expect(vm.minutosRestantesTurno, 180);
    expect(vm.minutosParaIniciarTurno, isNull);
    expect(vm.ultima.datos?.id, 'hoy');

    final m = vm.metricas.datos!;
    expect(vm.periodo, PeriodoInicio.hoy);
    expect(m.guardia.atendidas, 1);
    expect(m.guardia.promedioLlegadaSeg, 200);
    expect(m.tasaCierreConfirmado, 1.0);
    expect(m.alertasPorHora[10], 1);
    expect(m.alertasPorHora.reduce((a, b) => a + b), 1);
    vm.dispose();
  });

  test('cambiar de periodo recalcula sin volver a pedir datos', () async {
    final vm = crear(_InicioEspia(historial: historial));
    await vm.cargar();

    vm.cambiarPeriodo(PeriodoInicio.dias7);
    var m = vm.metricas.datos!;
    expect(m.guardia.atendidas, 2);
    expect(m.guardia.escaladas, 1);
    expect(m.tasaCierreConfirmado, 0.5);

    vm.cambiarPeriodo(PeriodoInicio.dias30);
    m = vm.metricas.datos!;
    expect(m.guardia.atendidas, 3);
    expect(m.alertasPorHora[22], 1);
    vm.dispose();
  });

  test('con cero alertas todo vale 0 y no hay última alerta', () async {
    final vm = crear(_InicioEspia());
    await vm.cargar();

    final m = vm.metricas.datos!;
    expect(m.guardia.atendidas, 0);
    expect(m.guardia.promedioAceptacionSeg, 0);
    expect(m.guardia.promedioLlegadaSeg, 0);
    expect(m.guardia.escaladas, 0);
    expect(m.tasaCierreConfirmado, 0);
    expect(m.alertasPorHora, everyElement(0));
    expect(vm.ultima, isA<Vacio>());
    vm.dispose();
  });

  test('alertas disponibles: total y urgentes desde el stream', () async {
    final repo = _InicioEspia(historial: historial);
    final vm = crear(repo);
    await vm.cargar();
    expect(repo.suscripciones, 1);

    AlertaPriorizada p(String id, MetodoDisparo m) =>
        AlertaPriorizada(Alerta(id: id, usuarioId: 'x', estado: EstadoAlerta.buscando, metodo: m, disparadaEn: ahoraPrueba), 100, 0, 0);
    repo.controlador.add([p('a', MetodoDisparo.agitacion), p('b', MetodoDisparo.toque), p('c', MetodoDisparo.mantener)]);
    await Future<void>.delayed(Duration.zero);

    expect(vm.totalDisponibles, 3);
    expect(vm.urgentesDisponibles, 1);
    vm.dispose();
    await repo.controlador.close();
  });

  test('fuera de turno: no escucha alertas, pero ve métricas y cuánto falta para su turno', () async {
    final repo = _InicioEspia(historial: historial);
    final vm = crear(repo, ahora: DateTime(2026, 10, 26, 20));
    await vm.cargar();

    expect(vm.estadoTurno, EstadoTurno.fueraDeTurno);
    expect(vm.motivoNoDisponible, contains('Tu turno es de 08:00 a 16:00'));
    expect(vm.minutosRestantesTurno, isNull);
    expect(vm.minutosParaIniciarTurno, 720);
    expect(repo.suscripciones, 0);
    expect(vm.metricas, isA<Listo>());
    expect(vm.ultima.datos?.id, 'hoy');
    vm.dispose();
  });

  test('sin zona: estado "Sin zona" y no escucha alertas', () async {
    final base = guardiaPrueba();
    final sinZona = Guardia(
      usuario: base.usuario,
      perfil: const PerfilGuardia(usuarioId: 'u-1', inicioTurno: '08:00', finTurno: '16:00', centroCobertura: null, radioCoberturaMetros: null),
    );
    final repo = _InicioEspia(g: sinZona);
    final vm = crear(repo);
    await vm.cargar();

    expect(vm.estadoTurno, EstadoTurno.sinZona);
    expect(vm.motivoNoDisponible, contains('zona asignada'));
    expect(repo.suscripciones, 0);
    expect(vm.metricas, isA<Listo>());
    vm.dispose();
  });
}
