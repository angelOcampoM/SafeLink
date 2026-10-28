// A-05 Historial con filtros — los filtros se combinan y el rango es [desde, hasta).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  final d = DateTime(2026, 10, 7);
  Alerta a(String id, int dia, {String? g, EstadoAlerta e = EstadoAlerta.cerrada}) =>
      Alerta(id: id, usuarioId: 'u', guardiaId: g, estado: e, metodo: MetodoDisparo.toque, disparadaEn: d.add(Duration(days: dia)));

  final alertas = [a('1', 0, g: 'g1'), a('2', 1, g: 'g2'), a('3', 2, g: 'g1', e: EstadoAlerta.resueltaPorAdmin)];

  test('sin filtros devuelve todo, más recientes primero', () {
    expect(const FiltroHistorial().aplicar(alertas).map((x) => x.id), ['3', '2', '1']);
  });

  test('rango, guardia y estado combinados', () {
    final f = FiltroHistorial(desde: d, hasta: d.add(const Duration(days: 3)), guardiaId: 'g1', estado: EstadoAlerta.cerrada);
    expect(f.aplicar(alertas).map((x) => x.id), ['1']);
  });

  test('hasta es exclusivo', () {
    expect(FiltroHistorial(hasta: d.add(const Duration(days: 1))).aplicar(alertas).map((x) => x.id), ['1']);
  });
}
