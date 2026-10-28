// G-03 Listado por cercanía y prioridad (sección 6.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  final ahora = DateTime(2026, 10, 7, 18, 0);
  const guardia = PuntoGeo(18.8400, -99.1800);

  Alerta alerta(String id, double dLat, int minutosAtras, {MetodoDisparo m = MetodoDisparo.toque}) => Alerta(
        id: id,
        usuarioId: 'u',
        estado: EstadoAlerta.buscando,
        metodo: m,
        disparadaEn: ahora.subtract(Duration(minutes: minutosAtras)),
        ubicacion: PuntoGeo(guardia.lat + dLat, guardia.lng),
      );

  test('las de agitación van primero aunque estén más lejos', () {
    final r = ReglaPrioridad.ordenar(
      alertas: [alerta('cerca', 0.001, 0), alerta('lejos-shake', 0.02, 0, m: MetodoDisparo.agitacion)],
      ubicacionGuardia: guardia,
      ahora: ahora,
    );
    expect(r.map((p) => p.alerta.id), ['lejos-shake', 'cerca']);
  });

  test('cada minuto de espera equivale a 100 m más cerca', () {
    // A: ~555 m, 0 min → puntaje 555. B: ~888 m, 5 min → puntaje 388.
    final r = ReglaPrioridad.ordenar(
      alertas: [alerta('A', 0.005, 0), alerta('B', 0.008, 5)],
      ubicacionGuardia: guardia,
      ahora: ahora,
    );
    expect(r.first.alerta.id, 'B');
  });

  test('ignora alertas sin ubicación', () {
    final sinUbicacion = Alerta(
      id: 'x',
      usuarioId: 'u',
      estado: EstadoAlerta.pendienteUbicacion,
      metodo: MetodoDisparo.toque,
      disparadaEn: ahora,
    );
    expect(ReglaPrioridad.ordenar(alertas: [sinUbicacion], ubicacionGuardia: guardia, ahora: ahora), isEmpty);
  });
}
