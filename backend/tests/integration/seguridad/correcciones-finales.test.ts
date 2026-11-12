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

const REALES = new Set([
  'POST /auth/login',
  'POST /auth/refresh',
  'POST /auth/logout',
  'GET /auth/me',
  'POST /auth/session',
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
let ejecuciones = 0;
const registro: Registro[] = [];

const GUARD_EMAIL = 'final-guardia@prueba.test';

beforeAll(async () => {
  db = await abrirDb();
  const passwordHash = await hasherPrueba.hash(PASSWORD);
  await db.prisma.user.create({
    data: {
      name: 'Final guardia',
      email: GUARD_EMAIL,
      phone: '7771234567',
      passwordHash,
      role: 'guard',
    },
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
          handler: async () => {
            if (clave === 'GET /guard/me') ejecuciones += 1;
            return ok({ ruta: clave });
          },
        });
      }
    },
    { prefix: API_PREFIX },
  );
  await app.ready();
  const res = await login(app, GUARD_EMAIL);
  guardToken = res.body.data.accessToken as string;
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

describe('normalización de rutas: nada de lo que parezca /api/v1/guard/me llega al handler', () => {
  const variantes = [
    '/API/V1/guard/me',
    '/api/v1//guard/me',
    '/api/v1/guard/me/',
    '/api/v1/guard%2Fme',
    '/api/v1/GUARD/me',
    '/api/v1/guard/me/%2e',
    '/api/v1/./guard/me',
  ];

  it.each(variantes)('GET %s con token de guard -> 404 y el stub no se ejecuta', async (ruta) => {
    const antes = ejecuciones;
    const res = await request(app.server).get(ruta).set('Authorization', `Bearer ${guardToken}`);
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(ejecuciones).toBe(antes);
  });

  it('control: la ruta exacta sí ejecuta el stub', async () => {
    const antes = ejecuciones;
    const res = await request(app.server)
      .get(`${API_PREFIX}/guard/me`)
      .set('Authorization', `Bearer ${guardToken}`);
    expect(res.status).toBe(200);
    expect(ejecuciones).toBe(antes + 1);
  });

  it('OPTIONS anónimo sobre una ruta con roles -> 404 (nunca 200)', async () => {
    const antes = ejecuciones;
    const res = await request(app.server).options(`${API_PREFIX}/guard/me`);
    expect(res.status).toBe(404);
    expect(ejecuciones).toBe(antes);
  });

  it('OPTIONS con token de guard también -> 404', async () => {
    const res = await request(app.server)
      .options(`${API_PREFIX}/guard/me`)
      .set('Authorization', `Bearer ${guardToken}`);
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
    expect(claves).toHaveLength(36);
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
      'POST /auth/login',
      'POST /auth/refresh',
      'POST /auth/register',
      'POST /auth/session',
    ]);
    for (const r of libres) expect(r.onRequest, r.url).toEqual([]);
  });
});
