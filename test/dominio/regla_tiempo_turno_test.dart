// G-03 Inicio del guardia: tiempo restante del turno y tiempo para que empiece.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/dominio.dart';

void main() {
  DateTime a(int h, int m) => DateTime(2026, 10, 26, h, m);

  test('turno de día: minutos restantes y fuera de turno', () {
    expect(ReglaTiempoTurno.minutosRestantes('08:00', '16:00', a(13, 0)), 180);
    expect(ReglaTiempoTurno.minutosRestantes('08:00', '16:00', a(8, 0)), 480, reason: 'incluye el inicio');
    expect(ReglaTiempoTurno.minutosRestantes('08:00', '16:00', a(15, 59)), 1);
    expect(ReglaTiempoTurno.minutosRestantes('08:00', '16:00', a(16, 0)), isNull, reason: 'excluye el fin');
  });

  test('turno que cruza medianoche', () {
    expect(ReglaTiempoTurno.minutosRestantes('22:00', '06:00', a(23, 30)), 390);
    expect(ReglaTiempoTurno.minutosRestantes('22:00', '06:00', a(2, 0)), 240);
    expect(ReglaTiempoTurno.minutosRestantes('22:00', '06:00', a(12, 0)), isNull);
  });

  test('minutos para iniciar', () {
    expect(ReglaTiempoTurno.minutosParaIniciar('22:00', '06:00', a(20, 0)), 120);
    expect(ReglaTiempoTurno.minutosParaIniciar('08:00', '16:00', a(17, 0)), 900, reason: 'empieza mañana');
    expect(ReglaTiempoTurno.minutosParaIniciar('08:00', '16:00', a(10, 0)), isNull, reason: 'ya está en turno');
  });

  test('turno de 24 h: siempre en turno y termina al volver al inicio', () {
    expect(ReglaTiempoTurno.minutosRestantes('07:00', '07:00', a(7, 0)), 1440);
    expect(ReglaTiempoTurno.minutosRestantes('07:00', '07:00', a(19, 0)), 720);
    expect(ReglaTiempoTurno.minutosParaIniciar('07:00', '07:00', a(19, 0)), isNull);
  });
}
