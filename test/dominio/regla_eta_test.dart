// U-08 (unitaria) — "la función de tiempo estimado devuelve un valor menor
// conforme disminuye la distancia del guardia".
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/regla_eta.dart';

void main() {
  int eta(double metros) => ReglaEta.segundos(distanciaMetros: metros, metrosPorMinutoGuardia: 250);

  test('a menor distancia, menos tiempo estimado', () {
    final tiempos = [2000.0, 1000.0, 500.0, 100.0].map(eta).toList();
    expect(tiempos, orderedEquals([...tiempos]..sort((a, b) => b.compareTo(a))));
    expect(tiempos.toSet(), hasLength(4), reason: 'cada distancia da un valor distinto');
  });

  test('250 m a 250 m/min es un minuto', () {
    expect(eta(250), 60);
  });

  test('el doble de distancia es el doble de tiempo', () {
    expect(eta(1000), eta(500) * 2);
  });

  test('si ya está en el punto, el tiempo es cero', () {
    expect(eta(0), 0);
    expect(eta(-10), 0, reason: 'una distancia imposible no produce tiempo negativo');
  });

  test('una velocidad inválida no revienta ni da negativos', () {
    expect(ReglaEta.segundos(distanciaMetros: 500, metrosPorMinutoGuardia: 0), 0);
  });

  test('a mayor velocidad, menos tiempo para la misma distancia', () {
    final lento = ReglaEta.segundos(distanciaMetros: 1000, metrosPorMinutoGuardia: 100);
    final rapido = ReglaEta.segundos(distanciaMetros: 1000, metrosPorMinutoGuardia: 400);
    expect(rapido, lessThan(lento));
  });
}
