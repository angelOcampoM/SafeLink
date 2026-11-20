// Canales en tiempo real (SSE, D3) bajo /api/v1/events/<canal del front>.
// BE-03 implementa alerts/active y BE-04 guard/alerts y guard/alerts/:id;
// admin/alerts/escalated (BE-05) se agrega aquí con el mismo SseHub.
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { findLiveSessionUser } from '../../auth/session.js';
import type { PrismaClient } from '../../db/prisma.js';
import { notFound, unauthorized } from '../../errors/app-error.js';
import { parseIdParam } from '../../http/validate.js';
import {
  alertTopic,
  alertsTopicForUser,
  dispatchTopic,
  guardTopic,
} from '../../realtime/event-bus.js';
import type { SseHub } from '../../realtime/sse.js';
import { ALERT_NOT_FOUND, type AlertsService } from '../alerts/service.js';
import type { GuardService } from '../guard/service.js';

export interface EventsRoutesOptions {
  prisma: PrismaClient;
  hub: SseHub;
  alerts: AlertsService;
  guard: GuardService;
}

/** `exp` del access token ya verificado por `authenticate` (para cerrar el stream a tiempo, D26). */
function expiraEnMs(app: FastifyInstance, request: FastifyRequest): number {
  const token = /^Bearer (\S+)$/.exec(request.headers.authorization ?? '')?.[1];
  const payload = token ? app.jwt.decode<{ exp?: unknown }>(token) : null;
  if (typeof payload?.exp !== 'number') throw unauthorized();
  return payload.exp * 1000;
}

export async function eventsRoutes(app: FastifyInstance, options: EventsRoutesOptions): Promise<void> {
  const { prisma, hub, alerts, guard } = options;

  // U-07 · U-08 · U-09: la alerta activa del usuario (a lo más una, D15) o null.
  app.get('/events/alerts/active', async (request, reply) => {
    const { id: userId, sid } = request.user;
    hub.open(request, reply, {
      name: 'alerts/active',
      topic: alertsTopicForUser(userId),
      snapshot: () => alerts.active(userId),
      sessionAlive: async () => (await findLiveSessionUser(prisma, userId, sid)) !== null,
      tokenExpiresAtMs: expiraEnMs(app, request),
    });
    return reply;
  });

  // G-03: lista completa de PrioritizedAlert, calculada por guardia en cada emisión (D22, D34).
  // Se refresca con el aviso global de despacho, con los cambios del guardia y en cada ping
  // (para reflejar la espera y el cambio de turno).
  app.get('/events/guard/alerts', async (request, reply) => {
    const { id: guardId, sid } = request.user;
    hub.open(request, reply, {
      name: 'guard/alerts',
      topics: [dispatchTopic, guardTopic(guardId)],
      refreshOnPing: true,
      snapshot: () => guard.listAvailable(guardId),
      sessionAlive: async () => (await findLiveSessionUser(prisma, guardId, sid)) !== null,
      tokenExpiresAtMs: expiraEnMs(app, request),
    });
    return reply;
  });

  // G-04: detalle de una alerta; mismo snapshot y misma visibilidad que GET /guard/alerts/:id (D22).
  // Un :id mal formado NO es 404 HTTP: el stream abre, manda NOT_FOUND como evento y cierra (D34).
  // Escucha la alerta (el usuario se mueve o confirma, G-06) y al guardia (ignorar, ubicación/ETA);
  // refresca en cada ping para cerrarse si deja de ser visible por turno o cobertura (D22).
  app.get('/events/guard/alerts/:id', async (request, reply) => {
    const { id: guardId, sid } = request.user;
    let alertId: string | null = null;
    try {
      // En minúsculas: el bus publica alertTopic con el id de la base, y un UUID en mayúsculas
      // dejaría el stream sin avisos (solo con el ping).
      alertId = parseIdParam((request.params as { id?: unknown }).id).toLowerCase();
    } catch {
      alertId = null;
    }
    hub.open(request, reply, {
      name: 'guard/alerts/:id',
      topics: alertId ? [alertTopic(alertId), guardTopic(guardId)] : [guardTopic(guardId)],
      refreshOnPing: true,
      snapshot: async () => {
        if (!alertId) throw notFound(ALERT_NOT_FOUND);
        return guard.getAlert(guardId, alertId);
      },
      sessionAlive: async () => (await findLiveSessionUser(prisma, guardId, sid)) !== null,
      tokenExpiresAtMs: expiraEnMs(app, request),
    });
    return reply;
  });
}
