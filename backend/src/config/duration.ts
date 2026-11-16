// Duraciones de configuración con formato "<entero><s|m|h|d>" (ej. 15m, 30d).

export const DURATION_PATTERN = /^([1-9]\d{0,5})(s|m|h|d)$/;

const UNIT_SECONDS = { s: 1, m: 60, h: 3600, d: 86_400 } as const;

/** Convierte "15m" o "30d" a segundos; lanza si el formato no es válido. */
export function durationToSeconds(value: string): number {
  const match = DURATION_PATTERN.exec(value);
  if (!match) throw new Error('Duración inválida');
  const unit = match[2] as keyof typeof UNIT_SECONDS;
  return Number(match[1]) * UNIT_SECONDS[unit];
}
