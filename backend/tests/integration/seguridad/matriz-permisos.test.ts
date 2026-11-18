// BE-01 paso 6: matriz de permisos rol x ruta contra PostgreSQL real y el mecanismo deny-by-default
// de buildApp. Las rutas que aún no existen (las que no están en REALES) se registran como stubs
// dentro de /api/v1 ANTES de ready(); así la matriz se ejecuta contra los hooks reales
// (authenticate + requireRole) y no contra una copia.
import type { FastifyInstance } from 'fastify';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { API_PREFIX, buildApp } from '../../../src/app.js';
import { ok } from '../../../src/http/envelope.js';
import type { Role } from '../../../src/generated/prisma/enums.js';
import { ROUTE_POLICIES, type RoutePolicy } from '../../../src/security/policies.js';
import {
  MSG_UNAUTHORIZED,
  PASSWORD,
  configPrueba,
  hasherPrueba,
  login,
} from '../auth/helpers.js';
import { abrirDb, type ContextoDb } from '../db/helpers.js';
import { abrirSse } from '../sse-helpers.js';

const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const UUID_RUTA = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
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
]);
const ROLES: readonly Role[] = ['protected_user', 'guard', 'admin'];

/**
 * La petición pasó el control de acceso y llegó al manejador. No se exige 2xx:
 * una ruta ya implementada puede responder 400 o 404 ante un cuerpo o un id de
 * relleno, y eso no dice nada del permiso. Lo que importa aquí es que no la
 * frenaron por falta de token (401) ni por rol (403).
 */
function esperarQueLlegue(res: { status: number; body: unknown }): void {
  expect(res.status, JSON.stringify(res.body)).not.toBe(401);
  expect(res.status, JSON.stringify(res.body)).not.toBe(403);
}

const entradas = Object.entries(ROUTE_POLICIES) as Array<[string, RoutePolicy]>;
const conRoles = entradas.filter(([, p]) => typeof p !== 'string') as Array<[string, readonly Role[]]>;

function partir(clave: string): { metodo: string; url: string } {
  const [metodo, ruta] = clave.split(' ') as [string, string];
  return { metodo, url: `${API_PREFIX}${ruta.replace(':id', UUID_RUTA)}` };
}

type Metodo = 'get' | 'post' | 'put' | 'patch' | 'delete' | 'head';

/**
 * Un canal SSE real no termina: se lee su primer evento (o su error JSON previo) y se corta.
 * Los canales que aún son stub responden JSON normal: se usa ese cuerpo.
 */
async function enviarSse(app: FastifyInstance, url: string, token?: string) {
  const c = await abrirSse(app, url, token);
  const esStream = (c.headers['content-type'] ?? '').startsWith('text/event-stream');
  const body = esStream ? await c.siguiente() : c.json;
  c.cerrar();
  return { status: c.status, headers: c.headers, body };
}

function enviar(app: FastifyInstance, metodo: string, url: string, token?: string, cuerpo?: object) {
  if (metodo === 'GET' && url.startsWith(`${API_PREFIX}/events/`)) return enviarSse(app, url, token);
  let r = request(app.server)[metodo.toLowerCase() as Metodo](url);
  if (token !== undefined) r = r.set('Authorization', `Bearer ${token}`);
  if (['POST', 'PUT', 'PATCH'].includes(metodo)) r = r.send(cuerpo ?? {});
  return r;
}

let db: ContextoDb;
let app: FastifyInstance;
const ids: Record<Role | 'inactivo' | 'promovible', string> = {
  protected_user: '',
  guard: '',
  admin: '',
  inactivo: '',
  promovible: '',
};
const emails: Record<Role | 'inactivo' | 'promovible', string> = {
  protected_user: 'matriz-usuario@prueba.test',
  guard: 'matriz-guardia@prueba.test',
  admin: 'matriz-admin@prueba.test',
  inactivo: 'matriz-inactivo@prueba.test',
  promovible: 'matriz-promovible@prueba.test',
};
const tokens = {} as Record<Role, string>;

async function tokenDe(email: string): Promise<string> {
  const res = await login(app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
}

beforeAll(async () => {
  db = await abrirDb();
  const passwordHash = await hasherPrueba.hash(PASSWORD);
  const crear = async (clave: keyof typeof ids, role: Role) => {
    const u = await db.prisma.user.create({
      data: {
        name: `Matriz ${clave}`,
        email: emails[clave],
        phone: '7771234567',
        passwordHash,
        role,
      },
    });
    ids[clave] = u.id;
  };
  await crear('protected_user', 'protected_user');
  await crear('guard', 'guard');
  await crear('admin', 'admin');
  await crear('inactivo', 'protected_user');
  await crear('promovible', 'protected_user');
  // GET /guard/me es real desde BE-04: sin perfil de guardia responde 404, así que estos dos lo tienen.
  for (const clave of ['guard', 'promovible'] as const) {
    await db.prisma.guardProfile.create({ data: { userId: ids[clave], shiftStart: '00:00', shiftEnd: '00:00' } });
  }

  app = buildApp(configPrueba(), { prisma: db.prisma });
  // Stubs para todas las rutas de la política que aún no se implementan.
  void app.register(
    async (api) => {
      for (const [clave] of entradas) {
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
  for (const r of ROLES) tokens[r] = await tokenDe(emails[r]);
}, 120_000);

afterAll(async () => {
  await app.close();
  await db.cerrar();
});

describe('matriz de permisos: cubre todas las rutas de la política', () => {
  // Los conteos salen de REALES, no de un número escrito a mano: así la prueba
  // no se rompe cada vez que una tarjeta implementa rutas nuevas.
  it('cada ruta de la política está cubierta: las implementadas de verdad y el resto con stubs', () => {
    expect(entradas).toHaveLength(Object.keys(ROUTE_POLICIES).length);
    // Si REALES tuviera una clave que no existe en la política, este conteo baja.
    expect(entradas.filter(([k]) => REALES.has(k))).toHaveLength(REALES.size);
    expect(entradas.filter(([k]) => !REALES.has(k))).toHaveLength(entradas.length - REALES.size);
  });
});

describe('anónimo en rutas con roles -> 401 UNAUTHORIZED (U-01, deny-by-default)', () => {
  it.each(conRoles.map(([k]) => k))('%s', async (clave) => {
    const { metodo, url } = partir(clave);
    const res = await enviar(app, metodo, url);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it.each(['Bearer', 'Bearer ', 'Basic abc', 'Bearer a.b.c', 'bearer x'])(
    'Authorization "%s" no autentica (GET /guard/me)',
    async (cabecera) => {
      const res = await request(app.server).get(`${API_PREFIX}/guard/me`).set('Authorization', cabecera);
      expect(res.status).toBe(401);
      expect(res.body.error.code).toBe('UNAUTHORIZED');
    },
  );
});

describe('rol x ruta: 2xx si está permitido, 403 FORBIDDEN si no', () => {
  const casos: Array<[string, Role, boolean]> = [];
  for (const [clave, roles] of conRoles) {
    for (const rol of ROLES) casos.push([clave, rol, roles.includes(rol)]);
  }

  it('la matriz contiene rutas con roles x 3 roles, con casos permitidos y rechazados', () => {
    expect(casos).toHaveLength(conRoles.length * 3);
    expect(casos.filter(([, , permitido]) => permitido).length).toBeGreaterThan(0);
    expect(casos.filter(([, , permitido]) => !permitido).length).toBeGreaterThan(0);
  });

  it.each(casos)('%s con %s (permitido: %s)', async (clave, rol, permitido) => {
    const { metodo, url } = partir(clave);
    // logout revoca la sesión: se usa un token propio para no invalidar el compartido.
    const token = clave === 'POST /auth/logout' ? await tokenDe(emails[rol]) : tokens[rol];
    const res = await enviar(app, metodo, url, token);
    if (permitido) {
      esperarQueLlegue(res);
    } else {
      expect(res.status).toBe(403);
      expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    }
  });

  it('los stubs permitidos responden el envoltorio { data: { ruta } }', async () => {
    // GET /admin/metrics es BE-05 (aún stub): conserva la aserción del envoltorio de un stub permitido.
    const res = await enviar(app, 'GET', `${API_PREFIX}/admin/metrics`, tokens.admin);
    expect(res.body).toEqual({ data: { ruta: 'GET /admin/metrics' } });
  });

  it('cada ruta restringida tiene al menos un rol permitido y un rol rechazado salvo las de ALL_ROLES', () => {
    for (const [clave, roles] of conRoles) {
      expect(roles.length, clave).toBeGreaterThan(0);
      if (roles.length < 3) expect(ROLES.some((r) => !roles.includes(r)), clave).toBe(true);
    }
  });
});

describe('rutas public: anónimo no recibe 401 ni 403', () => {
  it('POST /auth/login sin cuerpo válido -> 400 (llega a la ruta)', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/login`);
    expect(res.status).toBe(400);
  });

  it('POST /auth/refresh con token inventado responde por su propia lógica (401 de refresh, no del guard)', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/refresh`, undefined, {
      refreshToken: 'a'.repeat(43),
    });
    // Es el 401 de la lógica de refresh; lo relevante es que la ruta se alcanza (pasa del guard).
    expect([400, 401]).toContain(res.status);
    expect(res.body.error.code === 'UNAUTHORIZED' || res.body.error.code === 'INVALID_STATE').toBe(true);
  });

  it('POST /auth/register anónimo llega a la ruta (sin cuerpo válido responde 400)', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/register`);
    esperarQueLlegue(res);
  });

  it.each(ROLES)('POST /auth/register también acepta a un token de %s (no restringe por rol)', async (rol) => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/register`, tokens[rol]);
    esperarQueLlegue(res);
  });

  it('GET /alerts/:id/photo anónimo llega a la ruta: sin firma válida responde 404, no 401', async () => {
    const res = await enviar(app, 'GET', `${API_PREFIX}/alerts/${UUID_RUTA}/photo`);
    esperarQueLlegue(res);
    expect(res.status).toBe(404);
  });

  it('las rutas public no exigen token ni siquiera con uno basura', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/register`, 'basura.basura.basura');
    esperarQueLlegue(res);
  });
});

describe('ruta custom POST /auth/session: su propia lógica (D7, D25)', () => {
  it('anónimo -> 401', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/session`, undefined, {
      userId: ids.protected_user,
    });
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  it.each(ROLES)('rol %s con su propio userId -> 200 con su usuario (sin 403 por rol)', async (rol) => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/session`, tokens[rol], {
      userId: ids[rol],
    });
    expect(res.status).toBe(200);
    expect(res.body.data.id).toBe(ids[rol]);
    expect(res.body.data.role).toBe(rol);
  });

  it('userId ajeno -> 200 con data null (no 403 ni filtración)', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/session`, tokens.protected_user, {
      userId: ids.admin,
    });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
  });
});

describe('el 401/403 llega ANTES de validar el cuerpo', () => {
  it('rol incorrecto con cuerpo inválido (campos extra) -> 403, no 400', async () => {
    const res = await request(app.server)
      .post(`${API_PREFIX}/admin/guards`)
      .set('Authorization', `Bearer ${tokens.guard}`)
      .send({ campo: 'basura', role: 'admin' });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });

  it('rol incorrecto con JSON malformado -> 403, no 400', async () => {
    const res = await request(app.server)
      .post(`${API_PREFIX}/admin/guards`)
      .set('Authorization', `Bearer ${tokens.protected_user}`)
      .set('content-type', 'application/json')
      .send('{"a": ');
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });

  it('anónimo con JSON malformado en ruta con roles -> 401, no 400', async () => {
    const res = await request(app.server)
      .post(`${API_PREFIX}/guard/alerts/${UUID_RUTA}/accept`)
      .set('content-type', 'application/json')
      .send('{"a": ');
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });

  it('rol incorrecto con content-type no soportado -> 403, no 400', async () => {
    const res = await request(app.server)
      .post(`${API_PREFIX}/alerts`)
      .set('Authorization', `Bearer ${tokens.admin}`)
      .set('content-type', 'application/x-evil')
      .send('abc');
    expect(res.status).toBe(403);
  });

  it('rol incorrecto con cuerpo de __proto__ -> 403, no 400', async () => {
    const res = await request(app.server)
      .put(`${API_PREFIX}/guard/location`)
      .set('Authorization', `Bearer ${tokens.admin}`)
      .set('content-type', 'application/json')
      .send('{"__proto__":{"x":1}}');
    expect(res.status).toBe(403);
  });

  it('en cambio, un rol correcto con JSON malformado SÍ llega al parser -> 400', async () => {
    const res = await request(app.server)
      .post(`${API_PREFIX}/admin/guards`)
      .set('Authorization', `Bearer ${tokens.admin}`)
      .set('content-type', 'application/json')
      .send('{"a": ');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });

  it('id con formato inválido en la URL y rol incorrecto -> 403, no 404', async () => {
    const res = await request(app.server)
      .get(`${API_PREFIX}/admin/guards/no-es-uuid`)
      .set('Authorization', `Bearer ${tokens.guard}`);
    expect(res.status).toBe(403);
  });
});

describe('HEAD hereda la política de GET', () => {
  it('HEAD /guard/me anónimo -> 401', async () => {
    expect((await enviar(app, 'HEAD', `${API_PREFIX}/guard/me`)).status).toBe(401);
  });
  it('HEAD /guard/me con rol incorrecto -> 403', async () => {
    expect((await enviar(app, 'HEAD', `${API_PREFIX}/guard/me`, tokens.admin)).status).toBe(403);
  });
  it('HEAD /guard/me con guard -> 200', async () => {
    expect((await enviar(app, 'HEAD', `${API_PREFIX}/guard/me`, tokens.guard)).status).toBe(200);
  });
});

describe('rutas inexistentes bajo el prefijo y métodos no declarados', () => {
  it('GET /api/v1/no-existe -> 404 NOT_FOUND (con o sin token)', async () => {
    const anon = await request(app.server).get(`${API_PREFIX}/no-existe`);
    expect(anon.status).toBe(404);
    expect(anon.body.error.code).toBe('NOT_FOUND');
    const conToken = await enviar(app, 'GET', `${API_PREFIX}/no-existe`, tokens.admin);
    expect(conToken.status).toBe(404);
  });

  it('método no declarado en una ruta existente (DELETE /guard/me) -> 404, nunca 200', async () => {
    const res = await enviar(app, 'DELETE', `${API_PREFIX}/guard/me`, tokens.guard);
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('las respuestas de la API no se cachean (cache-control: no-store) también en 401 y 403', async () => {
    const r401 = await request(app.server).get(`${API_PREFIX}/guard/me`);
    const r403 = await enviar(app, 'GET', `${API_PREFIX}/guard/me`, tokens.admin);
    expect(r401.headers['cache-control']).toBe('no-store');
    expect(r403.headers['cache-control']).toBe('no-store');
  });
});

describe('token de usuario desactivado -> 401 en cualquier ruta con roles', () => {
  let tokenInactivo = '';

  beforeAll(async () => {
    tokenInactivo = await tokenDe(emails.inactivo);
    // Con el token ya emitido, se desactiva al usuario.
    await db.prisma.user.update({ where: { id: ids.inactivo }, data: { isActive: false } });
  });

  it.each(conRoles.map(([k]) => k))('%s', async (clave) => {
    const { metodo, url } = partir(clave);
    const res = await enviar(app, metodo, url, tokenInactivo);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it('también en la ruta custom POST /auth/session el usuario desactivado recibe data null o 401, nunca sus datos', async () => {
    const res = await enviar(app, 'POST', `${API_PREFIX}/auth/session`, tokenInactivo, {
      userId: ids.inactivo,
    });
    expect([200, 401]).toContain(res.status);
    if (res.status === 200) expect(res.body).toEqual({ data: null });
  });
});

describe('el rol sale de la BD, no del token', () => {
  it('un protected_user promovido a guard accede a /guard/me y ya no a /alerts/mine', async () => {
    const token = await tokenDe(emails.promovible);

    const antesGuard = await enviar(app, 'GET', `${API_PREFIX}/guard/me`, token);
    expect(antesGuard.status).toBe(403);
    const antesUsuario = await enviar(app, 'GET', `${API_PREFIX}/alerts/mine`, token);
    expect(antesUsuario.status).toBe(200);

    await db.prisma.user.update({ where: { id: ids.promovible }, data: { role: 'guard' } });

    const despuesGuard = await enviar(app, 'GET', `${API_PREFIX}/guard/me`, token);
    expect(despuesGuard.status).toBe(200);
    const despuesUsuario = await enviar(app, 'GET', `${API_PREFIX}/alerts/mine`, token);
    expect(despuesUsuario.status).toBe(403);
    expect(despuesUsuario.body.error.code).toBe('FORBIDDEN');

    // /auth/me (ruta real) refleja el rol de la BD.
    const yo = await enviar(app, 'GET', `${API_PREFIX}/auth/me`, token);
    expect(yo.status).toBe(200);
    expect(yo.body.data.role).toBe('guard');
  });

  it('degradar a un admin lo deja sin acceso a /admin/* con su token vigente', async () => {
    const token = await tokenDe(emails.promovible);
    await db.prisma.user.update({ where: { id: ids.promovible }, data: { role: 'admin' } });
    expect((await enviar(app, 'GET', `${API_PREFIX}/admin/guards`, token)).status).toBe(200);
    await db.prisma.user.update({ where: { id: ids.promovible }, data: { role: 'protected_user' } });
    expect((await enviar(app, 'GET', `${API_PREFIX}/admin/guards`, token)).status).toBe(403);
  });
});

describe('sesión revocada', () => {
  it('tras POST /auth/logout el mismo access token ya no entra a rutas con roles (401)', async () => {
    const token = await tokenDe(emails.guard);
    expect((await enviar(app, 'GET', `${API_PREFIX}/guard/me`, token)).status).toBe(200);
    expect((await enviar(app, 'POST', `${API_PREFIX}/auth/logout`, token)).status).toBe(200);
    const res = await enviar(app, 'GET', `${API_PREFIX}/guard/me`, token);
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
  });
});
