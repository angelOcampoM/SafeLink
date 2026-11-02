// CAPA: DOMINIO — cuánto falta del turno
// G-03 Inicio del guardia: tiempo restante del turno y tiempo para que empiece.
// Usa ReglaTurno (turnos "HH:mm" que pueden cruzar medianoche, rango [inicio, fin)).
// No hace: no lee el reloj; quien pregunta le pasa la hora local.

import 'regla_turno.dart';

abstract final class ReglaTiempoTurno {
  static const _minutosDia = 24 * 60;

  /// Minutos que faltan para que termine el turno, o `null` si no está en turno.
  /// Un turno de 24 h (inicio == fin) termina al volver a la hora de inicio.
  static int? minutosRestantes(String inicio, String fin, DateTime horaLocal) {
    if (!ReglaTurno.dentroDeTurno(inicio, fin, horaLocal)) return null;
    return _hasta(ReglaTurno.aMinutos(fin), horaLocal);
  }

  /// Minutos que faltan para que empiece el turno, o `null` si ya está en turno.
  static int? minutosParaIniciar(String inicio, String fin, DateTime horaLocal) {
    if (ReglaTurno.dentroDeTurno(inicio, fin, horaLocal)) return null;
    return _hasta(ReglaTurno.aMinutos(inicio), horaLocal);
  }

  /// Minutos desde [horaLocal] hasta la siguiente vez que el reloj marque [objetivo] (1 – 1440).
  static int _hasta(int objetivo, DateTime horaLocal) {
    final d = objetivo - (horaLocal.hour * 60 + horaLocal.minute);
    return d <= 0 ? d + _minutosDia : d;
  }
}
