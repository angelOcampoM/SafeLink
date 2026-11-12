// BE-01 paso 6: deny-by-default al arrancar. Sin base de datos: la instancia solo registra el
// mecanismo (registerRouteGuards) y rutas mínimas; `authenticate` se sustituye por un stub porque
// aquí solo importa que el arranque aborte o no.
import Fastify, { type FastifyContextConfig, type FastifyInstance } from 'fastify';
import request from 'supertest';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { loadConfig } from '../../../src/config/env.js';
import { registerErrorHandling } from '../../../src/http/error-handler.js';
import { Role } from '../../../src/generated/prisma/enums.js';
import { ALL_ROLES, ROUTE_POLICIES, getPolicy, policiesEqual } from '../../../src/security/policies.js';
import { EXEMPT_ROUTES, registerRouteGuards } from '../../../src/security/guards.js';

const PREFIJO = '/api/v1';
let app: FastifyInstance | undefined;

afterEach(async () => {
  await app?.close().catch(() => undefined);
  app = undefined;
});

function instancia(): FastifyInstance {
  const a = Fastify({ logger: false });
  registerErrorHandling(a, { isProduction: false });
  a.decorate('authenticate', async () => undefined);
  registerRouteGuards(a, { prefix: PREFIJO });
  app = a;
  return a;
}

const MSG_SIN_POLITICA = /sin política de acceso/i;

describe('arranque: ruta bajo /api/v1 sin política central', () => {
  it('aborta el arranque (ready rechaza) con GET /api/v1/inventada', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.get('/inventada', async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(MSG_SIN_POLITICA);
  });

  it('el mensaje nombra método y ruta para localizar el hueco', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.get('/inventada', async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow('GET /inventada');
  });

  it('aborta si la ruta existe en la política pero con OTRO método (DELETE /auth/me)', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.delete('/auth/me', async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(MSG_SIN_POLITICA);
  });

  it('aborta aunque una sola de varias rutas carezca de política', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.get('/auth/me', async () => ({ data: 1 }));
        api.get('/guard/me', async () => ({ data: 1 }));
        api.get('/sin/politica', async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(MSG_SIN_POLITICA);
  });

  it('aborta con una ruta registrada con route() para varios métodos si uno no tiene política', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.route({ method: ['GET', 'POST'], url: '/auth/me', handler: async () => ({ data: 1 }) });
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(MSG_SIN_POLITICA);
  });

  it('arranca con rutas que sí tienen política (GET /auth/me, GET /guard/me)', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.get('/auth/me', async () => ({ data: 1 }));
        api.get('/guard/me', async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).resolves.toBeDefined();
  });

  it('buildApp real: una ruta extra sin política tampoco arranca', async () => {
    const a = buildApp(loadConfig({ NODE_ENV: 'test', JWT_SECRET: 'x'.repeat(32) }));
    app = a;
    void a.register(
      async (api) => {
        api.get('/health-extra', async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(MSG_SIN_POLITICA);
  });
});

describe('arranque: config local que contradice la política central', () => {
  it.each([
    ['roles distintos (admin donde la central es guard)', { roles: [Role.admin] }, '/guard/me'],
    ['roles de más', { roles: [Role.guard, Role.admin] }, '/guard/me'],
    ['public donde la central exige roles', { public: true }, '/guard/me'],
    ['custom donde la central exige roles', { auth: 'custom' as const }, '/guard/me'],
    ['roles donde la central es public', { roles: ALL_ROLES }, '/auth/login'],
    ['public donde la central es custom', { public: true }, '/auth/session'],
  ] as Array<[string, FastifyContextConfig, string]>)('%s -> aborta', async (_n, config, ruta) => {
    const a = instancia();
    const metodo = ruta === '/guard/me' ? 'get' : 'post';
    void a.register(
      async (api) => {
        api[metodo](ruta, { config }, async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(/contradice/i);
  });

  it('declarar más de una política (public + roles) aborta', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.get(
          '/guard/me',
          { config: { public: true, roles: [Role.guard] } },
          async () => ({ data: 1 }),
        );
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).rejects.toThrow(/más de una política/i);
  });

  it('config idéntica a la central NO aborta (aunque los roles vengan en otro orden)', async () => {
    const a = instancia();
    void a.register(
      async (api) => {
        api.get('/guard/me', { config: { roles: [Role.guard] } }, async () => ({ data: 1 }));
        api.get('/auth/me', { config: { roles: [Role.admin, Role.guard, Role.protected_user] } }, async () => ({
          data: 1,
        }));
        api.post('/auth/login', { config: { public: true } }, async () => ({ data: 1 }));
        api.post('/auth/session', { config: { auth: 'custom' } }, async () => ({ data: 1 }));
      },
      { prefix: PREFIJO },
    );
    await expect(a.ready()).resolves.toBeDefined();
  });
});

describe('arranque: rutas fuera del prefijo', () => {
  it('solo GET /health está exento', () => {
    expect([...EXEMPT_ROUTES]).toEqual(['GET /health']);
  });

  it('GET /health fuera del prefijo no aborta', async () => {
    const a = instancia();
    a.get('/health', async () => ({ data: { status: 'ok' } }));
    await expect(a.ready()).resolves.toBeDefined();
    const res = await request(a.server).get('/health');
    expect(res.status).toBe(200);
  });

  it('HEAD /health (generado por Fastify) tampoco aborta', async () => {
    const a = instancia();
    a.get('/health', async () => ({ data: { status: 'ok' } }));
    await a.ready();
    expect((await request(a.server).head('/health')).status).toBe(200);
  });

  it.each([
    ['GET', '/otra'],
    ['GET', '/'],
    ['POST', '/health'],
    ['GET', '/health/detalle'],
    ['GET', '/api/v1'],
    ['GET', '/api/v1x/auth/me'],
    ['GET', '/api/v2/auth/me'],
    ['GET', '/admin/guards'],
  ] as const)('%s %s fuera del prefijo y no exenta -> aborta', async (metodo, ruta) => {
    const a = instancia();
    void a.register(async (raiz) => {
      raiz.route({ method: metodo, url: ruta, handler: async () => ({ data: 1 }) });
    });
    await expect(a.ready()).rejects.toThrow(/fuera de \/api\/v1/);
  });

  it('GET y POST juntos en /health: aborta porque POST no está exenta', async () => {
    const a = instancia();
    void a.register(async (raiz) => {
      raiz.route({ method: ['GET', 'POST'], url: '/health', handler: async () => ({ data: 1 }) });
    });
    await expect(a.ready()).rejects.toThrow(/fuera de \/api\/v1/);
  });

  it('buildApp sin prisma (solo /health) arranca', async () => {
    const a = buildApp(loadConfig({ NODE_ENV: 'test', JWT_SECRET: 'x'.repeat(32) }));
    app = a;
    await expect(a.ready()).resolves.toBeDefined();
    const res = await request(a.server).get('/health');
    expect(res.body).toEqual({ data: { status: 'ok' } });
  });
});

describe('policies.ts: utilidades', () => {
  it('getPolicy devuelve undefined para claves heredadas del prototipo y rutas desconocidas', () => {
    expect(getPolicy('GET', '/__proto__')).toBeUndefined();
    expect(getPolicy('GET', 'constructor')).toBeUndefined();
    expect(getPolicy('GET', '/nada')).toBeUndefined();
    expect(getPolicy('PATCH', '/auth/me')).toBeUndefined();
  });

  it('getPolicy es insensible al método en minúsculas y exacta en la ruta', () => {
    expect(getPolicy('get', '/guard/me')).toEqual([Role.guard]);
    expect(getPolicy('GET', '/guard/me/')).toBeUndefined();
    expect(getPolicy('GET', '/GUARD/me')).toBeUndefined();
  });

  it('policiesEqual: mismo conjunto sin importar el orden, y literales distintos no son iguales', () => {
    expect(policiesEqual([Role.admin, Role.guard], [Role.guard, Role.admin])).toBe(true);
    expect(policiesEqual([Role.admin], [Role.guard])).toBe(false);
    expect(policiesEqual('public', 'custom')).toBe(false);
    expect(policiesEqual('public', [Role.admin])).toBe(false);
    expect(policiesEqual('public', 'public')).toBe(true);
  });

  it('ROUTE_POLICIES está congelado', () => {
    expect(Object.isFrozen(ROUTE_POLICIES)).toBe(true);
  });
});
