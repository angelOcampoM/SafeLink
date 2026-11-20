// Orden del listado del guardia (G-03). Equivale a lib/dominio/regla_prioridad.dart.
// Función pura: no filtra por cobertura, turno ni estado; ordena lo que recibe.
//   1. Primero las urgentes (disparo `shake`, "doble clic de volumen" en el front).
//   2. Después, menor `score = distancia − minutosEspera × WAIT_METERS_PER_MINUTE`.
// Diferencias con el front (D24): la espera sale de `receivedAt` (hora del servidor), no de
// `triggeredAt`; y el desempate es determinista (receivedAt, luego id), porque el front deja
// los empates en el orden de entrada. Como en el front, las cifras no se redondean.
import { haversineMeters, type GeoPoint } from './geo.js';

/** Una alerta candidata: `alert` es lo que se devuelve tal cual; el resto alimenta el orden. */
export interface PriorityCandidate<T> {
  alert: T;
  id: string;
  triggerMethod: string;
  /** Hora del servidor al recibir la alerta (D24). */
  receivedAt: Date;
  location: GeoPoint;
}

/** Forma de PrioritizedAlert del contrato (nube_mapeadores.dart:167-181). */
export interface PrioritizedAlert<T> {
  alert: T;
  distanceMeters: number;
  waitingMinutes: number;
  score: number;
}

/** Valor de `triggerMethod` que se trata como urgente. */
export const URGENT_TRIGGER_METHOD = 'shake';

export const isUrgent = (triggerMethod: string): boolean => triggerMethod === URGENT_TRIGGER_METHOD;

/** Minutos de espera; los segundos se truncan como en el front (`inSeconds / 60`). */
export function waitingMinutes(receivedAt: Date, now: Date): number {
  return Math.trunc((now.getTime() - receivedAt.getTime()) / 1000) / 60;
}

export function prioritizeAlerts<T>(
  candidates: readonly PriorityCandidate<T>[],
  origin: GeoPoint,
  now: Date,
  waitMetersPerMinute: number,
): PrioritizedAlert<T>[] {
  const withKeys = candidates.map((c) => {
    const distanceMeters = haversineMeters(origin, c.location);
    const waiting = waitingMinutes(c.receivedAt, now);
    return {
      c,
      urgent: isUrgent(c.triggerMethod),
      result: {
        alert: c.alert,
        distanceMeters,
        waitingMinutes: waiting,
        score: distanceMeters - waiting * waitMetersPerMinute,
      },
    };
  });

  withKeys.sort((x, y) => {
    if (x.urgent !== y.urgent) return x.urgent ? -1 : 1;
    if (x.result.score !== y.result.score) return x.result.score - y.result.score;
    const byTime = x.c.receivedAt.getTime() - y.c.receivedAt.getTime();
    if (byTime !== 0) return byTime;
    return x.c.id < y.c.id ? -1 : x.c.id > y.c.id ? 1 : 0;
  });
  return withKeys.map((k) => k.result);
}
