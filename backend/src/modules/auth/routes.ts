import type { FastifyInstance } from 'fastify';
import { createPasswordHasher } from '../../auth/password.js';
import { durationToSeconds } from '../../config/duration.js';
import type { PrismaClient } from '../../db/prisma.js';
import { ok } from '../../http/envelope.js';
import { parse } from '../../http/validate.js';
import { loginBodySchema, refreshBodySchema, sessionBodySchema } from './schemas.js';
import { createAuthService } from './service.js';

export interface AuthRoutesOptions {
  prisma: PrismaClient;
}

/**
 * Requiere el plugin de auth (authenticate, signAccessToken) y @fastify/rate-limit
 * (registrado con global: false) ya cargados en un ancestro.
 */
export async function authRoutes(app: FastifyInstance, options: AuthRoutesOptions): Promise<void> {
  const { config } = app;
  const hasher = createPasswordHasher({
    memoryCost: config.ARGON2_MEMORY_KIB,
    timeCost: config.ARGON2_TIME_COST,
    parallelism: config.ARGON2_PARALLELISM,
  });
  const service = createAuthService({
    prisma: options.prisma,
    config,
    hasher,
    signAccessToken: app.signAccessToken,
  });

  // Precalienta el hash ficticio para que el primer login con correo inexistente no tarde de más.
  app.addHook('onReady', async () => {
    await hasher.dummyHash();
  });

  const loginLimit = {
    max: config.RATE_LIMIT_LOGIN_MAX,
    timeWindow: durationToSeconds(config.RATE_LIMIT_LOGIN_WINDOW) * 1000,
  };
  const refreshLimit = {
    max: config.RATE_LIMIT_REFRESH_MAX,
    timeWindow: durationToSeconds(config.RATE_LIMIT_REFRESH_WINDOW) * 1000,
  };

  // El acceso (público, roles o verificación propia) lo decide la política central
  // (src/security/policies.ts) y lo aplica el hook onRoute de src/security/guards.ts:
  // estas rutas ya no declaran config.public/roles/auth ni preHandler de autenticación.
  app.post('/auth/login', { config: { rateLimit: loginLimit } }, async (request) => {
    const body = parse(loginBodySchema, request.body);
    return ok(await service.login(body.email, body.password));
  });

  app.post('/auth/refresh', { config: { rateLimit: refreshLimit } }, async (request) => {
    const body = parse(refreshBodySchema, request.body);
    return ok(await service.refresh(body.refreshToken));
  });

  app.get('/auth/me', async (request) => ok(await service.me(request.user.id)));

  app.post('/auth/logout', async (request) => ok(await service.logout(request.user.sid)));

  // Política 'custom' (D7, D25): sin el control general. 401 solo por token ausente,
  // inválido o vencido; el resto de fallos de sesión responden 200 con data: null.
  app.post('/auth/session', { config: { rateLimit: refreshLimit } }, async (request) => {
    const claims = app.verifyAccessToken(request);
    const body = parse(sessionBodySchema, request.body);
    return ok(await service.session(claims, body.userId));
  });
}
