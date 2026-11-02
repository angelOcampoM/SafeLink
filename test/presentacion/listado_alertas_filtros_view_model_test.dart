// G-03 Filtros del listado: el filtro persiste entre emisiones y el banner de "alerta entrante" lo ignora.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/guardia/listado_alertas_view_model.dart';
import 'package:safelink/presentacion/sesion/sesion_view_model.dart';

import 'espias.dart';

/// Espía cuyo listado emite lo que la prueba mande.
class _GuardiaConStream extends AlertaGuardiaEspia {
  _GuardiaConStream() : super(alerta: alertaPrueba(), guardia: guardiaPrueba());
  final controlador = StreamController<List<AlertaPriorizada>>();

  @override
  Stream<List<AlertaPriorizada>> escucharAlertasDisponibles() => controlador.stream;
}

AlertaPriorizada _p(String id, double metros, {MetodoDisparo m = MetodoDisparo.toque}) => AlertaPriorizada(
      Alerta(id: id, usuarioId: 'u', estado: EstadoAlerta.buscando, metodo: m, disparadaEn: ahoraPrueba, fotoUrl: 'f'),
      metros,
      0,
      0,
    );

void main() {
  late _GuardiaConStream repo;
  late ListadoAlertasViewModel vm;

  setUp(() async {
    repo = _GuardiaConStream();
    vm = ListadoAlertasViewModel(repo, SesionViewModel(AuthEspia()), reloj: () => ahoraPrueba);
    await vm.iniciar();
  });

  tearDown(() {
    vm.dispose();
    repo.controlador.close();
  });

  Future<void> emitir(List<AlertaPriorizada> l) async {
    repo.controlador.add(l);
    await Future<void>.delayed(Duration.zero);
  }

  test('el filtro se aplica y persiste cuando llega una alerta nueva', () async {
    await emitir([_p('a', 300), _p('b', 2000, m: MetodoDisparo.mantener)]);
    vm.cambiarMetodo(MetodoDisparo.toque);
    expect(vm.filtradas.map((p) => p.alerta.id), ['a']);
    expect(vm.total, 2);
    expect(vm.hayFiltros, isTrue);

    await emitir([_p('a', 300), _p('b', 2000, m: MetodoDisparo.mantener), _p('c', 700)]);
    expect(vm.filtro.metodo, MetodoDisparo.toque, reason: 'el filtro no se pierde con la emisión');
    expect(vm.filtradas.map((p) => p.alerta.id), ['a', 'c']);
    expect(vm.total, 3);
  });

  test('el banner de alerta entrante avisa aunque el filtro la oculte', () async {
    await emitir([_p('a', 300)]);
    vm.cambiarDistancia(500);

    await emitir([_p('a', 300), _p('lejana', 2500, m: MetodoDisparo.agitacion)]);
    expect(vm.filtradas.map((p) => p.alerta.id), ['a']);
    expect(vm.entrante?.alerta.id, 'lejana');
  });

  test('cambiar cada filtro conserva los demás y limpiar vuelve a lo predeterminado', () async {
    await emitir([_p('a', 300), _p('b', 900)]);
    vm.cambiarMetodo(MetodoDisparo.toque);
    vm.cambiarDistancia(1000);
    vm.cambiarEvidencia(FiltroEvidencia.conFoto);
    vm.cambiarOrden(OrdenAlertasDisponibles.antiguas);
    expect(vm.filtro.metodo, MetodoDisparo.toque);
    expect(vm.filtro.distanciaMaxMetros, 1000);
    expect(vm.filtro.evidencia, FiltroEvidencia.conFoto);
    expect(vm.filtro.orden, OrdenAlertasDisponibles.antiguas);

    vm.limpiarFiltros();
    expect(vm.hayFiltros, isFalse);
    expect(vm.filtradas, hasLength(2));
  });

  test('sin alertas: filtradas vacía y total 0', () async {
    await emitir(const []);
    expect(vm.filtradas, isEmpty);
    expect(vm.total, 0);
  });
}
