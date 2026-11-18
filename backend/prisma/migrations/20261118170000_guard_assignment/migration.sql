-- BE-04 paso 5 (D35, D36): asignación de guardia.
-- Prisma no expresa CHECK ni índices parciales: se agregan a mano, igual que en la migración init.

-- D35: sin guardia mientras la alerta no se ha aceptado (o ya no está asignada). Cierra en la
-- base el pendiente "guard_id en estados sin guardia"; la visibilidad por guard_id depende de esto.
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_guard_absent_chk"
  CHECK ("status" NOT IN ('pending_location', 'searching', 'no_response') OR "guard_id" IS NULL);

-- D36: un guardia atiende una sola alerta a la vez (in_progress o guard_arrived).
CREATE UNIQUE INDEX "alerts_one_active_per_guard_idx" ON "alerts"("guard_id")
  WHERE "status" IN ('in_progress', 'guard_arrived');
