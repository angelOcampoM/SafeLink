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
import { devicesRoutes } from './modules/devices/routes.js';
import { createDevicesService } from './modules/devices/service.js';
import { escalationRoutes } from './modules/escalation/routes.js';
import { createEscalationService, type EscalationService } from './modules/escalation/service.js';
import { eventsRoutes } from './modules/events/routes.js';
import { guardRoutes } from './modules/guard/routes.js';
import { createGuardService } from './modules/guard/service.js';
import { createAlertDispatcher } from './notifications/dispatcher.js';
import { createFcmNotifier } from './notifications/fcm-notifier.js';
import { createNoopNotifier } from './notifications/noop-notifier.js';
import type { PushLogger, PushNotifier } from './notifications/push-notifier.js';
import { authPluginRoot } from './plugins/auth.js';
import {
  alertTopic,
  alertsTopicForUser,
  createMemoryEventBus,
  dispatchTopic,
  escalatedTopic,
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
    /** Escalamiento automático (BE-05). Solo existe con base de datos; las pruebas llaman a `sweep()`. */
    escalation?: EscalationService;
  }
}

export const API_PREFIX = '/api/v1';

export interface AppDependencies {
  /** Sin prisma solo se registra /health (las rutas con base de datos no existen). */
  prisma?: PrismaClient;
  /** Bus de eventos del tiempo real (D3); por defecto, uno en memoria. */
  bus?: EventBus;
  /** Notificador push (D43); por defecto se arma según PUSH_PROVIDER. Inyectarlo enciende el despachador (D44). */
  push?: PushNotifier;
}

function buildPushNotifier(config: Config, logger: PushLogger): PushNotifier {
  if (config.PUSH_PROVIDER !== 'fcm') return createNoopNotifier(logger);
  // Un Config armado sin loadConfig podría omitirlos: se falla en vez de caer en silencio al no-op.
  if (!config.FCM_PROJECT_ID || !config.FCM_SERVICE_ACCOUNT_FILE) {
    throw new Error('PUSH_PROVIDER=fcm requiere FCM_PROJECT_ID y FCM_SERVICE_ACCOUNT_FILE');
  }
  return createFcmNotifier({
    projectId: config.FCM_PROJECT_ID,
    serviceAccountFile: config.FCM_SERVICE_ACCOUNT_FILE,
    maxAttempts: config.PUSH_MAX_ATTEMPTS,
    ttlSeconds: config.ACCEPT_TIMEOUT_SECONDS,
    logger,
  });
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
  // Con PUSH_PROVIDER=fcm, una cuenta de servicio ausente o inválida lanza aquí y la API no arranca.
  const push: PushNotifier = deps.push ?? buildPushNotifier(config, app.log);
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
      etaRoundingSeconds: config.ETA_ROUNDING_SECONDS,
      guardGridMeters: config.ETA_GUARD_GRID_METERS,
    };
    // Un solo cableado de avisos de alerta para los servicios del usuario y del guardia.
    const devices = createDevicesService({ prisma });
    // Aviso push (D44): sin PUSH_PROVIDER=fcm ni doble inyectado el notificador es el no-op, así que
    // el despachador se apaga y no gasta consultas. BE-06 reutiliza `alertDispatcher.dispatchAlert`.
    const alertDispatcher = createAlertDispatcher({
      prisma,
      push,
      devices,
      logger: app.log,
      timeZone: config.TZ_SHIFTS,
      maxTokensPerAlert: config.PUSH_MAX_TOKENS_PER_ALERT,
      enabled: deps.push !== undefined || config.PUSH_PROVIDER === 'fcm',
    });
    const onAlertChanged = ({ userId, alertId, dispatch, published }: AlertChange): void => {
      bus.publish(alertsTopicForUser(userId));
      bus.publish(alertTopic(alertId));
      if (dispatch) bus.publish(dispatchTopic);
      // Fire-and-forget, después del commit: la respuesta no espera al push.
      if (published) alertDispatcher.notifyPublished(alertId);
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
      geofenceMeters: config.GEOFENCE_METERS,
      waitMetersPerMinute: config.WAIT_METERS_PER_MINUTE,
      onUserAlertChanged: (userId) => bus.publish(alertsTopicForUser(userId)),
      onGuardChanged: (guardId) => bus.publish(guardTopic(guardId)),
      onAlertChanged,
    });
    // U-09 · A-04 (BE-05, D14): escala las alertas vencidas y avisa a todos los canales afectados.
    const escalation = createEscalationService({
      prisma,
      limits: {
        acceptTimeoutSeconds: config.ACCEPT_TIMEOUT_SECONDS,
        confirmTimeoutSeconds: config.CONFIRM_TIMEOUT_SECONDS,
      },
      serialize,
      falseAlarms: { limit: config.FALSE_ALARM_LIMIT, blockDays: config.BLOCK_DAYS },
      adminNoteMaxLength: config.ADMIN_NOTE_MAX_LENGTH,
      logger: app.log,
      // A-04: sale de la bandeja del admin; el detalle del guardia que la atendió la ve resuelta.
      onResolved: ({ alertId }) => {
        bus.publish(escalatedTopic);
        bus.publish(alertTopic(alertId));
      },
      onEscalated: ({ alertId, userId, guardId, from }) => {
        bus.publish(alertsTopicForUser(userId)); // deja de ser su alerta activa: alerts/active emite null
        bus.publish(alertTopic(alertId)); // el detalle del guardia la ve escalada
        // Salió de `searching`: desaparece del listado de los guardias (D34).
        if (from !== 'guard_arrived') bus.publish(dispatchTopic);
        if (guardId) bus.publish(guardTopic(guardId)); // el guardia que atendía queda libre (D36)
        bus.publish(escalatedTopic); // entra a la bandeja del admin
      },
    });
    app.decorate('escalation', escalation);
    app.addHook('onReady', async () => {
      escalation.start(config.ESCALATION_SWEEP_SECONDS);
    });
    // Los streams abiertos y el temporizador no deben impedir que la API se apague.
    app.addHook('preClose', async () => {
      escalation.stop();
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
        await api.register(adminRoutes, { prisma, serialize });
        await api.register(alertsRoutes, { prisma, service: alerts, photos, photoUrls });
        await api.register(guardRoutes, { service: guard });
        await api.register(devicesRoutes, { service: devices });
        await api.register(escalationRoutes, { service: escalation });
        await api.register(eventsRoutes, { prisma, hub, alerts, guard, escalation });
      },
      { prefix: API_PREFIX },
    );
  }
  return app;
}
