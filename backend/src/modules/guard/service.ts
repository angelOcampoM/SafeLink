// G-01 · G-04 (BE-04): vista del guardia. Equivale a lo de lectura de
// lib/datos/memoria_alerta_guardia_repository.dart (perfil, historial, métricas y detalle).
// Un recurso que el guardia no puede ver responde NOT_FOUND con el mismo cuerpo que uno
// inexistente (D22, D40): nada que permita enumerar alertas ajenas.
import { ACTIVE_STATUSES } from '../../domain/alert-rules.js';
import { guardMetrics, type GuardMetrics } from '../../domain/metrics.js';
import type { VisibilityGuard } from '../../domain/guard-visibility.js';
import type { PrismaClient } from '../../db/prisma.js';
import { AppError, notFound } from '../../errors/app-error.js';
import type { Prisma } from '../../generated/prisma/client.js';
import { AlertStatus, Role } from '../../generated/prisma/enums.js';
import { assertGuardCanSee } from '../../security/ownership.js';
import { ALERT_NOT_FOUND } from '../alerts/service.js';
import {
  ALERT_INCLUDE,
  serializeGuardAlert,
  type AlertJson,
  type SerializeOptions,
} from '../alerts/serializers.js';
import { serializeGuard, type GuardJson } from '../admin/serializers.js';

export interface GuardServiceDeps {
  prisma: PrismaClient;
  serialize: SerializeOptions;
  /** Zona horaria IANA de los turnos (config TZ_SHIFTS). */
  timeZone: string;
  /** Reloj inyectable para las pruebas. */
  now?: () => Date;
  /** Avisa al dueño de una alerta cuyo guardia se movió (su ETA cambia); lo cablea app.ts. */
  onUserAlertChanged?: (userId: string) => void;
}

/**
 * Historial del guardia: lo que ya terminó y atendió él (memoria_alerta_guardia_repository.dart:107).
 * Las métricas salen de este mismo filtro para que las cifras coincidan (D41).
 */
const historyWhere = (guardId: string): Prisma.AlertWhereInput => ({
  guardId,
  status: { notIn: [...ACTIVE_STATUSES] },
});

export function createGuardService(deps: GuardServiceDeps) {
  const { prisma, serialize, timeZone } = deps;
  const now = deps.now ?? (() => new Date());

  /**
   * El guardia en sesión con su perfil; si ya no existe como guardia, NOT_FOUND. `message` deja
   * que el detalle de alerta responda con el mismo texto que una alerta inexistente (D40).
   */
  async function loadGuardWithProfile(guardId: string, message?: string) {
    const user = await prisma.user.findFirst({
      where: { id: guardId, role: Role.guard },
      include: { guardProfile: true },
    });
    if (!user?.guardProfile) throw notFound(message);
    return { user, profile: user.guardProfile };
  }

  return {
    /** G-01 (extra del front): el guardia en sesión como { user, profile }. */
    async me(guardId: string): Promise<GuardJson> {
      const { user, profile } = await loadGuardWithProfile(guardId);
      return serializeGuard(user, profile);
    },

    /** Sin paginación (D41). Más recientes primero por `receivedAt` (D24); el id desempata. */
    async history(guardId: string): Promise<AlertJson[]> {
      const alerts = await prisma.alert.findMany({
        where: historyWhere(guardId),
        include: ALERT_INCLUDE,
        orderBy: [{ receivedAt: 'desc' }, { id: 'asc' }],
      });
      return alerts.map((a) => serializeGuardAlert(a, guardId, serialize));
    },

    /** Sobre la misma lista que `history` (D41); duraciones truncadas a segundos por alerta. */
    async metrics(guardId: string): Promise<GuardMetrics> {
      const alerts = await prisma.alert.findMany({
        where: historyWhere(guardId),
        select: {
          guardId: true,
          receivedAt: true,
          acceptedAt: true,
          arrivedAt: true,
          escalationReason: true,
        },
      });
      return guardMetrics(guardId, alerts);
    },

    /**
     * G-06: guarda la última ubicación del guardia con la hora del servidor (no exige turno).
     * Sin perfil de guardia, NOT_FOUND. Si atiende una alerta en curso, avisa a su dueño.
     */
    async updateLocation(guardId: string, location: { lat: number; lng: number }): Promise<null> {
      const { count } = await prisma.guardProfile.updateMany({
        where: { userId: guardId, user: { role: Role.guard } },
        data: { lastLocationLat: location.lat, lastLocationLng: location.lng, lastLocationAt: now() },
      });
      if (count === 0) throw notFound();
      // Un aviso por dueño, no por alerta (D36 dejará como máximo una en curso).
      const owners = await prisma.alert.findMany({
        where: { guardId, status: AlertStatus.in_progress },
        select: { userId: true },
        distinct: ['userId'],
      });
      for (const { userId } of owners) deps.onUserAlertChanged?.(userId);
      return null;
    },

    /**
     * G-04: detalle de una alerta asignada al guardia o disponible para él (D22). Cualquier
     * otra (ajena, no visible, inexistente) es NOT_FOUND con el mismo mensaje (D40).
     */
    async getAlert(guardId: string, alertId: string): Promise<AlertJson> {
      const alert = await prisma.alert.findUnique({ where: { id: alertId }, include: ALERT_INCLUDE });
      if (!alert) throw notFound(ALERT_NOT_FOUND);
      const { user, profile } = await loadGuardWithProfile(guardId, ALERT_NOT_FOUND);
      const ignored = await prisma.alertIgnore.findUnique({
        where: { guardId_alertId: { guardId, alertId } },
        select: { guardId: true },
      });

      const guard: VisibilityGuard = {
        id: guardId,
        active: user.isActive,
        shiftStart: profile.shiftStart,
        shiftEnd: profile.shiftEnd,
        coverage:
          profile.coverageCenterLat !== null &&
          profile.coverageCenterLng !== null &&
          profile.coverageRadiusMeters !== null
            ? {
                center: { lat: profile.coverageCenterLat, lng: profile.coverageCenterLng },
                radiusMeters: profile.coverageRadiusMeters,
              }
            : null,
      };
      const location =
        alert.lat !== null && alert.lng !== null ? { lat: alert.lat, lng: alert.lng } : null;
      try {
        assertGuardCanSee(
          { guardId: alert.guardId, status: alert.status, location },
          guard,
          { now: now(), timeZone, ignoredByGuard: ignored !== null },
        );
      } catch (error) {
        // El 404 genérico de ownership.ts lleva otro texto: aquí debe ser idéntico al de "no existe".
        if (error instanceof AppError && error.code === 'NOT_FOUND') throw notFound(ALERT_NOT_FOUND);
        throw error;
      }
      return serializeGuardAlert(alert, guardId, serialize);
    },
  };
}

export type GuardService = ReturnType<typeof createGuardService>;
