/// Turnos "HH:mm" que pueden cruzar medianoche (ej. 22:00 → 06:00).
abstract final class ShiftUtils {
  static int toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Incluye el inicio y excluye el fin: [start, end).
  static bool isWithinShift(String start, String end, DateTime localNow) {
    final s = toMinutes(start);
    final e = toMinutes(end);
    final n = localNow.hour * 60 + localNow.minute;
    if (s == e) return true; // turno de 24 h
    if (s < e) return n >= s && n < e;
    return n >= s || n < e; // cruza medianoche
  }
}
