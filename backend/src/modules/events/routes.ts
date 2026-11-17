// Canales en tiempo real (SSE, D3) bajo /api/v1/events/<canal del front>.
// BE-03 implementa alerts/active; guard/alerts, guard/alerts/:id (BE-04) y
// admin/alerts/escalated (BE-05) se agregan aquí con el mismo SseHub.
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { findLiveSessionUser } from '../../auth/session.js';
import type { PrismaClient } from '../../db/prisma.js';
import { unauthorized } from '../../errors/app-error.js';
import { alertsTopicForUser } from '../../realtime/event-bus.js';
import type { SseHub } from '../../realtime/sse.js';
import type { AlertsService } from '../alerts/service.js';

export interface EventsRoutesOptions {
  prisma: PrismaClient;
  hub: SseHub;
  alerts: AlertsService;
}

/** `exp` del access token ya verificado por `authenticate` (para cerrar el stream a tiempo, D26). */
function expiraEnMs(app: FastifyInstance, request: FastifyRequest): number {
  const token = /^Bearer (\S+)$/.exec(request.headers.authorization ?? '')?.[1];
  const payload = token ? app.jwt.decode<{ exp?: unknown }>(token) : null;
  if (typeof payload?.exp !== 'number') throw unauthorized();
  return payload.exp * 1000;
}

export async function eventsRoutes(app: FastifyInstance, options: EventsRoutesOptions): Promise<void> {
  const { prisma, hub, alerts } = options;

  // U-07 · U-08 · U-09: la alerta activa del usuario (a lo más una, D15) o null.
  app.get('/events/alerts/active', async (request, reply) => {
    const { id: userId, sid } = request.user;
    hub.open(request, reply, {
      topic: alertsTopicForUser(userId),
      snapshot: () => alerts.active(userId),
      sessionAlive: async () => (await findLiveSessionUser(prisma, userId, sid)) !== null,
      tokenExpiresAtMs: expiraEnMs(app, request),
    });
    return reply;
  });
}
