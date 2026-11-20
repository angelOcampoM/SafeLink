// U-09 · A-04 (BE-05): escalamiento automático de alertas y bandeja de escaladas del admin.
//
// D14 (resuelta en BE-05): `no_response` NO se guarda como estado intermedio. Una alerta que
// nadie aceptó pasa directo de `searching` a `escalated` con `escalationReason = no_response`,
// como hace la simulación del front (memoria_base_datos.dart:189-203) y como cuentan las
// métricas (por la razón, regla_metricas.dart:28). Una que llegó pero el usuario no confirmó
// pasa de `guard_arrived` a `escalated` con `no_confirmation` y CONSERVA al guardia (evidencia
// de quién atendió; el índice de D36 lo libera porque `escalated` no está en atención).
import {
  ALERT_NOT_ESCALATED,
  adminNoteError,
  applyFalseAlarm,
  escalationReasonFor,
  type EscalationLimits,
} from '../../domain/alert-rules.js';
import type { PrismaClient } from '../../db/prisma.js';
import { invalidInput, invalidState, notFound } from '../../errors/app-error.js';
import { AlertStatus, Resolution, type EscalationReason } from '../../generated/prisma/enums.js';
import { ALERT_INCLUDE, serializeAdminAlert, type AlertJson, type SerializeOptions } from '../alerts/serializers.js';
import { ALERT_NOT_FOUND } from '../alerts/service.js';

/** A-08: reglas del bloqueo por falsas alarmas (FALSE_ALARM_LIMIT y BLOCK_DAYS). */
export interface FalseAlarmRules {
  limit: number;
  blockDays: number;
}

/** Lo que cambió al resolver, para los avisos en tiempo real. */
export interface ResolvedAlert {
  alertId: string;
  userId: string;
  guardId: string | null;
  resolution: Resolution;
}

/** Estados de los que se puede escalar (los demás nunca escalan, D14). */
const ESCALABLE: readonly AlertStatus[] = [
  AlertStatus.searching,
  AlertStatus.no_response,
  AlertStatus.guard_arrived,
];

/** Cuántas alertas vencidas se revisan por vuelta; las demás quedan para la siguiente. */
const LOTE = 100;

/** Lo que cambió con una alerta escalada, para los avisos en tiempo real. */
export interface EscalatedAlert {
  alertId: string;
  userId: string;
  guardId: string | null;
  from: AlertStatus;
  reason: EscalationReason;
}

export interface EscalationLogger {
  error(obj: unknown, msg: string): void;
}

export interface EscalationServiceDeps {
  prisma: PrismaClient;
  limits: EscalationLimits;
  serialize: SerializeOptions;
  falseAlarms: FalseAlarmRules;
  /** ADMIN_NOTE_MAX_LENGTH. */
  adminNoteMaxLength: number;
  /** Se llama después del commit de cada alerta escalada. */
  onEscalated?: (escalated: EscalatedAlert) => void;
  /** Se llama después del commit de una resolución. */
  onResolved?: (resolved: ResolvedAlert) => void;
  logger?: EscalationLogger;
  /** Reloj inyectable para las pruebas. */
  now?: () => Date;
}

export function createEscalationService(deps: EscalationServiceDeps) {
  const { prisma, limits, serialize } = deps;
  const now = deps.now ?? (() => new Date());
  let timer: NodeJS.Timeout | null = null;
  let corriendo = false;

  /**
   * Escala todas las alertas vencidas a la hora `now()` y devuelve las que escaló.
   * Cada alerta se escala con un `updateMany` condicionado al estado y a `statusChangedAt` que se
   * leyeron: si un guardia la aceptó o el usuario confirmó en el mismo instante, gana esa acción
   * y la alerta no se escala (count = 0). Así es seguro aunque corran varias instancias.
   */
  async function sweep(): Promise<EscalatedAlert[]> {
    const at = now();
    // El límite más corto acota la consulta; la regla de dominio decide caso por caso.
    const desde = (segundos: number) => new Date(at.getTime() - segundos * 1000);
    const candidatas = await prisma.alert.findMany({
      where: {
        OR: [
          { status: { in: [AlertStatus.searching, AlertStatus.no_response] }, statusChangedAt: { lte: desde(limits.acceptTimeoutSeconds) } },
          { status: AlertStatus.guard_arrived, statusChangedAt: { lte: desde(limits.confirmTimeoutSeconds) } },
        ],
      },
      select: { id: true, userId: true, guardId: true, status: true, statusChangedAt: true },
      orderBy: { statusChangedAt: 'asc' },
      take: LOTE,
    });

    const escaladas: EscalatedAlert[] = [];
    for (const alerta of candidatas) {
      const reason = escalationReasonFor(alerta, at, limits);
      if (!reason || !ESCALABLE.includes(alerta.status)) continue;

      let escalo: boolean;
      try {
        escalo = await prisma.$transaction(async (tx) => {
          const { count } = await tx.alert.updateMany({
            where: { id: alerta.id, status: alerta.status, statusChangedAt: alerta.statusChangedAt },
            // guardId no se toca: `null` desde searching (D35) y el que atendió desde guard_arrived.
            data: { status: AlertStatus.escalated, escalationReason: reason, statusChangedAt: at },
          });
          if (count === 0) return false;
          await tx.alertStatusHistory.create({
            // actorId null: el cambio lo hace el sistema (comentario del modelo).
            data: { alertId: alerta.id, fromStatus: alerta.status, toStatus: AlertStatus.escalated, actorId: null, at },
          });
          return true;
        });
      } catch (error) {
        // Una alerta que falla no detiene la revisión de las demás; se reintenta en la siguiente vuelta.
        deps.logger?.error({ err: error, alertId: alerta.id }, 'Escalamiento: no se pudo escalar una alerta');
        continue;
      }
      if (!escalo) continue;

      const cambio: EscalatedAlert = {
        alertId: alerta.id,
        userId: alerta.userId,
        guardId: alerta.guardId,
        from: alerta.status,
        reason,
      };
      escaladas.push(cambio);
      deps.onEscalated?.(cambio);
    }
    return escaladas;
  }

  return {
    sweep,

    /** A-04: la bandeja del admin. Todas las escaladas, la más antigua primero (D24: por `receivedAt`). */
    async listEscalated(): Promise<AlertJson[]> {
      const alerts = await prisma.alert.findMany({
        where: { status: AlertStatus.escalated },
        include: ALERT_INCLUDE,
        orderBy: [{ receivedAt: 'asc' }, { id: 'asc' }],
      });
      return alerts.map((a) => serializeAdminAlert(a, serialize));
    },

    /**
     * A-04 · A-08 (BE-05): el admin resuelve una escalada. Orden de validación del front
     * (memoria_admin_repository.dart:120): primero el estado (409), luego la nota (400).
     * Si es falsa alarma, en la MISMA transacción suma 1 al usuario y, al llegar al límite,
     * lo bloquea BLOCK_DAYS días (renovando el bloqueo en cada falsa alarma posterior).
     */
    async resolve(adminId: string, alertId: string, resolution: Resolution, adminNote: string): Promise<AlertJson> {
      const alerta = await prisma.alert.findUnique({ where: { id: alertId }, select: { status: true } });
      if (!alerta) throw notFound(ALERT_NOT_FOUND);
      if (alerta.status !== AlertStatus.escalated) throw invalidState(ALERT_NOT_ESCALATED);
      const errorNota = adminNoteError(adminNote, deps.adminNoteMaxLength);
      if (errorNota) throw invalidInput(errorNota);

      const at = now();
      const resuelta = await prisma.$transaction(async (tx) => {
        // Condicionada a `escalated`: dos admins a la vez no la resuelven dos veces (ni suman dos falsas alarmas).
        const { count } = await tx.alert.updateMany({
          where: { id: alertId, status: AlertStatus.escalated },
          data: {
            status: AlertStatus.resolved_by_admin,
            resolution,
            adminNote: adminNote.trim(),
            closedAt: at,
            statusChangedAt: at,
          },
        });
        if (count === 0) throw invalidState(ALERT_NOT_ESCALATED);
        await tx.alertStatusHistory.create({
          data: { alertId, fromStatus: AlertStatus.escalated, toStatus: AlertStatus.resolved_by_admin, actorId: adminId, at },
        });
        const final = await tx.alert.findUniqueOrThrow({ where: { id: alertId }, include: ALERT_INCLUDE });
        if (resolution === Resolution.false_alarm) {
          // FOR UPDATE: dos falsas alarmas del mismo usuario al mismo tiempo no pierden la cuenta.
          const filas = await tx.$queryRaw<{ false_alarm_count: number }[]>`
            SELECT false_alarm_count FROM users WHERE id = ${final.userId}::uuid FOR UPDATE`;
          const actual = filas[0]?.false_alarm_count ?? 0;
          const cambio = applyFalseAlarm(actual, at, deps.falseAlarms.limit, deps.falseAlarms.blockDays);
          await tx.user.update({
            where: { id: final.userId },
            data: {
              falseAlarmCount: cambio.falseAlarmCount,
              ...(cambio.blockedUntil ? { blockedUntil: cambio.blockedUntil } : {}),
            },
          });
        }
        return final;
      });
      deps.onResolved?.({ alertId, userId: resuelta.userId, guardId: resuelta.guardId, resolution });
      return serializeAdminAlert(resuelta, serialize);
    },

    /** Revisa cada `intervalSeconds`. Una vuelta no empieza si la anterior sigue corriendo. */
    start(intervalSeconds: number): void {
      if (timer || intervalSeconds <= 0) return;
      timer = setInterval(() => {
        if (corriendo) return;
        corriendo = true;
        sweep()
          .catch((error: unknown) => deps.logger?.error({ err: error }, 'Escalamiento: la revisión falló'))
          .finally(() => {
            corriendo = false;
          });
      }, intervalSeconds * 1000);
      timer.unref();
    },

    stop(): void {
      if (timer) clearInterval(timer);
      timer = null;
    },
  };
}

export type EscalationService = ReturnType<typeof createEscalationService>;
