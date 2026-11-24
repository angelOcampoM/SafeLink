// Conversiones entre instantes y hora de pared en una zona IANA (config TZ_SHIFTS).
// Sin dependencias: `Intl.DateTimeFormat` ya trae la base de datos de zonas de ICU, así que
// los cambios de horario (DST) salen correctos sin instalar nada.
//
// Lo usan BE-07 (`alertsByHour` del admin, contrato 4.6) y el filtro de historial, porque el
// front manda las fechas con `DateTime.toIso8601String()` sobre una fecha LOCAL: el texto
// llega sin zona ("2026-11-19T00:00:00.000") y hay que leerlo en la zona de los turnos, no
// en la del servidor (que en CI es UTC).

const MINUTO_MS = 60_000;

/** Partes de la fecha en `timeZone`, con hora en formato 0-23. */
function partes(timeZone: string, at: Date): Record<string, number> {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const salida: Record<string, number> = {};
  for (const { type, value } of fmt.formatToParts(at)) {
    if (type !== 'literal') salida[type] = Number(value);
  }
  return salida;
}

/** Hora de pared (0-23) del instante `at` visto en `timeZone`. */
export function hourInZone(at: Date, timeZone: string): number {
  return partes(timeZone, at).hour ?? 0;
}

/**
 * Minutos que `timeZone` lleva de adelanto sobre UTC en el instante `at`
 * (Ciudad de México en invierno: -360).
 */
export function zoneOffsetMinutes(timeZone: string, at: Date): number {
  const p = partes(timeZone, at);
  const comoUtc = Date.UTC(
    p.year ?? 1970,
    (p.month ?? 1) - 1,
    p.day ?? 1,
    p.hour ?? 0,
    p.minute ?? 0,
    p.second ?? 0,
  );
  // Los milisegundos no los da el formateador: se toman del instante original.
  const msOriginal = at.getTime() - Math.floor(at.getTime() / 1000) * 1000;
  return Math.round((comoUtc + msOriginal - at.getTime()) / MINUTO_MS);
}

/**
 * Lee una hora de pared de `timeZone` y devuelve el instante UTC equivalente.
 * `wallClockIso` es un ISO 8601 SIN zona ("2026-11-19T00:00:00.000").
 *
 * Dos pasadas: la primera supone que el texto era UTC para saber en qué época del año cae y
 * con qué desplazamiento; la segunda lo recalcula ya sobre el instante corregido, que es lo
 * que hace falta en los dos domingos del año en que cambia el horario.
 */
export function wallClockToUtc(wallClockIso: string, timeZone: string): Date {
  const comoUtc = new Date(`${wallClockIso}Z`);
  if (Number.isNaN(comoUtc.getTime())) return comoUtc;
  const primera = new Date(comoUtc.getTime() - zoneOffsetMinutes(timeZone, comoUtc) * MINUTO_MS);
  return new Date(comoUtc.getTime() - zoneOffsetMinutes(timeZone, primera) * MINUTO_MS);
}
