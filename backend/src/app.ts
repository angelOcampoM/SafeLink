import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import type { Config } from './config/env.js';
import type { PrismaClient } from './db/prisma.js';
import { tooManyRequests } from './errors/app-error.js';
import { createFrameworkErrorHandler, registerErrorHandling } from './http/error-handler.js';
import { authRoutes } from './modules/auth/routes.js';
import { authPluginRoot } from './plugins/auth.js';
import { healthRoutes } from './routes/health.js';
import { registerRouteGuards } from './security/guards.js';

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
  }
}

export const API_PREFIX = '/api/v1';

export interface AppDependencies {
  /** Sin prisma solo se registra /health (las rutas con base de datos no existen). */
  prisma?: PrismaClient;
}

export function buildApp(config: Config, deps: AppDependencies = {}): FastifyInstance {
  const app = Fastify({
    bodyLimit: config.BODY_LIMIT_BYTES,
    frameworkErrors: createFrameworkErrorHandler(config.NODE_ENV === 'production'),
    logger:
      config.NODE_ENV === 'test'
        ? false
        : {
            level: 'info',
            redact: {
              paths: [
                'req.headers.authorization',
                'req.headers.cookie',
                'req.headers["set-cookie"]',
                'req.headers["x-api-key"]',
                'res.headers["set-cookie"]',
              ],
              censor: '[REDACTADO]',
            },
            serializers: {
              req(req: { method?: string; url?: string; hostname?: string; ip?: string }) {
                return {
                  method: req.method,
                  url: req.url?.split('?')[0],
                  host: req.hostname,
                  remoteAddress: req.ip,
                };
              },
            },
          },
  });
  app.decorate('config', config);
  registerErrorHandling(app, { isProduction: config.NODE_ENV === 'production' });
  // Las respuestas de la API no se cachean (llevan tokens y datos personales). Va en la raíz
  // para cubrir también el 404 de rutas inexistentes bajo el prefijo.
  app.addHook('onSend', async (request, reply) => {
    const path = request.url.split('?')[0] ?? '';
    if (path === API_PREFIX || path.startsWith(`${API_PREFIX}/`)) {
      void reply.header('cache-control', 'no-store');
    }
  });
  // Deny-by-default: antes de registrar cualquier ruta (los hooks onRoute solo ven las siguientes).
  registerRouteGuards(app, { prefix: API_PREFIX });
  void app.register(healthRoutes);
  const { prisma } = deps;
  if (prisma) {
    void app.register(authPluginRoot, { prisma });
    void app.register(
      async (api) => {
        // Solo se limitan las rutas que declaran config.rateLimit (login y refresh), por IP.
        await api.register(rateLimit, {
          global: false,
          errorResponseBuilder: () => tooManyRequests(),
          addHeaders: {
            'x-ratelimit-limit': false,
            'x-ratelimit-remaining': false,
            'x-ratelimit-reset': false,
            'retry-after': true,
          },
          addHeadersOnExceeding: {
            'x-ratelimit-limit': false,
            'x-ratelimit-remaining': false,
            'x-ratelimit-reset': false,
          },
        });
        await api.register(authRoutes, { prisma });
      },
      { prefix: API_PREFIX },
    );
  }
  return app;
}
