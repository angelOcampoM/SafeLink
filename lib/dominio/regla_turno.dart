// CAPA: DOMINIO — regla de turnos
// A-03 Turnos y radios
// "¿Este guardia está en turno?" vive aquí y en ningún otro lugar. Turnos "HH:mm"
// que pueden cruzar medianoche (ej. 22:00 → 06:00).
// No hace: no lee el reloj; quien pregunta le pasa la hora local.

abstract final class ReglaTurno {
  static final _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

  static int aMinutos(String hhmm) {
    final partes = hhmm.split(':');
    return int.parse(partes[0]) * 60 + int.parse(partes[1]);
  }

  /// 7, 5 → "07:05"
  static String deHoraMinuto(int hora, int minuto) =>
      '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  /// Incluye el inicio y excluye el fin: [inicio, fin).
  static bool dentroDeTurno(String inicio, String fin, DateTime horaLocal) {
    final s = aMinutos(inicio);
    final e = aMinutos(fin);
    final n = horaLocal.hour * 60 + horaLocal.minute;
    if (s == e) return true; // turno de 24 h
    if (s < e) return n >= s && n < e;
    return n >= s || n < e; // cruza medianoche
  }

  /// Devuelve el motivo del rechazo, o `null` si el turno es válido.
  static String? validar(String inicio, String fin) {
    if (!_hhmm.hasMatch(inicio) || !_hhmm.hasMatch(fin)) return 'Usa el formato HH:mm';
    return null;
  }

  /// Duración del turno en minutos (24 h si inicio == fin).
  static int duracionMinutos(String inicio, String fin) {
    final d = aMinutos(fin) - aMinutos(inicio);
    return d <= 0 ? d + 24 * 60 : d;
  }
}
