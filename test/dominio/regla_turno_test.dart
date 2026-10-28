// A-03 Turnos — incluye turnos que cruzan medianoche.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/dominio/regla_turno.dart';

void main() {
  DateTime a(int h, int m) => DateTime(2026, 10, 7, h, m);

  test('turno diurno 08:00–16:00', () {
    expect(ReglaTurno.dentroDeTurno('08:00', '16:00', a(8, 0)), isTrue);
    expect(ReglaTurno.dentroDeTurno('08:00', '16:00', a(15, 59)), isTrue);
    expect(ReglaTurno.dentroDeTurno('08:00', '16:00', a(16, 0)), isFalse);
  });

  test('turno nocturno 22:00–06:00 cruza medianoche', () {
    expect(ReglaTurno.dentroDeTurno('22:00', '06:00', a(23, 30)), isTrue);
    expect(ReglaTurno.dentroDeTurno('22:00', '06:00', a(2, 0)), isTrue);
    expect(ReglaTurno.dentroDeTurno('22:00', '06:00', a(12, 0)), isFalse);
  });

  test('duración y formato', () {
    expect(ReglaTurno.duracionMinutos('22:00', '06:00'), 8 * 60);
    expect(ReglaTurno.duracionMinutos('08:00', '08:00'), 24 * 60);
    expect(ReglaTurno.deHoraMinuto(7, 5), '07:05');
  });

  test('validar devuelve el motivo o null', () {
    expect(ReglaTurno.validar('08:00', '16:00'), isNull);
    expect(ReglaTurno.validar('8:00', '16:00'), isNotNull);
    expect(ReglaTurno.validar('08:00', '24:00'), isNotNull);
  });
}
