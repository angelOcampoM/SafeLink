// Propiedad y visibilidad de recursos. Funciones puras sobre datos ya cargados (sin consultas).
// Si no se cumple, lanzan NOT_FOUND (nunca FORBIDDEN): un recurso ajeno no debe revelar que existe (D9, D22).
import {
  isAlertVisibleToGuard,
  isAssignedTo,
  type VisibilityAlert,
  type VisibilityContext,
  type VisibilityGuard,
} from '../domain/guard-visibility.js';
import { notFound } from '../errors/app-error.js';
import type { Role } from '../generated/prisma/enums.js';

export const GUARD_NOT_FOUND_MESSAGE = 'No encontramos a ese guardia';

/** El dueño de la alerta es el usuario autenticado. */
export function assertOwnsAlert<T extends { userId: string }>(
  alert: T | null | undefined,
  user: { id: string },
): asserts alert is T {
  if (!alert || alert.userId !== user.id) throw notFound();
}

/** El guardia autenticado es el asignado a la alerta (p. ej. `arrive`). */
export function assertAssignedGuard<T extends { guardId: string | null }>(
  alert: T | null | undefined,
  user: { id: string },
): asserts alert is T {
  if (!alert || !isAssignedTo(alert, user.id)) throw notFound();
}

/** La alerta está asignada al guardia o disponible para él (D22); si no, NOT_FOUND. */
export function assertGuardCanSee<T extends VisibilityAlert>(
  alert: T | null | undefined,
  guard: VisibilityGuard,
  ctx: VisibilityContext,
): asserts alert is T {
  if (!alert || !isAlertVisibleToGuard(alert, guard, ctx)) throw notFound();
}

/** El objetivo de /admin/guards/:id debe existir y tener rol guard. */
export function assertIsGuardTarget<T extends { role: Role }>(
  target: T | null | undefined,
): asserts target is T {
  if (!target || target.role !== 'guard') throw notFound(GUARD_NOT_FOUND_MESSAGE);
}
