import type { FastifyInstance, FastifyRequest } from 'fastify';
import { durationToSeconds } from '../../config/duration.js';
import { ok } from '../../http/envelope.js';
import { parse } from '../../http/validate.js';
import { deviceTokenBodySchema } from './schemas.js';
import type { DevicesService } from './service.js';

export interface DevicesRoutesOptions {
  service: DevicesService;
}

/**
 * Requiere @fastify/rate-limit (global: false) cargado en un ancestro. El acceso (solo guard)
 * lo decide la política central (src/security/policies.ts).
 */
export async function devicesRoutes(
  app: FastifyInstance,
  options: DevicesRoutesOptions,
): Promise<void> {
  const { service } = options;

  // Límite por usuario (no por IP) y en preHandler, ya autenticado. Reutiliza el límite de
  // refresh: es una operación de sesión poco frecuente y holgada para un uso legítimo.
  const deviceTokenLimit = {
    max: app.config.RATE_LIMIT_REFRESH_MAX,
    timeWindow: durationToSeconds(app.config.RATE_LIMIT_REFRESH_WINDOW) * 1000,
    hook: 'preHandler' as const,
    keyGenerator: (request: FastifyRequest): string => request.user?.id ?? request.ip,
  };

  // EXCEPCIÓN de contrato (D42): no existe en el front. Idempotente; responde 200 con data null.
  // El token nunca se registra ni se devuelve.
  app.put('/users/me/device-token', { config: { rateLimit: deviceTokenLimit } }, async (request) => {
    const body = parse(deviceTokenBodySchema, request.body);
    return ok(await service.register(request.user.id, request.user.sid, body.token));
  });
}
