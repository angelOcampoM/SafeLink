// Métricas por guardia (G-01 · A-07). Equivale a ReglaMetricas.deGuardia
// (lib/dominio/regla_metricas.dart:42-50). Función pura: recibe las alertas ya cargadas y
// filtradas por el periodo; no consulta nada. La reutiliza BE-07 (GET /admin/metrics/guards/:id).
//
// Base de tiempo: `receivedAt` (hora del servidor, D24), no `triggeredAt` (hora del teléfono).
// Cada duración se trunca a segundos enteros por alerta antes de promediar, igual que
// `Duration.inSeconds` en el front; con cero valores el promedio es 0 (nunca divide entre 0).
import type { AlertStatus, EscalationReason } from '../generated/prisma/enums.js';
import { hourInZone } from './timezone.js';

/** Zona con la que se agrupan las alertas sin guardia o con guardia sin zona (regla_metricas.dart:13). */
export const ZONA_SIN_ASIGNAR = 'Sin zona asignada';

const HORAS_DEL_DIA = 24;

/** Lo que el cálculo necesita de cada alerta. */
export interface MetricsAlert {
  guardId: string | null;
  receivedAt: Date;
  acceptedAt: Date | null;
  arrivedAt: Date | null;
  escalationReason: EscalationReason | null;
}

/** Forma `MetricasGuardiaJson` del front (nube_mapeadores.dart:207-221). */
export interface GuardMetrics {
  attendedCount: number;
  avgAcceptanceSeconds: number;
  avgArrivalSeconds: number;
  escalatedCount: number;
}

/** Segundos enteros entre dos instantes, truncados hacia cero (`Duration.inSeconds`). */
function wholeSeconds(from: Date, to: Date): number {
  return Math.trunc((to.getTime() - from.getTime()) / 1000);
}

function average(values: readonly number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

/** Lo que el cálculo general necesita de cada alerta, además de `MetricsAlert`. */
export interface GeneralMetricsAlert extends MetricsAlert {
  status: AlertStatus;
  /** Zona del guardia asignado; `null` si no hay guardia o no tiene zona. */
  zone: string | null;
}

/** Una zona con su conteo (contrato 4.6). */
export interface ZoneCount {
  zone: string;
  count: number;
}

/** Forma `MetricasGeneralesJson` del front (nube_mapeadores.dart:183-205). */
export interface GeneralMetrics {
  totalAlerts: number;
  avgAcceptanceSeconds: number;
  avgArrivalSeconds: number;
  noResponseRate: number;
  confirmedCloseRate: number;
  alertsByHour: number[];
  alertsByZone: ZoneCount[];
}

/** Proporción de `cuantas` sobre `total`; con total 0 es 0 (nunca divide entre 0). */
function rate(cuantas: number, total: number): number {
  return total === 0 ? 0 : cuantas / total;
}

/**
 * A-06 · Métricas generales del periodo. Equivale a `ReglaMetricas.generales`
 * (lib/dominio/regla_metricas.dart:16-40). Función pura: recibe las alertas ya cargadas y
 * filtradas por el periodo; no consulta nada.
 *
 * `alertsByHour` usa la hora de pared de `receivedAt` en `timeZone` (D12, D24): el front usa
 * la hora local del dispositivo, que aquí no existe, así que la referencia es TZ_SHIFTS.
 */
export function generalMetrics(
  alerts: readonly GeneralMetricsAlert[],
  timeZone: string,
): GeneralMetrics {
  const total = alerts.length;
  const acceptance = alerts.flatMap((a) =>
    a.acceptedAt ? [wholeSeconds(a.receivedAt, a.acceptedAt)] : [],
  );
  const arrival = alerts.flatMap((a) =>
    a.arrivedAt ? [wholeSeconds(a.acceptedAt ?? a.receivedAt, a.arrivedAt)] : [],
  );

  const alertsByHour = Array.from({ length: HORAS_DEL_DIA }, () => 0);
  for (const a of alerts) {
    const hora = hourInZone(a.receivedAt, timeZone);
    alertsByHour[hora] = (alertsByHour[hora] ?? 0) + 1;
  }

  // Más alertas primero y, a igualdad, por nombre de zona: así el orden no depende de la base.
  const porZona = new Map<string, number>();
  for (const a of alerts) {
    const zona = a.zone ?? ZONA_SIN_ASIGNAR;
    porZona.set(zona, (porZona.get(zona) ?? 0) + 1);
  }
  const alertsByZone = [...porZona.entries()]
    .map(([zone, count]) => ({ zone, count }))
    .sort((x, y) => (y.count - x.count) || x.zone.localeCompare(y.zone, 'es'));

  return {
    totalAlerts: total,
    avgAcceptanceSeconds: average(acceptance),
    avgArrivalSeconds: average(arrival),
    noResponseRate: rate(alerts.filter((a) => a.escalationReason === 'no_response').length, total),
    confirmedCloseRate: rate(alerts.filter((a) => a.status === 'closed').length, total),
    alertsByHour,
    alertsByZone,
  };
}

export function guardMetrics(guardId: string, alerts: readonly MetricsAlert[]): GuardMetrics {
  const mine = alerts.filter((a) => a.guardId === guardId);
  const acceptance = mine.flatMap((a) =>
    a.acceptedAt ? [wholeSeconds(a.receivedAt, a.acceptedAt)] : [],
  );
  const arrival = mine.flatMap((a) =>
    a.arrivedAt ? [wholeSeconds(a.acceptedAt ?? a.receivedAt, a.arrivedAt)] : [],
  );
  return {
    attendedCount: mine.filter((a) => a.arrivedAt !== null).length,
    avgAcceptanceSeconds: average(acceptance),
    avgArrivalSeconds: average(arrival),
    escalatedCount: mine.filter((a) => a.escalationReason !== null).length,
  };
}
