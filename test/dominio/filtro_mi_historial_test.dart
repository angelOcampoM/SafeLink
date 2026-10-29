// G-03 Filtros del historial del guardia: fechas [desde, hasta), resultado y método de disparo.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  Alerta a(String id, DateTime t, {EstadoAlerta e = EstadoAlerta.cerrada, MetodoDisparo m = MetodoDisparo.toque}) =>
      Alerta(id: id, usuarioId: 'u', guardiaId: 'g', estado: e, metodo: m, disparadaEn: t);

  final historial = [
    a('vieja', DateTime(2026, 10, 1, 9)),
    a('escalada', DateTime(2026, 10, 10, 22), e: EstadoAlerta.escalada, m: MetodoDisparo.agitacion),
    a('admin', DateTime(2026, 10, 15, 8), e: EstadoAlerta.resueltaPorAdmin, m: MetodoDisparo.mantener),
    a('reciente', DateTime(2026, 10, 20, 18), m: MetodoDisparo.agitacion),
  ];
  List<String> ids(List<Alerta> r) => [for (final x in r) x.id];

  test('sin filtros: todo, más recientes primero', () {
    const f = FiltroMiHistorial();
    expect(f.hayFiltros, isFalse);
    expect(ids(f.aplicar(historial)), ['reciente', 'admin', 'escalada', 'vieja']);
  });

  test('rango de fechas [desde, hasta)', () {
    final f = FiltroMiHistorial(desde: DateTime(2026, 10, 10), hasta: DateTime(2026, 10, 15));
    expect(ids(f.aplicar(historial)), ['escalada']);
    expect(f.hayFiltros, isTrue);
  });

  test('por resultado (estado)', () {
    expect(ids(const FiltroMiHistorial(estado: EstadoAlerta.cerrada).aplicar(historial)), ['reciente', 'vieja']);
    expect(ids(const FiltroMiHistorial(estado: EstadoAlerta.resueltaPorAdmin).aplicar(historial)), ['admin']);
  });

  test('por método de disparo', () {
    expect(ids(const FiltroMiHistorial(metodo: MetodoDisparo.agitacion).aplicar(historial)), ['reciente', 'escalada']);
    expect(const FiltroMiHistorial(metodo: MetodoDisparo.mantener).cumple(historial[2]), isTrue);
  });

  test('combinados', () {
    final f = FiltroMiHistorial(desde: DateTime(2026, 10, 5), metodo: MetodoDisparo.agitacion, estado: EstadoAlerta.cerrada);
    expect(ids(f.aplicar(historial)), ['reciente']);
    expect(const FiltroMiHistorial(estado: EstadoAlerta.escalada, metodo: MetodoDisparo.toque).aplicar(historial), isEmpty);
  });

  test('estados presentes en el orden del enum y sin repetir', () {
    expect(FiltroMiHistorial.estadosPresentes(historial), [EstadoAlerta.cerrada, EstadoAlerta.escalada, EstadoAlerta.resueltaPorAdmin]);
    expect(FiltroMiHistorial.estadosPresentes(const []), isEmpty);
  });

  test('lista vacía', () {
    expect(const FiltroMiHistorial(metodo: MetodoDisparo.toque).aplicar(const []), isEmpty);
  });
}
