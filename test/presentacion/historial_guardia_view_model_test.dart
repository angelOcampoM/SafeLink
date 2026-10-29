// G-03 Historial del guardia con filtros en memoria (sin volver a pedir al repositorio).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';
import 'package:safelink/presentacion/comun/estado_vista.dart';
import 'package:safelink/presentacion/guardia/historial_guardia_view_model.dart';

import 'espias.dart';

class _HistorialEspia extends AlertaGuardiaEspia {
  _HistorialEspia(this.historial) : super(alerta: alertaPrueba(), guardia: guardiaPrueba());
  final List<Alerta> historial;
  int pedidas = 0;

  @override
  Future<List<Alerta>> obtenerMiHistorial() async {
    pedidas++;
    return historial;
  }
}

Alerta _a(String id, DateTime t, {EstadoAlerta e = EstadoAlerta.cerrada, MetodoDisparo m = MetodoDisparo.toque, int llegadaSeg = 300}) =>
    Alerta(
      id: id,
      usuarioId: 'u',
      guardiaId: 'u-1',
      estado: e,
      metodo: m,
      disparadaEn: t,
      aceptadaEn: t.add(const Duration(minutes: 1)),
      llegadaEn: t.add(Duration(minutes: 1, seconds: llegadaSeg)),
    );

void main() {
  final historial = [
    _a('h1', DateTime(2026, 10, 25, 20), llegadaSeg: 200),
    _a('h2', DateTime(2026, 10, 20, 9), e: EstadoAlerta.escalada, m: MetodoDisparo.agitacion, llegadaSeg: 600),
    _a('h3', DateTime(2026, 10, 3, 14), m: MetodoDisparo.mantener, llegadaSeg: 400),
  ];

  test('carga una vez y filtra en memoria por rango (inclusive), estado y método', () async {
    final repo = _HistorialEspia(historial);
    final vm = HistorialGuardiaViewModel(repo, reloj: () => ahoraPrueba);
    await vm.cargar();
    expect(vm.estado, isA<Listo>());
    expect(vm.filtradas.map((a) => a.id), ['h1', 'h2', 'h3']);

    vm.cambiarRango(DateTime(2026, 10, 20, 15), DateTime(2026, 10, 25));
    expect(vm.filtradas.map((a) => a.id), ['h1', 'h2'], reason: 'días completos: incluye el 20 desde las 00:00 y todo el 25');

    vm.cambiarEstado(EstadoAlerta.escalada);
    expect(vm.filtradas.map((a) => a.id), ['h2']);

    vm.cambiarMetodo(MetodoDisparo.toque);
    expect(vm.filtradas, isEmpty);
    expect(vm.hayFiltros, isTrue);

    vm.limpiarFiltros();
    expect(vm.hayFiltros, isFalse);
    expect(vm.filtradas, hasLength(3));
    expect(repo.pedidas, 1, reason: 'filtrar no vuelve a pedir el historial');
  });

  test('resumen de lo filtrado: conteo y llegada promedio', () async {
    final vm = HistorialGuardiaViewModel(_HistorialEspia(historial), reloj: () => ahoraPrueba);
    await vm.cargar();
    expect(vm.resumen.conteo, 3);
    expect(vm.resumen.promedioLlegadaSeg, 400);

    vm.cambiarMetodo(MetodoDisparo.toque);
    expect(vm.resumen.conteo, 1);
    expect(vm.resumen.promedioLlegadaSeg, 200);

    vm.cambiarMetodo(MetodoDisparo.mantener);
    vm.cambiarEstado(EstadoAlerta.escalada);
    expect(vm.resumen.conteo, 0);
    expect(vm.resumen.promedioLlegadaSeg, 0);
  });

  test('los resultados disponibles salen del historial', () async {
    final vm = HistorialGuardiaViewModel(_HistorialEspia(historial), reloj: () => ahoraPrueba);
    await vm.cargar();
    expect(vm.estadosDisponibles, [EstadoAlerta.cerrada, EstadoAlerta.escalada]);
  });

  test('sin historial queda Vacío (aún no atiende alertas)', () async {
    final vm = HistorialGuardiaViewModel(_HistorialEspia(const []), reloj: () => ahoraPrueba);
    await vm.cargar();
    expect(vm.estado, isA<Vacio>());
    expect(vm.filtradas, isEmpty);
    expect(vm.estadosDisponibles, isEmpty);
  });

  test('los filtros se conservan al recargar', () async {
    final vm = HistorialGuardiaViewModel(_HistorialEspia(historial), reloj: () => ahoraPrueba);
    await vm.cargar();
    vm.cambiarMetodo(MetodoDisparo.agitacion);
    await vm.cargar();
    expect(vm.filtradas.map((a) => a.id), ['h2']);
  });
}
