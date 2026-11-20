// BE-01 paso 6, correcciones finales (integración): authenticate ausente, rate limit de
// /auth/session, normalización de rutas y recorrido de hooks registrados.
import Fastify, { type FastifyInstance } from 'fastify';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { API_PREFIX, buildApp } from '../../../src/app.js';
import { registerErrorHandling } from '../../../src/http/error-handler.js';
import { ok } from '../../../src/http/envelope.js';
import { registerRouteGuards } from '../../../src/security/guards.js';
import { ROUTE_POLICIES } from '../../../src/security/policies.js';
import { PASSWORD, configPrueba, hasherPrueba, login } from '../auth/helpers.js';
import { abrirDb, type ContextoDb } from '../db/helpers.js';

// Rutas que YA están implementadas: las demás se cubren con stubs más abajo.
// Al implementar una ruta nueva hay que agregarla aquí, o Fastify falla al
// arrancar con "Method 'X' already declared for route '...'" porque el stub
// choca con la ruta real. (BE-01: auth; BE-02: registro, ajustes y guardias.)
const REALES = new Set([
  // BE-01
  'POST /auth/login',
  'POST /auth/refresh',
  'POST /auth/logout',
  'GET /auth/me',
  'POST /auth/session',
  // BE-02
  'POST /auth/register',
  'PATCH /users/me/settings',
  'GET /admin/guards',
  'POST /admin/guards',
  'GET /admin/guards/:id',
  'PATCH /admin/guards/:id',
  'DELETE /admin/guards/:id',
  // BE-03
  'POST /alerts',
  'GET /alerts/mine',
  'POST /alerts/:id/locations',
  'POST /alerts/:id/confirm',
  'GET /alerts/:id/photo',
  'GET /events/alerts/active',
  // BE-04
  'GET /guard/me',
  'GET /guard/history',
  'GET /guard/metrics',
  'PUT /guard/location',
  'GET /guard/alerts/:id',
  'POST /guard/alerts/:id/accept',
  'POST /guard/alerts/:id/ignore',
  'POST /guard/alerts/:id/arrive',
  'GET /events/guard/alerts',
  'GET /events/guard/alerts/:id',
  // BE-05
  'GET /events/admin/alerts/escalated',
  'POST /admin/alerts/:id/resolve',
  // BE-06
  'PUT /admin/guards/:id/coverage',
  // BE-07
  'GET /admin/alerts',
  'GET /admin/metrics',
  'GET /admin/metrics/guards/:id',
  'GET /admin/users',
  'GET /admin/users/blocked',
  'DELETE /admin/users/:id/block',
  'PUT /users/me/device-token',
]);

describe('guards: ruta con roles sin authenticate decorado', () => {
  it('ready() rechaza con mensaje claro', async () => {
    const a = Fastify({ logger: false });
    registerErrorHandling(a, { isProduction: false });
    registerRouteGuards(a, { prefix: API_PREFIX });
    void a.register(
      async (api) => {
        api.get('/guard/me', async () => ({ data: 1 }));
      },
      { prefix: API_PREFIX },
    );
    await expect(a.ready()).rejects.toThrow(/authenticate/);
    await expect(a.ready()).rejects.toThrow(/\/guard\/me/);
    await a.close().catch(() => undefined);
  });

  it('una ruta public no necesita authenticate', async () => {
    const a = Fastify({ logger: false });
    registerRouteGuards(a, { prefix: API_PREFIX });
    void a.register(
      async (api) => {
        api.post('/auth/login', async () => ({ data: 1 }));
      },
      { prefix: API_PREFIX },
    );
    await expect(a.ready()).resolves.toBeDefined();
    await a.close();
  });
});

interface Registro {
  metodo: string;
  url: string;
  onRequest: unknown[];
}

let db: ContextoDb;
let app: FastifyInstance;
let guardToken = '';
const registro: Registro[] = [];

const GUARD_EMAIL = 'final-guardia@prueba.test';
const ADMIN_EMAIL = 'final-admin@prueba.test';
// Desde BE-06 ya NO queda ninguna ruta stub: las 38 de la política están implementadas.
// Las pruebas de normalización de abajo usan una ruta REAL (GET /admin/metrics/guards/:id) y
// comparan 404 contra 200, en vez de contar ejecuciones de un stub. El registro de stubs se
// deja puesto: si alguien agrega una clave a la política antes de implementarla, vuelve a
// cubrirla solo. Historial de la variable que había aquí: POST /guard/alerts/:id/arrive
// (real desde BE-04), POST /admin/alerts/:id/resolve (BE-05), DELETE /admin/users/:id/block
// (BE-07) y PUT /admin/guards/:id/coverage (BE-06).
let guardiaId = '';
let adminToken = '';

beforeAll(async () => {
  db = await abrirDb();
  const passwordHash = await hasherPrueba.hash(PASSWORD);
  const guardia = await db.prisma.user.create({
    data: {
      name: 'Final guardia',
      email: GUARD_EMAIL,
      phone: '7771234567',
      passwordHash,
      role: 'guard',
    },
  });
  guardiaId = guardia.id;
  await db.prisma.user.create({
    data: { name: 'Final admin', email: ADMIN_EMAIL, phone: '7771234567', passwordHash, role: 'admin' },
  });
  app = buildApp(configPrueba({ RATE_LIMIT_REFRESH_MAX: '3' }), { prisma: db.prisma });
  // Se agrega después de registerRouteGuards: ve cada ruta ya con los hooks del guard aplicados.
  app.addHook('onRoute', (opts) => {
    const metodos = Array.isArray(opts.method) ? opts.method : [opts.method];
    const oh = opts.onRequest;
    const lista = oh === undefined ? [] : Array.isArray(oh) ? [...(oh as unknown[])] : [oh];
    for (const m of metodos) registro.push({ metodo: m, url: opts.url, onRequest: lista });
  });
  void app.register(
    async (api) => {
      for (const clave of Object.keys(ROUTE_POLICIES)) {
        if (REALES.has(clave)) continue;
        const [metodo, ruta] = clave.split(' ') as [string, string];
        api.route({
          method: metodo as 'GET',
          url: ruta,
          handler: async () => ok({ ruta: clave }),
        });
      }
    },
    { prefix: API_PREFIX },
  );
  await app.ready();
  const res = await login(app, GUARD_EMAIL);
  guardToken = res.body.data.accessToken as string;
  adminToken = (await login(app, ADMIN_EMAIL)).body.data.accessToken as string;
}, 120_000);

afterAll(async () => {
  await app.close();
  await db.cerrar();
});

describe('POST /auth/session con rate limit (comparte el límite de refresh)', () => {
  it('con RATE_LIMIT_REFRESH_MAX=3, la petición 4 -> 429 TOO_MANY_REQUESTS', async () => {
    const sesion = () =>
      request(app.server)
        .post(`${API_PREFIX}/auth/session`)
        .set('Authorization', `Bearer ${guardToken}`)
        .send({ userId: '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11' });
    for (let i = 1; i <= 3; i += 1) {
      const res = await sesion();
      expect(res.status, `petición ${String(i)}`).toBe(200);
    }
    const res = await sesion();
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe('TOO_MANY_REQUESTS');
    expect(Object.keys(res.body)).toEqual(['error']);
    expect(res.headers['cache-control']).toBe('no-store');
  });
});

// Ruta REAL con un `:id` en el camino: con el id de un guardia responde 200, así que
// cualquier variante que acabe en 404 demuestra que el enrutador no la reconoció. El token es
// de admin porque la ruta es del admin.
describe('normalización de rutas: nada de lo que parezca /api/v1/admin/metrics/guards/:id llega al handler', () => {
  const variantes = (): string[] => [
    `/API/V1/admin/metrics/guards/${guardiaId}`,
    `/api/v1//admin/metrics/guards/${guardiaId}`,
    `/api/v1/admin/metrics/guards/${guardiaId}/`,
    `/api/v1/admin%2Fmetrics/guards/${guardiaId}`,
    `/api/v1/ADMIN/metrics/guards/${guardiaId}`,
    `/api/v1/admin/metrics/guards/${guardiaId}/%2e`,
    `/api/v1/./admin/metrics/guards/${guardiaId}`,
  ];

  it('cada variante con token de admin -> 404 NOT_FOUND', async () => {
    for (const ruta of variantes()) {
      const res = await request(app.server).get(ruta).set('Authorization', `Bearer ${adminToken}`);
      expect(res.status, ruta).toBe(404);
      expect(res.body.error.code, ruta).toBe('NOT_FOUND');
    }
  });

  it('control: la ruta exacta sí llega al manejador', async () => {
    const res = await request(app.server)
      .get(`${API_PREFIX}/admin/metrics/guards/${guardiaId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveProperty('attendedCount');
  });

  it('OPTIONS anónimo sobre una ruta con roles -> 404 (nunca 200)', async () => {
    const res = await request(app.server).options(
      `${API_PREFIX}/admin/metrics/guards/${guardiaId}`,
    );
    expect(res.status).toBe(404);
  });

  it('OPTIONS con token de admin también -> 404', async () => {
    const res = await request(app.server)
      .options(`${API_PREFIX}/admin/metrics/guards/${guardiaId}`)
      .set('Authorization', `Bearer ${adminToken}`);
    expect(res.status).toBe(404);
  });
});

describe('recorrido de rutas registradas', () => {
  const sinHead = () =>
    registro.filter((r) => r.url.startsWith(`${API_PREFIX}/`) && r.metodo !== 'HEAD');

  it('el conjunto de rutas registradas (auth + stubs) es EXACTAMENTE ROUTE_POLICIES', () => {
    const claves = sinHead().map((r) => `${r.metodo} ${r.url.slice(API_PREFIX.length)}`);
    expect(new Set(claves).size).toBe(claves.length);
    expect([...claves].sort()).toEqual(Object.keys(ROUTE_POLICIES).sort());
    // 36 de BE-01 + GET /alerts/:id/photo (BE-03, D30) + PUT /users/me/device-token (BE-04, D42).
    expect(claves).toHaveLength(38);
  });

  it('solo /health queda fuera del prefijo', () => {
    const fuera = registro.filter((r) => !r.url.startsWith(`${API_PREFIX}/`) && r.metodo !== 'HEAD');
    expect(fuera.map((r) => `${r.metodo} ${r.url}`)).toEqual(['GET /health']);
  });

  it('cada ruta con roles tiene authenticate como PRIMER hook onRequest y luego el de rol', async () => {
    const conRoles = sinHead().filter((r) => {
      const p = ROUTE_POLICIES[`${r.metodo} ${r.url.slice(API_PREFIX.length)}`];
      return typeof p !== 'string' && p !== undefined;
    });
    expect(conRoles.length).toBe(
      Object.values(ROUTE_POLICIES).filter((p) => typeof p !== 'string').length,
    );

    const original = app.authenticate;
    let llamadas = 0;
    // authenticate se resuelve al ejecutar el hook; se sustituye por un espía.
    (app as { authenticate: unknown }).authenticate = async () => {
      llamadas += 1;
    };
    try {
      for (const r of conRoles) {
        const clave = `${r.metodo} ${r.url.slice(API_PREFIX.length)}`;
        expect(r.onRequest.length, clave).toBeGreaterThanOrEqual(2);
        const [primero, segundo] = r.onRequest as Array<(req: unknown) => Promise<void>>;
        const antes = llamadas;
        await primero!({});
        expect(llamadas, `${clave}: el primer hook debe ser authenticate`).toBe(antes + 1);
        // El segundo es el de rol: sin request.user es 401.
        await expect(segundo!({}), clave).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      }
    } finally {
      (app as { authenticate: unknown }).authenticate = original;
    }
  });

  it('las rutas public y custom no llevan hooks de authenticate/rol', () => {
    const libres = sinHead().filter((r) => {
      const p = ROUTE_POLICIES[`${r.metodo} ${r.url.slice(API_PREFIX.length)}`];
      return typeof p === 'string';
    });
    expect(libres.map((r) => `${r.metodo} ${r.url.slice(API_PREFIX.length)}`).sort()).toEqual([
      'GET /alerts/:id/photo',
      'POST /auth/login',
      'POST /auth/refresh',
      'POST /auth/register',
      'POST /auth/session',
    ]);
    for (const r of libres) expect(r.onRequest, r.url).toEqual([]);
  });
});
