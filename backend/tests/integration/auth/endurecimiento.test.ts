// BE-01 paso 5 (correcciones del checkpoint): carreras, gracia, vida máxima, rate limit,
// JWT endurecido, rehash, respuestas indistinguibles y cabeceras de caché.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { crearAppAislada } from '../app-aislada.js';
import {
  createTokenFamily,
  hashRefreshToken,
  revokeAllUserFamilies,
  rotateRefreshToken,
} from '../../../src/auth/tokens.js';
import { loadConfig } from '../../../src/config/env.js';
import {
  ARGON2_PRUEBA,
  JWT_SECRET,
  MSG_UNAUTHORIZED,
  PASSWORD,
  configPrueba,
  crearEntorno,
  decodificar,
  firmarHmac,
  forjarJwt,
  hasherPrueba,
  login,
  logout,
  me,
  refresh,
  session,
  type Entorno,
} from './helpers.js';

const ERROR_401 = { error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } };
const MSG_429 = 'Demasiados intentos. Espera un momento e intenta de nuevo.';

let env: Entorno;

beforeAll(async () => {
  env = await crearEntorno();
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});
beforeEach(async () => {
  await env.prisma.refreshToken.deleteMany();
});

interface Sesion {
  access: string;
  refresh: string;
  sid: string;
}
async function iniciar(email = env.usuarios.protegido.email): Promise<Sesion> {
  const res = await login(env.app, email);
  const access = res.body.data.accessToken as string;
  return {
    access,
    refresh: res.body.data.refreshToken as string,
    sid: decodificar(access).payload['sid'] as string,
  };
}
const filasDe = (sid: string) =>
  env.prisma.refreshToken.findMany({ where: { familyId: sid }, orderBy: { createdAt: 'asc' } });
const ahora = () => Math.floor(Date.now() / 1000);
const claims = (sub: string, role: string, sid: string) => ({
  sub,
  role,
  sid,
  iat: ahora(),
  exp: ahora() + 900,
});

describe('carreras refresh / logout / revocación (cierre de la ventana de resurrección)', () => {
  it('Promise.all([refresh, logout]) x25: ninguna fila sin revocar y nada nuevo sirve', async () => {
    for (let i = 0; i < 25; i += 1) {
      const s = await iniciar();
      const [r, l] = await Promise.all([refresh(env.app, s.refresh), logout(env.app, s.access)]);
      expect(l.status).toBe(200);
      expect([200, 401]).toContain(r.status);
      const filas = await filasDe(s.sid);
      expect(filas.length).toBeGreaterThanOrEqual(1);
      expect(filas.every((f) => f.revokedAt !== null)).toBe(true);
      if (r.status === 200) {
        expect((await me(env.app, r.body.data.accessToken as string)).status).toBe(401);
        expect((await refresh(env.app, r.body.data.refreshToken as string)).status).toBe(401);
      }
      expect((await me(env.app, s.access)).status).toBe(401);
    }
  }, 60_000);

  it('refresh concurrente con detección de reutilización x10: la familia termina revocada', async () => {
    for (let i = 0; i < 10; i += 1) {
      const s = await iniciar();
      const rot = await refresh(env.app, s.refresh);
      expect(rot.status).toBe(200);
      // El viejo queda fuera de la gracia: reutilizarlo es un robo.
      await env.prisma.refreshToken.updateMany({
        where: { tokenHash: hashRefreshToken(s.refresh) },
        data: { usedAt: new Date(Date.now() - 3_600_000) },
      });
      const [a, b] = await Promise.all([
        refresh(env.app, s.refresh),
        refresh(env.app, rot.body.data.refreshToken as string),
      ]);
      expect(a.status).toBe(401);
      expect([200, 401]).toContain(b.status);
      const filas = await filasDe(s.sid);
      expect(filas.every((f) => f.revokedAt !== null)).toBe(true);
      expect((await me(env.app, rot.body.data.accessToken as string)).status).toBe(401);
      if (b.status === 200) {
        expect((await me(env.app, b.body.data.accessToken as string)).status).toBe(401);
        expect((await refresh(env.app, b.body.data.refreshToken as string)).status).toBe(401);
      }
    }
  });

  it('dos reutilizaciones simultáneas del viejo (fuera de gracia): ambas 401 y familia revocada', async () => {
    const s = await iniciar();
    await refresh(env.app, s.refresh);
    await env.prisma.refreshToken.updateMany({
      where: { tokenHash: hashRefreshToken(s.refresh) },
      data: { usedAt: new Date(Date.now() - 3_600_000) },
    });
    const [a, b] = await Promise.all([refresh(env.app, s.refresh), refresh(env.app, s.refresh)]);
    expect([a.status, b.status]).toEqual([401, 401]);
    expect((await filasDe(s.sid)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('refresh concurrente con revokeAllUserFamilies x20: sin filas vivas y nada nuevo sirve', async () => {
    for (let i = 0; i < 20; i += 1) {
      await env.prisma.refreshToken.deleteMany();
      const a = await iniciar();
      const b = await iniciar();
      const [r] = await Promise.all([
        refresh(env.app, a.refresh),
        revokeAllUserFamilies(env.prisma, env.usuarios.protegido.id),
      ]);
      expect([200, 401]).toContain(r.status);
      const vivas = await env.prisma.refreshToken.count({
        where: { userId: env.usuarios.protegido.id, revokedAt: null },
      });
      expect(vivas).toBe(0);
      if (r.status === 200) {
        expect((await me(env.app, r.body.data.accessToken as string)).status).toBe(401);
        expect((await refresh(env.app, r.body.data.refreshToken as string)).status).toBe(401);
      }
      expect((await me(env.app, b.access)).status).toBe(401);
      expect((await refresh(env.app, b.refresh)).status).toBe(401);
    }
  }, 60_000);
});

describe('gracia: el hermano queda revocado cuando la otra rama rota', () => {
  it('rota la rama original: el hermano de gracia queda revocado y el sucesor sirve', async () => {
    const s = await iniciar();
    const a = await refresh(env.app, s.refresh);
    const b = await refresh(env.app, s.refresh); // gracia
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    const sucesorA = await refresh(env.app, a.body.data.refreshToken as string);
    expect(sucesorA.status).toBe(200);
    const hermano = (await filasDe(s.sid)).find(
      (f) => f.tokenHash === hashRefreshToken(b.body.data.refreshToken as string),
    );
    expect(hermano?.revokedAt).not.toBeNull();
    // El cliente legítimo descartó al hermano: presentarlo después es reutilización (D25) y
    // revoca toda la familia, incluido el sucesor vigente.
    const rb = await refresh(env.app, b.body.data.refreshToken as string);
    expect(rb.status).toBe(401);
    expect((await refresh(env.app, sucesorA.body.data.refreshToken as string)).status).toBe(401);
    expect((await filasDe(s.sid)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('sin presentar al hermano descartado, el sucesor de la rama elegida sigue sirviendo', async () => {
    const s = await iniciar();
    const a = await refresh(env.app, s.refresh);
    const b = await refresh(env.app, s.refresh); // gracia
    expect(b.status).toBe(200);
    const sucesorA = await refresh(env.app, a.body.data.refreshToken as string);
    expect(sucesorA.status).toBe(200);
    expect((await refresh(env.app, sucesorA.body.data.refreshToken as string)).status).toBe(200);
  });

  it('rota la rama de gracia: la original queda revocada', async () => {
    const s = await iniciar();
    const a = await refresh(env.app, s.refresh);
    const b = await refresh(env.app, s.refresh);
    const sucesorB = await refresh(env.app, b.body.data.refreshToken as string);
    expect(sucesorB.status).toBe(200);
    const original = (await filasDe(s.sid)).find(
      (f) => f.tokenHash === hashRefreshToken(a.body.data.refreshToken as string),
    );
    expect(original?.revokedAt).not.toBeNull();
    // Presentar la rama descartada es reutilización: revoca la familia.
    expect((await refresh(env.app, a.body.data.refreshToken as string)).status).toBe(401);
    expect((await refresh(env.app, sucesorB.body.data.refreshToken as string)).status).toBe(401);
  });

  it('el default es 5 s (borde 5 inclusivo, 6 revoca) con reloj inyectado', async () => {
    expect(configPrueba().REFRESH_GRACE_SECONDS).toBe(5);
    expect(loadConfig({ JWT_SECRET }).REFRESH_GRACE_SECONDS).toBe(5);
    const base = new Date('2026-03-01T00:00:00.000Z');
    const opts = {
      ttlSeconds: 86_400,
      maxAgeSeconds: 7_776_000,
      graceSeconds: configPrueba().REFRESH_GRACE_SECONDS,
    };
    const en = (n: number) => new Date(base.getTime() + n * 1000);
    const t1 = await createTokenFamily(env.prisma, env.usuarios.protegido.id, opts, base);
    await rotateRefreshToken(env.prisma, t1.token, opts, base);
    expect((await rotateRefreshToken(env.prisma, t1.token, opts, en(5))).ok).toBe(true);
    const t2 = await createTokenFamily(env.prisma, env.usuarios.protegido.id, opts, base);
    await rotateRefreshToken(env.prisma, t2.token, opts, base);
    expect((await rotateRefreshToken(env.prisma, t2.token, opts, en(6))).ok).toBe(false);
    expect((await filasDe(t2.familyId)).every((f) => f.revokedAt !== null)).toBe(true);
  });
});

describe('vida máxima de la sesión (JWT_SESSION_MAX_AGE)', () => {
  const BASE = new Date('2026-01-01T00:00:00.000Z');
  const DIA = 86_400_000;
  const opts = { ttlSeconds: 30 * 86_400, maxAgeSeconds: 90 * 86_400, graceSeconds: 0 };
  const dia = (n: number) => new Date(BASE.getTime() + n * DIA);

  it('una familia refrescada continuamente vence en family_started_at + 90 d, sin revocar', async () => {
    const t0 = await createTokenFamily(env.prisma, env.usuarios.protegido.id, opts, BASE);
    let token = t0.token;
    for (const d of [20, 40, 60, 80]) {
      const r = await rotateRefreshToken(env.prisma, token, opts, dia(d));
      expect(r.ok).toBe(true);
      if (r.ok) token = r.token;
    }
    const filas = await filasDe(t0.familyId);
    // family_started_at se hereda del padre en toda la cadena.
    for (const f of filas) expect(f.familyStartedAt.toISOString()).toBe(BASE.toISOString());
    // El último token (creado el día 80) vence el día 90, no el 110.
    const ultimo = filas.find((f) => f.tokenHash === hashRefreshToken(token));
    expect(ultimo?.expiresAt.toISOString()).toBe(dia(90).toISOString());
    // Los anteriores respetan ttl (día 20 + 30 = 50).
    expect(filas[0]?.expiresAt.toISOString()).toBe(dia(30).toISOString());
    expect(filas[1]?.expiresAt.toISOString()).toBe(dia(50).toISOString());

    expect((await rotateRefreshToken(env.prisma, token, opts, dia(90))).ok).toBe(false);
    expect((await filasDe(t0.familyId)).every((f) => f.revokedAt === null)).toBe(true);
  });

  it('un día antes del límite todavía rota y el sucesor ya nace con el límite de la sesión', async () => {
    const t0 = await createTokenFamily(env.prisma, env.usuarios.protegido.id, opts, BASE);
    let token = t0.token;
    for (const d of [29, 58, 87, 89]) {
      const r = await rotateRefreshToken(env.prisma, token, opts, dia(d));
      expect(r.ok).toBe(true);
      if (r.ok) token = r.token;
    }
    const filas = await filasDe(t0.familyId);
    expect(filas.at(-1)?.expiresAt.toISOString()).toBe(dia(90).toISOString());
    expect((await rotateRefreshToken(env.prisma, token, opts, dia(90))).ok).toBe(false);
  });

  it('el primer token de la familia guarda family_started_at = su creación', async () => {
    const t0 = await createTokenFamily(env.prisma, env.usuarios.protegido.id, opts, BASE);
    const [fila] = await filasDe(t0.familyId);
    expect(fila?.familyStartedAt.toISOString()).toBe(BASE.toISOString());
    expect(fila?.parentId).toBeNull();
  });

  it('por HTTP el sucesor hereda family_started_at del login', async () => {
    const s = await iniciar();
    const r = await refresh(env.app, s.refresh);
    expect(r.status).toBe(200);
    const filas = await filasDe(s.sid);
    expect(filas).toHaveLength(2);
    expect(filas[1]?.familyStartedAt.toISOString()).toBe(filas[0]?.familyStartedAt.toISOString());
  });
});

describe('rate limit (429)', () => {
  it('login: el intento 11 de la misma IP da 429 TOO_MANY_REQUESTS; cuentan todos los intentos', async () => {
    const app = buildApp(configPrueba({ RATE_LIMIT_LOGIN_MAX: '10', RATE_LIMIT_LOGIN_WINDOW: '1m' }), {
      prisma: env.prisma,
    });
    await app.ready();
    try {
      for (let i = 0; i < 10; i += 1) {
        const r = await login(app, env.usuarios.protegido.email, i % 2 === 0 ? 'mala' : PASSWORD);
        expect([200, 401]).toContain(r.status);
      }
      const res = await login(app, env.usuarios.protegido.email);
      expect(res.status).toBe(429);
      expect(res.body).toEqual({ error: { code: 'TOO_MANY_REQUESTS', message: MSG_429 } });
      expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
      expect(Object.keys(res.headers).filter((h) => h.startsWith('x-ratelimit'))).toEqual([]);
      expect(res.headers['cache-control']).toBe('no-store');
      // Un intento limitado no inicia sesión aunque la contraseña sea correcta.
      expect(res.text).not.toContain('accessToken');
      // /health no está limitado.
      for (let i = 0; i < 40; i += 1) expect((await request(app.server).get('/health')).status).toBe(200);
      // Las rutas sin límite declarado siguen respondiendo.
      expect((await me(app, 'x')).status).toBe(401);
    } finally {
      await app.close();
    }
  });

  it('las respuestas bajo el límite no llevan cabeceras X-RateLimit-*', async () => {
    const app = buildApp(configPrueba({ RATE_LIMIT_LOGIN_MAX: '10' }), { prisma: env.prisma });
    await app.ready();
    try {
      const res = await login(app, env.usuarios.protegido.email);
      expect(res.status).toBe(200);
      expect(Object.keys(res.headers).filter((h) => h.startsWith('x-ratelimit'))).toEqual([]);
    } finally {
      await app.close();
    }
  });

  it('refresh: la petición 31 da 429; el contador de login es independiente', async () => {
    const app = buildApp(configPrueba({ RATE_LIMIT_REFRESH_MAX: '30', RATE_LIMIT_LOGIN_MAX: '10' }), {
      prisma: env.prisma,
    });
    await app.ready();
    try {
      const falso = 'a'.repeat(43);
      for (let i = 0; i < 30; i += 1) expect((await refresh(app, falso)).status).toBe(401);
      const res = await refresh(app, falso);
      expect(res.status).toBe(429);
      expect(res.body).toEqual({ error: { code: 'TOO_MANY_REQUESTS', message: MSG_429 } });
      expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
      expect(res.headers['cache-control']).toBe('no-store');
      expect((await login(app, env.usuarios.protegido.email)).status).toBe(200);
    } finally {
      await app.close();
    }
  });

  it('un 429 lanzado desde otro origen se traduce a TOO_MANY_REQUESTS (no 500)', async () => {
    // Instancia propia sin deny-by-default (buildApp aborta con rutas sin política central).
    const app = crearAppAislada(configPrueba(), (a) => {
      a.get('/boom429', () => {
        throw Object.assign(new Error('Rate limit exceeded, retry in 1 minute'), { statusCode: 429 });
      });
    });
    await app.ready();
    try {
      const res = await request(app.server).get('/boom429');
      expect(res.status).toBe(429);
      expect(res.body).toEqual({ error: { code: 'TOO_MANY_REQUESTS', message: MSG_429 } });
      expect(res.text).not.toContain('Rate limit exceeded');
    } finally {
      await app.close();
    }
  });
});

describe('JWT endurecido', () => {
  let sid: string;
  beforeEach(async () => {
    sid = (await iniciar(env.usuarios.guardia.email)).sid;
  });
  const g = () => env.usuarios.guardia.id;

  it('sin exp, sin iat o sin sid (firma correcta): 401', async () => {
    const base = claims(g(), 'guard', sid);
    const sin = (k: string): Record<string, unknown> =>
      Object.fromEntries(Object.entries(base).filter(([n]) => n !== k));
    const sinExp = sin('exp');
    const sinIat = sin('iat');
    const sinSid = sin('sid');
    for (const c of [sinExp, sinIat, sinSid]) {
      const res = await me(env.app, firmarHmac(c));
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    }
  });

  it('sin sub (firma correcta): 401', async () => {
    const sinSub = Object.fromEntries(
      Object.entries(claims(g(), 'guard', sid)).filter(([n]) => n !== 'sub'),
    );
    const res = await me(env.app, firmarHmac(sinSub));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('emitido hace más de maxAge (iat viejo con exp lejano): 401', async () => {
    const c = { ...claims(g(), 'guard', sid), iat: ahora() - 1200, exp: ahora() + 3600 };
    const res = await me(env.app, firmarHmac(c));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('exp más allá de la vigencia de acceso (iat actual, exp = +1 día): 401', async () => {
    const c = { ...claims(g(), 'guard', sid), exp: ahora() + 86_400 };
    const res = await me(env.app, firmarHmac(c));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('cabeceras kid/jku/x5u/typ raras con la firma correcta: se ignoran (misma clave)', async () => {
    const cuerpo = claims(g(), 'guard', sid);
    const { createHmac } = await import('node:crypto');
    const header = {
      alg: 'HS256',
      typ: 'at+jwt',
      kid: 'otra-clave',
      jku: 'http://atacante.test/jwks.json',
      x5u: 'http://atacante.test/cert.pem',
    };
    const sinFirma = forjarJwt(header, cuerpo).slice(0, -1); // "cabecera.payload"
    const firma = createHmac('sha256', JWT_SECRET).update(sinFirma).digest('base64url');
    const ok = await me(env.app, `${sinFirma}.${firma}`);
    expect(ok.status).toBe(200);
    expect(ok.body.data.id).toBe(g());
    // Con firma ajena la cabecera no cambia la clave: 401.
    const ajena = createHmac('sha256', 'clave-del-atacante-de-al-menos-32-chars!!')
      .update(sinFirma)
      .digest('base64url');
    const mal = await me(env.app, `${sinFirma}.${ajena}`);
    expect(mal.status).toBe(401);
    expect(mal.body).toEqual(ERROR_401);
    // typ raro (distinto de JWT) con firma correcta no rompe ni escala nada.
    const typ = await me(env.app, firmarHmac(cuerpo));
    expect(typ.status).toBe(200);
  });

  it('un refresh token enviado como Bearer: 401', async () => {
    const s = await iniciar(env.usuarios.guardia.email);
    for (const valor of [`Bearer ${s.refresh}`, `Bearer ${s.refresh}.x.y`]) {
      const res = await request(env.app.server).get('/api/v1/auth/me').set('Authorization', valor);
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    }
  });

  it('un access token enviado como refreshToken: 401', async () => {
    const s = await iniciar(env.usuarios.guardia.email);
    const res = await refresh(env.app, s.access);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('el mismo rechazo aplica a /auth/session y /auth/logout', async () => {
    const sinIat = Object.fromEntries(
      Object.entries(claims(g(), 'guard', sid)).filter(([n]) => n !== 'iat'),
    );
    expect((await session(env.app, firmarHmac(sinIat), { userId: g() })).status).toBe(401);
    expect((await logout(env.app, firmarHmac(sinIat))).status).toBe(401);
  });
});

describe('rehash de contraseñas (needsRehash)', () => {
  it('login exitoso con hash de otros parámetros lo re-hashea; sigue funcionando', async () => {
    const viejo = await (await import('../../../src/auth/password.js'))
      .createPasswordHasher({ memoryCost: 2048, timeCost: 2, parallelism: 1 })
      .hash(PASSWORD);
    const u = await env.prisma.user.create({
      data: {
        name: 'Rehash',
        email: 'rehash@prueba.test',
        phone: '7770000000',
        passwordHash: viejo,
        role: 'protected_user',
      },
    });
    const leer = async () =>
      (await env.prisma.$queryRaw<{ h: string }[]>`SELECT password_hash AS h FROM users WHERE id = ${u.id}::uuid`)[0]
        ?.h ?? '';
    expect(hasherPrueba.needsRehash(viejo)).toBe(true);

    // Una contraseña incorrecta no re-hashea.
    expect((await login(env.app, u.email, 'Mala12345')).status).toBe(401);
    expect(await leer()).toBe(viejo);

    const ok = await login(env.app, u.email);
    expect(ok.status).toBe(200);
    const nuevo = await leer();
    expect(nuevo).not.toBe(viejo);
    expect(hasherPrueba.needsRehash(nuevo)).toBe(false);
    expect(nuevo).toContain(`$m=${String(ARGON2_PRUEBA.memoryCost)},t=2,p=1$`);
    expect(await hasherPrueba.verify(nuevo, PASSWORD)).toBe(true);

    // Y el siguiente login con el hash nuevo funciona sin volver a cambiarlo.
    expect((await login(env.app, u.email)).status).toBe(200);
    expect(await leer()).toBe(nuevo);
  });
});

describe('respuestas indistinguibles y sin datos sensibles', () => {
  it('login de inactivo con contraseña correcta no crea filas en refresh_tokens', async () => {
    const res = await login(env.app, env.usuarios.inactivo.email, PASSWORD);
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
    expect(await env.prisma.refreshToken.count()).toBe(0);
  });

  it('/auth/session con userId de otro usuario existente = exactamente igual que con uno inexistente', async () => {
    const s = await iniciar(env.usuarios.admin.email);
    const ajeno = await session(env.app, s.access, { userId: env.usuarios.guardia.id });
    const inexistente = await session(env.app, s.access, { userId: '22222222-2222-4222-8222-222222222222' });
    expect(ajeno.status).toBe(inexistente.status);
    expect(ajeno.text).toBe(inexistente.text);
    expect(ajeno.text).toBe('{"data":null}');
    for (const h of ['content-type', 'cache-control', 'content-length']) {
      expect(ajeno.headers[h]).toBe(inexistente.headers[h]);
    }
  });

  it('Cache-Control: no-store en login, refresh, me, session y logout', async () => {
    const l = await login(env.app, env.usuarios.protegido.email);
    const a = l.body.data.accessToken as string;
    const r = await refresh(env.app, l.body.data.refreshToken as string);
    const m = await me(env.app, r.body.data.accessToken as string);
    const se = await session(env.app, r.body.data.accessToken as string, { userId: env.usuarios.protegido.id });
    const lo = await logout(env.app, r.body.data.accessToken as string);
    expect(a).toBeTruthy();
    for (const res of [l, r, m, se, lo]) {
      expect(res.status).toBe(200);
      expect(res.headers['cache-control']).toBe('no-store');
    }
  });

  it('Cache-Control: no-store también en errores de /api/v1', async () => {
    const errores = [
      await login(env.app, 'nadie@prueba.test'), // 401 credenciales
      await request(env.app.server).post('/api/v1/auth/login').send({ x: 1 }), // 400
      await me(env.app), // 401
      await refresh(env.app, 'a'.repeat(43)), // 401
      await request(env.app.server).post('/api/v1/auth/session'), // 401
    ];
    for (const res of errores) {
      expect(res.status).toBeGreaterThanOrEqual(400);
      expect(res.headers['cache-control']).toBe('no-store');
    }
  });

  it('Cache-Control: no-store en un 404 bajo /api/v1', async () => {
    const res = await request(env.app.server).get('/api/v1/no-existe');
    expect(res.status).toBe(404);
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('ninguna respuesta de auth contiene "passwordHash" ni "$argon2"', async () => {
    const textos: string[] = [];
    const guardar = (...rs: { text: string; headers: unknown }[]) => {
      for (const r of rs) textos.push(r.text, JSON.stringify(r.headers));
    };
    const l = await login(env.app, env.usuarios.bloqueado.email);
    guardar(l);
    guardar(await login(env.app, env.usuarios.inactivo.email));
    guardar(await login(env.app, 'nadie@prueba.test'));
    guardar(await request(env.app.server).post('/api/v1/auth/login').send({ email: 'a@b.c', password: 'x', extra: 'h' }));
    const token = l.body.data.accessToken as string;
    guardar(await me(env.app, token));
    guardar(await session(env.app, token, { userId: env.usuarios.bloqueado.id }));
    const r = await refresh(env.app, l.body.data.refreshToken as string);
    guardar(r);
    guardar(await refresh(env.app, 'a'.repeat(43)));
    guardar(await logout(env.app, r.body.data.accessToken as string));
    guardar(await me(env.app, token));
    expect(textos.length).toBeGreaterThan(10);
    for (const t of textos) {
      expect(t).not.toContain('passwordHash');
      expect(t).not.toContain('password_hash');
      expect(t).not.toContain('$argon2');
    }
  });
});
