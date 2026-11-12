// Visibilidad de una alerta para un guardia (D22). Función pura sobre datos ya cargados.
//
// Una alerta es visible para el guardia si:
//   - está asignada a él, o
//   - está disponible para él: en `searching` (salvo que se omita la condición de estado,
//     como en `accept`), con ubicación dentro de su cobertura (centro + radio), con turno
//     vigente y no ignorada por él. `zone` es solo una etiqueta y no filtra.
import { AlertStatus } from '../generated/prisma/enums.js';
import { isWithinRadius, type GeoPoint } from './geo.js';
import { isShiftActive } from './shift.js';

export interface VisibilityAlert {
  guardId: string | null;
  status: AlertStatus;
  location: GeoPoint | null;
}

export interface VisibilityGuard {
  id: string;
  /** Falso si el guardia fue dado de baja o está bloqueado: no ve alertas disponibles. */
  active: boolean;
  shiftStart: string;
  shiftEnd: string;
  /** Null si el administrador aún no le asigna cobertura. */
  coverage: { center: GeoPoint; radiusMeters: number } | null;
}

export interface VisibilityContext {
  now: Date;
  /** Zona horaria IANA de los turnos (config TZ_SHIFTS). */
  timeZone: string;
  /** El guardia ya ignoró esta alerta (alert_ignores). */
  ignoredByGuard: boolean;
  /**
   * Omite las condiciones `status === searching` y `guardId === null`. SOLO sirve para decidir
   * entre 404 y 409 en `accept` (no visible = 404; visible pero ya no disponible = 409
   * ALERT_TAKEN). Nunca debe usarse para devolver datos de la alerta.
   */
  skipStatusCheck?: boolean;
}

export function isAssignedTo(alert: Pick<VisibilityAlert, 'guardId'>, guardId: string): boolean {
  return alert.guardId !== null && alert.guardId === guardId;
}

/** ¿La alerta está disponible (sin asignar) para este guardia? */
export function isAlertAvailableToGuard(
  alert: VisibilityAlert,
  guard: VisibilityGuard,
  ctx: VisibilityContext,
): boolean {
  if (!guard.active) return false;
  if (!ctx.skipStatusCheck && (alert.status !== AlertStatus.searching || alert.guardId !== null)) {
    return false;
  }
  if (ctx.ignoredByGuard) return false;
  if (!alert.location || !guard.coverage) return false;
  if (!isWithinRadius(guard.coverage.center, guard.coverage.radiusMeters, alert.location)) {
    return false;
  }
  return isShiftActive(guard.shiftStart, guard.shiftEnd, ctx.now, ctx.timeZone);
}

/** Asignada al guardia, o disponible para él. */
export function isAlertVisibleToGuard(
  alert: VisibilityAlert,
  guard: VisibilityGuard,
  ctx: VisibilityContext,
): boolean {
  return isAssignedTo(alert, guard.id) || isAlertAvailableToGuard(alert, guard, ctx);
}
