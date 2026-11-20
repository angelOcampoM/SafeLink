// G-01 · G-04 (BE-04): vista del guardia. Equivale a lo de lectura de
// lib/datos/memoria_alerta_guardia_repository.dart (perfil, historial, métricas y detalle).
// Un recurso que el guardia no puede ver responde NOT_FOUND con el mismo cuerpo que uno
// inexistente (D22, D40): nada que permita enumerar alertas ajenas.
import {
  ACTIVE_STATUSES,
  ATTENDED_STATUSES,
  ALERT_NOT_IN_ATTENDANCE,
  GUARD_ALREADY_ATTENDING,
} from '../../domain/alert-rules.js';
import { isWithinRadius, metersRemaining } from '../../domain/geo.js';
import { guardMetrics, type GuardMetrics } from '../../domain/metrics.js';
import {
  isAlertAvailableToGuard,
  isAssignedTo,
  isAlertVisibleToGuard,
  toVisibilityGuard,
} from '../../domain/guard-visibility.js';
import { prioritizeAlerts, type PrioritizedAlert } from '../../domain/priority.js';
import { esGuardiaOcupado } from '../../db/errores-prisma.js';
import type { PrismaClient } from '../../db/prisma.js';
import { AppError, alertTaken, invalidState, notFound, outsideGeofence } from '../../errors/app-error.js';
import type { Prisma } from '../../generated/prisma/client.js';
import { AlertStatus, Role } from '../../generated/prisma/enums.js';
import { assertAssignedGuard, assertGuardCanSee } from '../../security/ownership.js';
import { ALERT_NOT_FOUND, type AlertChange } from '../alerts/service.js';
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
  /** GEOFENCE_METERS: radio en que se puede registrar la llegada (G-07). */
  geofenceMeters: number;
  /** WAIT_METERS_PER_MINUTE: peso de la espera en el orden del listado. */
  waitMetersPerMinute: number;
  /** Reloj inyectable para las pruebas. */
  now?: () => Date;
  /** Avisa al dueño de una alerta cuyo guardia se movió (su ETA cambia); lo cablea app.ts. */
  onUserAlertChanged?: (userId: string) => void;
  /** Avisa que cambió algo propio del guardia (su ubicación, una alerta ignorada): se recalcula su listado (D34). */
  onGuardChanged?: (guardId: string) => void;
  /** Avisa que cambió una alerta (la misma publicación que usa el servicio de alertas, D34). */
  onAlertChanged?: (change: AlertChange) => void;
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
  const { prisma, serialize, timeZone, geofenceMeters, waitMetersPerMinute } = deps;
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

  /**
   * Lo que hace falta para decidir si el guardia ve una alerta (getAlert, accept, ignore): la
   * alerta, el guardia con su perfil, si la ignoró y su ubicación. Alerta inexistente, guardia sin
   * perfil o de baja son NOT_FOUND con el mismo mensaje (D40). Un guardia de baja no ve nada, ni
   * lo asignado: el canal guard/alerts/:id solo revisa la sesión en cada ping y, mientras tanto,
   * un aviso del bus le mandaría teléfono y ubicación.
   */
  async function loadVisibilityContext(guardId: string, alertId: string) {
    const alert = await prisma.alert.findUnique({ where: { id: alertId }, include: ALERT_INCLUDE });
    if (!alert) throw notFound(ALERT_NOT_FOUND);
    const { user, profile } = await loadGuardWithProfile(guardId, ALERT_NOT_FOUND);
    if (!user.isActive) throw notFound(ALERT_NOT_FOUND);
    const ignored =
      (await prisma.alertIgnore.findUnique({
        where: { guardId_alertId: { guardId, alertId } },
        select: { guardId: true },
      })) !== null;
    const location =
      alert.lat !== null && alert.lng !== null ? { lat: alert.lat, lng: alert.lng } : null;
    return { alert, guard: toVisibilityGuard(user, profile), profile, ignored, location };
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
      // Su distancia a cada alerta cambió: se reordena su propio listado (D34).
      deps.onGuardChanged?.(guardId);
      return null;
    },

    /**
     * G-03: alertas disponibles para el guardia, ya priorizadas (snapshot del canal guard/alerts).
     * Se calcula por guardia y desde la base en cada llamada (D22). Sin disponibilidad (baja,
     * sin cobertura, fuera de turno o sin perfil) la lista es vacía: un error cerraría el stream
     * y el cliente reconectaría en bucle. La visibilidad sale de isAlertAvailableToGuard, la
     * misma que usarán accept y el push (D44); sin PostGIS (D17).
     */
    async listAvailable(guardId: string): Promise<PrioritizedAlert<AlertJson>[]> {
      const user = await prisma.user.findFirst({
        where: { id: guardId, role: Role.guard },
        include: { guardProfile: true },
      });
      if (!user?.guardProfile) return [];
      const profile = user.guardProfile;
      const guard = toVisibilityGuard(user, profile);
      if (!guard.active || !guard.coverage) return [];
      const at = now();

      const rows = await prisma.alert.findMany({
        where: {
          status: AlertStatus.searching,
          guardId: null,
          lat: { not: null },
          lng: { not: null },
          ignores: { none: { guardId } },
        },
        include: ALERT_INCLUDE,
      });

      const candidates = rows.flatMap((row) => {
        if (row.lat === null || row.lng === null) return [];
        const location = { lat: row.lat, lng: row.lng };
        // Las ignoradas ya salen en el `where` (ignores: none); si se cambia la consulta,
        // hay que pasar aquí el valor real.
        const visible = isAlertAvailableToGuard(
          { guardId: row.guardId, status: row.status, location },
          guard,
          { now: at, timeZone, ignoredByGuard: false },
        );
        if (!visible) return [];
        return [
          {
            alert: serializeGuardAlert(row, guardId, serialize),
            id: row.id,
            triggerMethod: row.triggerMethod,
            receivedAt: row.receivedAt,
            location,
          },
        ];
      });

      // D37: sin última ubicación, la distancia parte del centro de cobertura.
      const origin =
        profile.lastLocationLat !== null && profile.lastLocationLng !== null
          ? { lat: profile.lastLocationLat, lng: profile.lastLocationLng }
          : guard.coverage.center;
      return prioritizeAlerts(candidates, origin, at, waitMetersPerMinute);
    },

    /**
     * G-04: detalle de una alerta asignada al guardia o disponible para él (D22). Cualquier
     * otra (ajena, no visible, inexistente) es NOT_FOUND con el mismo mensaje (D40).
     */
    async getAlert(guardId: string, alertId: string): Promise<AlertJson> {
      const { alert, guard, ignored, location } = await loadVisibilityContext(guardId, alertId);
      try {
        assertGuardCanSee(
          { guardId: alert.guardId, status: alert.status, location },
          guard,
          { now: now(), timeZone, ignoredByGuard: ignored },
        );
      } catch (error) {
        // El 404 genérico de ownership.ts lleva otro texto: aquí debe ser idéntico al de "no existe".
        if (error instanceof AppError && error.code === 'NOT_FOUND') throw notFound(ALERT_NOT_FOUND);
        throw error;
      }
      return serializeGuardAlert(alert, guardId, serialize);
    },

    /**
     * G-05 (D22, D35, D36): el guardia acepta una alerta en `searching`. Orden de errores:
     * 404 (no la ve) -> 409 ALERT_TAKEN (la ve pero ya no está disponible) -> 409 INVALID_STATE
     * (ya atiende otra). Lo de atender otra va después de la visibilidad para que un guardia
     * ocupado no pueda distinguir una alerta ajena de una inexistente por el tipo de error.
     */
    async accept(guardId: string, alertId: string): Promise<AlertJson> {
      const { alert: found, guard, ignored, location } = await loadVisibilityContext(guardId, alertId);
      // Sin la condición de estado (D22): la que ya tomó otro sigue siendo "visible" y da 409.
      const visible = isAlertVisibleToGuard(
        { guardId: found.guardId, status: found.status, location },
        guard,
        { now: now(), timeZone, ignoredByGuard: ignored, skipStatusCheck: true },
      );
      if (!visible) throw notFound(ALERT_NOT_FOUND);
      if (found.status !== AlertStatus.searching || found.guardId !== null) throw alertTaken();

      const at = now();
      let accepted;
      try {
        accepted = await prisma.$transaction(async (tx) => {
          // Baja concurrente (BE-06): se bloquea la fila del guardia y se revisa que siga activo.
          // Una baja que llegue después espera a este commit y luego libera sus alertas.
          const active = await tx.$queryRaw<{ id: string }[]>`
            SELECT id::text AS id FROM users WHERE id = ${guardId}::uuid AND is_active FOR SHARE`;
          if (active.length === 0) throw notFound(ALERT_NOT_FOUND);

          // D36: el índice único es la garantía; esta consulta da el mensaje claro antes.
          const attending = await tx.alert.findFirst({
            where: { guardId, status: { in: [...ATTENDED_STATUSES] } },
            select: { id: true },
          });
          if (attending) throw invalidState(GUARD_ALREADY_ATTENDING);

          // D35: la asignación atómica; si otro guardia ganó la carrera, no afecta filas.
          const { count } = await tx.alert.updateMany({
            where: { id: alertId, status: AlertStatus.searching, guardId: null },
            data: { status: AlertStatus.in_progress, guardId, acceptedAt: at, statusChangedAt: at },
          });
          if (count === 0) throw alertTaken();
          await tx.alertStatusHistory.create({
            data: {
              alertId,
              fromStatus: AlertStatus.searching,
              toStatus: AlertStatus.in_progress,
              actorId: guardId,
              at,
            },
          });
          return tx.alert.findUniqueOrThrow({ where: { id: alertId }, include: ALERT_INCLUDE });
        });
      } catch (error) {
        // Carrera entre dos aceptaciones del mismo guardia: gana el índice de D36.
        if (esGuardiaOcupado(error)) throw invalidState(GUARD_ALREADY_ATTENDING);
        throw error;
      }
      // Después del commit: el dueño la ve aceptada y a los demás guardias les sale del listado.
      deps.onAlertChanged?.({ userId: accepted.userId, alertId, dispatch: true });
      return serializeGuardAlert(accepted, guardId, serialize);
    },

    /**
     * G-07 (D40): el guardia registra su llegada. Orden de errores: 404 (no es suya o no existe,
     * sin distinguirlas) -> 409 INVALID_STATE (es suya pero ya no está en `in_progress`) -> 422
     * OUTSIDE_GEOFENCE. Así un guardia ajeno nunca ve `remainingMeters` ni un 409. La distancia
     * sale de su última ubicación guardada (PUT /guard/location) y de la ubicación actual de la
     * alerta; el borde exacto cuenta como dentro (regla_geocerca.dart: distancia <= radio).
     * Sin ubicación de alguno de los dos (D37; una alerta en curso siempre tiene la suya) se
     * responde 422 con `remainingMeters: null`. Al dueño le avisa para que pueda confirmar (U-09).
     */
    async arrive(guardId: string, alertId: string): Promise<AlertJson> {
      const { alert, profile, location } = await loadVisibilityContext(guardId, alertId);
      try {
        assertAssignedGuard(alert, { id: guardId });
      } catch (error) {
        // Mismo texto que "no existe" (D40); el 404 genérico de ownership.ts lleva otro.
        if (error instanceof AppError && error.code === 'NOT_FOUND') throw notFound(ALERT_NOT_FOUND);
        throw error;
      }
      if (alert.status !== AlertStatus.in_progress) throw invalidState(ALERT_NOT_IN_ATTENDANCE);

      const guardLocation =
        profile.lastLocationLat !== null && profile.lastLocationLng !== null
          ? { lat: profile.lastLocationLat, lng: profile.lastLocationLng }
          : null;
      // Sin alguna de las dos ubicaciones la distancia es infinita: remainingMeters sale null.
      if (!guardLocation || !location) throw outsideGeofence(Number.POSITIVE_INFINITY);
      if (!isWithinRadius(location, geofenceMeters, guardLocation)) {
        throw outsideGeofence(metersRemaining(guardLocation, location, geofenceMeters));
      }

      const at = now();
      const arrived = await prisma.$transaction(async (tx) => {
        // Baja concurrente (BE-06): igual que accept, se bloquea al guardia y se revisa que siga activo.
        const active = await tx.$queryRaw<{ id: string }[]>`
          SELECT id::text AS id FROM users WHERE id = ${guardId}::uuid AND is_active FOR SHARE`;
        if (active.length === 0) throw notFound(ALERT_NOT_FOUND);

        // Solo pasa si sigue en curso y asignada a él (la escalada o una liberación pudo ganar).
        const { count } = await tx.alert.updateMany({
          where: { id: alertId, status: AlertStatus.in_progress, guardId },
          data: { status: AlertStatus.guard_arrived, arrivedAt: at, statusChangedAt: at },
        });
        if (count === 0) throw invalidState(ALERT_NOT_IN_ATTENDANCE);
        await tx.alertStatusHistory.create({
          data: {
            alertId,
            fromStatus: AlertStatus.in_progress,
            toStatus: AlertStatus.guard_arrived,
            actorId: guardId,
            at,
          },
        });
        return tx.alert.findUniqueOrThrow({ where: { id: alertId }, include: ALERT_INCLUDE });
      });
      // Después del commit: el dueño ve la llegada. No estaba en `searching`, el despacho no cambia.
      deps.onAlertChanged?.({ userId: arrived.userId, alertId, dispatch: false });
      return serializeGuardAlert(arrived, guardId, serialize);
    },

    /**
     * G-03 (extra del front): el guardia deja de ver una alerta (D39). Idempotente: la visibilidad
     * se evalúa sin el filtro de "ignorada", así que repetirlo responde 200. Si la alerta es suya
     * (asignada) la asignación manda (D22): responde 200 sin registrar nada, para que una
     * liberación posterior no la deje oculta para él. El contrato no define un error para eso.
     * No avisa al dueño (no ve las ignoradas ni cambia nada para él) ni al despacho (a los demás
     * guardias no les cambia): solo se recalculan el listado y el detalle del propio guardia.
     */
    async ignore(guardId: string, alertId: string): Promise<null> {
      const { alert, guard, location } = await loadVisibilityContext(guardId, alertId);
      const visible = isAlertVisibleToGuard(
        { guardId: alert.guardId, status: alert.status, location },
        guard,
        { now: now(), timeZone, ignoredByGuard: false },
      );
      if (!visible) throw notFound(ALERT_NOT_FOUND);
      if (isAssignedTo(alert, guardId)) return null;
      const { count } = await prisma.alertIgnore.createMany({
        data: [{ guardId, alertId }],
        skipDuplicates: true,
      });
      // Un segundo ignore no cambia nada: no hace falta recalcular sus canales.
      if (count > 0) deps.onGuardChanged?.(guardId);
      return null;
    },
  };
}

export type GuardService = ReturnType<typeof createGuardService>;
