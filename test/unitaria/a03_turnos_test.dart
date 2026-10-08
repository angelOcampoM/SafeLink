// A-03 Turnos — incluye turnos que cruzan medianoche.
import 'package:flutter_test/flutter_test.dart';
import 'package:safelink/core/utils/shift_utils.dart';

void main() {
  DateTime at(int h, int m) => DateTime(2026, 10, 7, h, m);

  test('turno diurno 08:00–16:00', () {
    expect(ShiftUtils.isWithinShift('08:00', '16:00', at(8, 0)), isTrue);
    expect(ShiftUtils.isWithinShift('08:00', '16:00', at(15, 59)), isTrue);
    expect(ShiftUtils.isWithinShift('08:00', '16:00', at(16, 0)), isFalse);
  });

  test('turno nocturno 22:00–06:00 cruza medianoche', () {
    expect(ShiftUtils.isWithinShift('22:00', '06:00', at(23, 30)), isTrue);
    expect(ShiftUtils.isWithinShift('22:00', '06:00', at(2, 0)), isTrue);
    expect(ShiftUtils.isWithinShift('22:00', '06:00', at(12, 0)), isFalse);
  });
}
