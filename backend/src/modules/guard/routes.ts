import type { FastifyInstance } from 'fastify';
import { AppError, notFound } from '../../errors/app-error.js';
import { ok } from '../../http/envelope.js';
import { parseIdParam } from '../../http/validate.js';
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

  // G-04
  app.get('/guard/alerts/:id', async (request) => {
    let id: string;
    try {
      id = parseIdParam((request.params as { id?: unknown }).id);
    } catch (error) {
      // Un UUID mal formado responde igual que una alerta inexistente (D40).
      if (error instanceof AppError && error.code === 'NOT_FOUND') throw notFound(ALERT_NOT_FOUND);
      throw error;
    }
    return ok(await service.getAlert(request.user.id, id));
  });
}
