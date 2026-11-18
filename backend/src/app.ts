import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import type { Config } from './config/env.js';
import type { PrismaClient } from './db/prisma.js';
import { tooManyRequests } from './errors/app-error.js';
import { createFrameworkErrorHandler, registerErrorHandling } from './http/error-handler.js';
import { adminRoutes } from './modules/admin/routes.js';
import { alertsRoutes } from './modules/alerts/routes.js';
import { createAlertsService, type AlertChange } from './modules/alerts/service.js';
import { authRoutes } from './modules/auth/routes.js';
import { eventsRoutes } from './modules/events/routes.js';
import { guardRoutes } from './modules/guard/routes.js';
import { createGuardService } from './modules/guard/service.js';
import { authPluginRoot } from './plugins/auth.js';
import {
  alertTopic,
  alertsTopicForUser,
  createMemoryEventBus,
  dispatchTopic,
  guardTopic,
  type EventBus,
} from './realtime/event-bus.js';
import { createSseHub } from './realtime/sse.js';
import { healthRoutes } from './routes/health.js';
import { registerRouteGuards } from './security/guards.js';
import { createDiskPhotoStorage } from './storage/photo-storage.js';
import { createPhotoUrlSigner } from './storage/photo-urls.js';

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
  }
}

export const API_PREFIX = '/api/v1';

export interface AppDependencies {
  /** Sin prisma solo se registra /health (las rutas con base de datos no existen). */
  prisma?: PrismaClient;
  /** Bus de eventos del tiempo real (D3); por defecto, uno en memoria. */
  bus?: EventBus;
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
    // Alertas (BE-03): un solo servicio para las rutas REST y el canal alerts/active. Cada
    // cambio publica en el bus, y el canal SSE de ese usuario manda un snapshot nuevo.
    const bus = deps.bus ?? createMemoryEventBus();
    const hub = createSseHub(bus, {
      pingSeconds: config.SSE_PING_SECONDS,
      maxConnectionsPerUser: config.SSE_MAX_CONNECTIONS_PER_USER,
    });
    const photos = createDiskPhotoStorage(config.PHOTO_DIR);
    const photoUrls = createPhotoUrlSigner({
      secret: config.JWT_SECRET,
      publicApiUrl: config.PUBLIC_API_URL ?? `http://127.0.0.1:${String(config.PORT)}/api/v1`,
      ttlSeconds: config.PHOTO_URL_TTL_SECONDS,
    });
    const serialize = {
      photoUrl: (alertId: string, photoKey: string | null) =>
        photoKey ? photoUrls.url(alertId, photoKey) : null,
      guardMetersPerMinute: config.GUARD_METERS_PER_MINUTE,
    };
    // Un solo cableado de avisos de alerta para los servicios del usuario y del guardia.
    const onAlertChanged = ({ userId, alertId, dispatch }: AlertChange): void => {
      bus.publish(alertsTopicForUser(userId));
      bus.publish(alertTopic(alertId));
      if (dispatch) bus.publish(dispatchTopic);
    };
    const alerts = createAlertsService({
      prisma,
      serialize,
      triggeredAtToleranceSeconds: config.TRIGGERED_AT_TOLERANCE_SECONDS,
      onAlertChanged,
    });
    const guard = createGuardService({
      prisma,
      serialize,
      timeZone: config.TZ_SHIFTS,
      waitMetersPerMinute: config.WAIT_METERS_PER_MINUTE,
      onUserAlertChanged: (userId) => bus.publish(alertsTopicForUser(userId)),
      onGuardChanged: (guardId) => bus.publish(guardTopic(guardId)),
      onAlertChanged,
    });
    // Los streams abiertos no deben impedir que la API se apague.
    app.addHook('preClose', async () => {
      hub.closeAll();
    });

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
        await api.register(adminRoutes, { prisma });
        await api.register(alertsRoutes, { prisma, service: alerts, photos, photoUrls });
        await api.register(guardRoutes, { service: guard });
        await api.register(eventsRoutes, { prisma, hub, alerts, guard });
      },
      { prefix: API_PREFIX },
    );
  }
  return app;
}
