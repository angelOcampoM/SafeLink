// Reglas de turno puras. Equivalen a lib/dominio/regla_turno.dart.
// Turnos "HH:mm" que pueden cruzar medianoche (ej. 22:00 -> 06:00).

const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** "HH:mm" a minutos desde la medianoche. Lanza si el formato no es válido. */
export function hhmmToMinutes(hhmm: string): number {
  const match = HHMM.exec(hhmm);
  if (!match) throw new RangeError('Hora con formato inválido, se esperaba HH:mm');
  return Number(match[1]) * 60 + Number(match[2]);
}

/** Incluye el inicio y excluye el fin: [inicio, fin). Inicio == fin es turno de 24 h. */
export function isWithinShift(start: string, end: string, minutesOfDay: number): boolean {
  const s = hhmmToMinutes(start);
  const e = hhmmToMinutes(end);
  if (s === e) return true;
  if (s < e) return minutesOfDay >= s && minutesOfDay < e;
  return minutesOfDay >= s || minutesOfDay < e;
}

/** Minutos desde la medianoche del instante `date` en la zona horaria IANA indicada. */
export function localMinutesOfDay(date: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const hour = Number(parts.find((p) => p.type === 'hour')?.value);
  const minute = Number(parts.find((p) => p.type === 'minute')?.value);
  return (hour % 24) * 60 + minute;
}

/** ¿El turno está vigente en el instante `now`, según la hora local de `timeZone`? */
export function isShiftActive(start: string, end: string, now: Date, timeZone: string): boolean {
  return isWithinShift(start, end, localMinutesOfDay(now, timeZone));
}
