// Métricas por guardia (G-01 · A-07). Equivale a ReglaMetricas.deGuardia
// (lib/dominio/regla_metricas.dart:42-50). Función pura: recibe las alertas ya cargadas y
// filtradas por el periodo; no consulta nada. La reutiliza BE-07 (GET /admin/metrics/guards/:id).
//
// Base de tiempo: `receivedAt` (hora del servidor, D24), no `triggeredAt` (hora del teléfono).
// Cada duración se trunca a segundos enteros por alerta antes de promediar, igual que
// `Duration.inSeconds` en el front; con cero valores el promedio es 0 (nunca divide entre 0).
import type { EscalationReason } from '../generated/prisma/enums.js';

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
