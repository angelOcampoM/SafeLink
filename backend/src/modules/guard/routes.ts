import type { FastifyInstance, FastifyRequest } from 'fastify';
import { AppError, notFound } from '../../errors/app-error.js';
import { ok } from '../../http/envelope.js';
import { locationBodySchema } from '../../http/location-schema.js';
import { parse, parseIdParam } from '../../http/validate.js';
import { ALERT_NOT_FOUND } from '../alerts/service.js';
import type { GuardService } from './service.js';

export interface GuardRoutesOptions {
  /** Lo arma app.ts: lo comparten las rutas REST y, en el paso siguiente, los canales SSE. */
  service: GuardService;
}

/**
 * Vista del guardia (BE-04). El acceso lo decide la política central
 * (src/security/policies.ts): todas son del rol guard y siempre sobre el propio guardia
 * en sesión (`request.user.id`), nunca un id del cliente salvo el de la alerta.
 */
export async function guardRoutes(app: FastifyInstance, options: GuardRoutesOptions): Promise<void> {
  const { service } = options;

  // G-01 (extra del front)
  app.get('/guard/me', async (request) => ok(await service.me(request.user.id)));

  // Extra del front: historial y métricas comparten lista (D41)
  app.get('/guard/history', async (request) => ok(await service.history(request.user.id)));
  app.get('/guard/metrics', async (request) => ok(await service.metrics(request.user.id)));

  // G-06: límite por guardia (no por IP) y en preHandler, ya autenticado; mismo criterio que U-07.
  const locationLimit = {
    max: app.config.RATE_LIMIT_LOCATIONS_PER_WINDOW,
    timeWindow: app.config.LOCATION_UPDATE_SECONDS * 1000,
    hook: 'preHandler' as const,
    keyGenerator: (request: FastifyRequest): string => request.user?.id ?? request.ip,
  };
  app.put('/guard/location', { config: { rateLimit: locationLimit } }, async (request) => {
    const body = parse(locationBodySchema, request.body);
    return ok(await service.updateLocation(request.user.id, body.location));
  });

  /** `:id` de la alerta; un UUID mal formado responde igual que una inexistente (D40). */
  function alertId(request: FastifyRequest): string {
    try {
      return parseIdParam((request.params as { id?: unknown }).id);
    } catch (error) {
      if (error instanceof AppError && error.code === 'NOT_FOUND') throw notFound(ALERT_NOT_FOUND);
      throw error;
    }
  }

  // G-04
  app.get('/guard/alerts/:id', async (request) =>
    ok(await service.getAlert(request.user.id, alertId(request))),
  );

  // G-05: sin cuerpo; 200 (no crea un recurso, D22).
  app.post('/guard/alerts/:id/accept', async (request) =>
    ok(await service.accept(request.user.id, alertId(request))),
  );

  // G-03 (extra del front): idempotente; 200 con data null (safelink_service.dart:195).
  app.post('/guard/alerts/:id/ignore', async (request) =>
    ok(await service.ignore(request.user.id, alertId(request))),
  );
}
