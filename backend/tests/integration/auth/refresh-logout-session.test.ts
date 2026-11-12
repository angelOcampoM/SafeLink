// BE-01 paso 5: refresh con rotación y gracia, logout y restauración de sesión (D7, D8, D25).
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { createTokenFamily, hashRefreshToken, rotateRefreshToken } from '../../../src/auth/tokens.js';
import {
  MSG_UNAUTHORIZED,
  USER_KEYS,
  configPrueba,
  crearEntorno,
  decodificar,
  firmarHmac,
  login,
  logout,
  me,
  refresh,
  session,
  type Entorno,
} from './helpers.js';

const ERROR_401 = { error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } };

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

describe('POST /auth/refresh - rotación', () => {
  it('rota: el viejo queda usado, el nuevo es distinto y funciona', async () => {
    const s = await iniciar();
    const res = await refresh(env.app, s.refresh);
    expect(res.status).toBe(200);
    expect(Object.keys(res.body)).toEqual(['data']);
    expect(Object.keys(res.body.data).sort()).toEqual([...USER_KEYS, 'accessToken', 'refreshToken'].sort());
    expect(res.body.data.id).toBe(env.usuarios.protegido.id);
    const nuevo = res.body.data.refreshToken as string;
    expect(nuevo).not.toBe(s.refresh);
    // El sid se conserva y el access nuevo sirve.
    expect(decodificar(res.body.data.accessToken).payload['sid']).toBe(s.sid);
    expect((await me(env.app, res.body.data.accessToken as string)).status).toBe(200);

    const filas = await filasDe(s.sid);
    expect(filas).toHaveLength(2);
    const viejo = filas.find((f) => f.tokenHash === hashRefreshToken(s.refresh));
    const sucesor = filas.find((f) => f.tokenHash === hashRefreshToken(nuevo));
    expect(viejo?.usedAt).not.toBeNull();
    expect(viejo?.replacedById).toBe(sucesor?.id);
    expect(sucesor?.parentId).toBe(viejo?.id);
    expect(sucesor?.usedAt).toBeNull();
    for (const f of filas) expect(f.tokenHash).toMatch(/^[0-9a-f]{64}$/);

    // El token nuevo rota otra vez.
    const otra = await refresh(env.app, nuevo);
    expect(otra.status).toBe(200);
  });

  it('reutilizar el viejo dentro de la gracia: 200 con sucesor nuevo UNA vez', async () => {
    const s = await iniciar();
    const primero = await refresh(env.app, s.refresh);
    const gracia = await refresh(env.app, s.refresh);
    expect(gracia.status).toBe(200);
    expect(gracia.body.data.refreshToken).not.toBe(primero.body.data.refreshToken);
    expect(gracia.body.data.refreshToken).not.toBe(s.refresh);
    // Ambos sucesores son hijos del viejo y de la misma familia.
    const filas = await filasDe(s.sid);
    expect(filas).toHaveLength(3);
    expect(filas.every((f) => f.revokedAt === null)).toBe(true);
    // Ambos sucesores siguen sirviendo.
    expect((await me(env.app, gracia.body.data.accessToken as string)).status).toBe(200);
  });

  it('segunda reutilización del viejo: 401 y familia revocada (sucesores y access)', async () => {
    const s = await iniciar();
    const primero = await refresh(env.app, s.refresh);
    const gracia = await refresh(env.app, s.refresh);
    const tercera = await refresh(env.app, s.refresh);
    expect(tercera.status).toBe(401);
    expect(tercera.body).toEqual(ERROR_401);
    const filas = await filasDe(s.sid);
    expect(filas.every((f) => f.revokedAt !== null)).toBe(true);
    for (const r of [primero, gracia]) {
      expect((await refresh(env.app, r.body.data.refreshToken as string)).status).toBe(401);
      expect((await me(env.app, r.body.data.accessToken as string)).status).toBe(401);
    }
    expect((await me(env.app, s.access)).status).toBe(401);
  });

  it('reutilizar fuera de la ventana: 401 y familia revocada', async () => {
    const s = await iniciar();
    const primero = await refresh(env.app, s.refresh);
    // El viejo se usó hace una hora (el reloj no se espera: se fija used_at).
    await env.prisma.refreshToken.updateMany({
      where: { tokenHash: hashRefreshToken(s.refresh) },
      data: { usedAt: new Date(Date.now() - 3_600_000) },
    });
    const res = await refresh(env.app, s.refresh);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
    expect((await filasDe(s.sid)).every((f) => f.revokedAt !== null)).toBe(true);
    expect((await refresh(env.app, primero.body.data.refreshToken as string)).status).toBe(401);
    expect((await me(env.app, primero.body.data.accessToken as string)).status).toBe(401);
  });

  it('refresh vencido: 401 sin revocar la familia', async () => {
    const s = await iniciar();
    await env.prisma.refreshToken.updateMany({
      where: { familyId: s.sid },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    const res = await refresh(env.app, s.refresh);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
    const filas = await filasDe(s.sid);
    expect(filas.every((f) => f.revokedAt === null && f.usedAt === null)).toBe(true);
    expect(filas).toHaveLength(1);
  });

  it('token revocado: 401', async () => {
    const s = await iniciar();
    await env.prisma.refreshToken.updateMany({ where: { familyId: s.sid }, data: { revokedAt: new Date() } });
    expect((await refresh(env.app, s.refresh)).status).toBe(401);
  });

  it.each([
    ['inexistente', 'a'.repeat(43)],
    ['formato inválido', 'no es un token!!'],
    ['con comillas y SQL', "' OR 1=1 --"],
    ['un access token', 'eyJhbGciOiJIUzI1NiJ9.e30.x'],
  ])('token %s: 401 UNAUTHORIZED', async (_n, token) => {
    const res = await refresh(env.app, token);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('usuario inactivo: 401 y la familia queda revocada', async () => {
    const s = await iniciar(env.usuarios.guardia.email);
    await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: false } });
    try {
      const res = await refresh(env.app, s.refresh);
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
      expect((await filasDe(s.sid)).every((f) => f.revokedAt !== null)).toBe(true);
    } finally {
      await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: true } });
    }
  });

  it.each([
    ['campo extra', (t: string) => ({ refreshToken: t, userId: 'x' })],
    ['sin refreshToken', () => ({})],
    ['refreshToken de más de 512', () => ({ refreshToken: 'a'.repeat(513) })],
    ['refreshToken numérico', () => ({ refreshToken: 5 })],
  ])('cuerpo inválido (%s): 400 INVALID_STATE y no rota', async (_n, mk) => {
    const s = await iniciar();
    const res = await request(env.app.server).post('/api/v1/auth/refresh').send(mk(s.refresh));
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect((await filasDe(s.sid)).filter((f) => f.usedAt !== null)).toHaveLength(0);
  });

  it('refreshToken vacío o con forma inválida: 401 (no 400) y no toca la base', async () => {
    const s = await iniciar();
    for (const t of ['', 'a'.repeat(42), 'a'.repeat(44), `${'a'.repeat(42)}=`, `${'a'.repeat(42)} `]) {
      const res = await refresh(env.app, t);
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    }
    expect((await filasDe(s.sid)).every((f) => f.usedAt === null && f.revokedAt === null)).toBe(true);
  });

  it('no requiere Authorization (ruta pública) y se ignora un Bearer inválido', async () => {
    const s = await iniciar();
    const res = await request(env.app.server)
      .post('/api/v1/auth/refresh')
      .set('Authorization', 'Bearer basura')
      .send({ refreshToken: s.refresh });
    expect(res.status).toBe(200);
  });

  it('refresh concurrente con el mismo token: documenta el resultado y acota las ramas', async () => {
    const s = await iniciar();
    const [a, b] = await Promise.all([refresh(env.app, s.refresh), refresh(env.app, s.refresh)]);
    const estados = [a.status, b.status].sort();
    // El FOR UPDATE ordena ambas: la primera rota, la segunda cae en la gracia (permitida UNA vez).
    // Nunca más de dos sucesores del mismo token ni errores 5xx.
    expect(estados.every((e) => e === 200 || e === 401)).toBe(true);
    const filas = await filasDe(s.sid);
    const hijos = filas.filter((f) => f.parentId !== null);
    expect(hijos.length).toBeLessThanOrEqual(2);
    expect(hijos.length).toBe(estados.filter((e) => e === 200).length);
    expect(filas.filter((f) => f.usedAt !== null)).toHaveLength(1);
    // Resultado esperado con la gracia activa: ambas 200 y dos ramas.
    expect(estados).toEqual([200, 200]);
    // Y la siguiente reutilización ya revoca todo.
    expect((await refresh(env.app, s.refresh)).status).toBe(401);
    expect((await filasDe(s.sid)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('sin gracia (REFRESH_GRACE_SECONDS=0) la reutilización inmediata revoca la familia', async () => {
    const sinGracia = buildApp(configPrueba({ REFRESH_GRACE_SECONDS: '0' }), { prisma: env.prisma });
    await sinGracia.ready();
    try {
      const l = await login(sinGracia, env.usuarios.protegido.email);
      const viejo = l.body.data.refreshToken as string;
      const sid = decodificar(l.body.data.accessToken as string).payload['sid'] as string;
      const rot = await refresh(sinGracia, viejo);
      expect(rot.status).toBe(200);
      const reuso = await refresh(sinGracia, viejo);
      expect(reuso.status).toBe(401);
      expect((await filasDe(sid)).every((f) => f.revokedAt !== null)).toBe(true);
      expect((await refresh(sinGracia, rot.body.data.refreshToken as string)).status).toBe(401);
    } finally {
      await sinGracia.close();
    }
  });
});

describe('rotateRefreshToken con reloj inyectado (D25)', () => {
  const BASE = new Date('2026-01-01T00:00:00.000Z');
  const opts = { ttlSeconds: 86_400, maxAgeSeconds: 7_776_000, graceSeconds: 5 };
  const seg = (n: number) => new Date(BASE.getTime() + n * 1000);

  async function nuevaFamilia() {
    await env.prisma.refreshToken.deleteMany();
    return createTokenFamily(env.prisma, env.usuarios.protegido.id, opts, BASE);
  }

  it('dentro de la ventana (borde inclusivo, 5 s por defecto) acepta una vez; la segunda revoca', async () => {
    const t = await nuevaFamilia();
    const r1 = await rotateRefreshToken(env.prisma, t.token, opts, BASE);
    expect(r1.ok).toBe(true);
    const r2 = await rotateRefreshToken(env.prisma, t.token, opts, seg(5));
    expect(r2.ok).toBe(true);
    const r3 = await rotateRefreshToken(env.prisma, t.token, opts, seg(5));
    expect(r3.ok).toBe(false);
    expect((await filasDe(t.familyId)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('a los 6 s ya es reutilización: rechazo y familia revocada', async () => {
    const t = await nuevaFamilia();
    expect((await rotateRefreshToken(env.prisma, t.token, opts, BASE)).ok).toBe(true);
    expect((await rotateRefreshToken(env.prisma, t.token, opts, seg(6))).ok).toBe(false);
    expect((await filasDe(t.familyId)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('graceSeconds=0 desactiva la gracia', async () => {
    const t = await nuevaFamilia();
    const sin = { ...opts, graceSeconds: 0 };
    expect((await rotateRefreshToken(env.prisma, t.token, sin, BASE)).ok).toBe(true);
    expect((await rotateRefreshToken(env.prisma, t.token, sin, BASE)).ok).toBe(false);
    expect((await filasDe(t.familyId)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('vencimiento por reloj inyectado: exactamente en expiresAt ya no sirve, sin revocar', async () => {
    const t = await nuevaFamilia();
    expect((await rotateRefreshToken(env.prisma, t.token, opts, seg(86_400))).ok).toBe(false);
    expect((await filasDe(t.familyId)).every((f) => f.revokedAt === null)).toBe(true);
    expect((await rotateRefreshToken(env.prisma, t.token, opts, seg(86_399))).ok).toBe(true);
  });
});

describe('POST /auth/logout', () => {
  it('data null; luego /me y refresh dan 401', async () => {
    const s = await iniciar();
    const res = await logout(env.app, s.access);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
    expect((await me(env.app, s.access)).status).toBe(401);
    const r = await refresh(env.app, s.refresh);
    expect(r.status).toBe(401);
    expect(r.body).toEqual(ERROR_401);
    expect((await filasDe(s.sid)).every((f) => f.revokedAt !== null)).toBe(true);
  });

  it('revoca también los sucesores rotados', async () => {
    const s = await iniciar();
    const rot = await refresh(env.app, s.refresh);
    expect((await logout(env.app, rot.body.data.accessToken as string)).status).toBe(200);
    expect((await refresh(env.app, rot.body.data.refreshToken as string)).status).toBe(401);
  });

  it('otra sesión del mismo usuario (otro login) sigue viva', async () => {
    const a = await iniciar();
    const b = await iniciar();
    expect((await logout(env.app, a.access)).status).toBe(200);
    expect((await me(env.app, b.access)).status).toBe(200);
    expect((await refresh(env.app, b.refresh)).status).toBe(200);
  });

  it('sin token: 401; repetir logout con el mismo token: 401', async () => {
    const s = await iniciar();
    const sin = await request(env.app.server).post('/api/v1/auth/logout');
    expect(sin.status).toBe(401);
    expect(sin.body).toEqual(ERROR_401);
    await logout(env.app, s.access);
    expect((await logout(env.app, s.access)).status).toBe(401);
  });
});

describe('POST /auth/session', () => {
  const ahora = () => Math.floor(Date.now() / 1000);

  it('todo bien: devuelve el User (sin tokens)', async () => {
    const s = await iniciar(env.usuarios.admin.email);
    const res = await session(env.app, s.access, { userId: env.usuarios.admin.id });
    expect(res.status).toBe(200);
    expect(Object.keys(res.body.data).sort()).toEqual([...USER_KEYS].sort());
    expect(res.body.data.id).toBe(env.usuarios.admin.id);
  });

  it('userId en mayúsculas del mismo usuario también se acepta', async () => {
    const s = await iniciar(env.usuarios.admin.email);
    const res = await session(env.app, s.access, { userId: env.usuarios.admin.id.toUpperCase() });
    expect(res.status).toBe(200);
    expect(res.body.data?.id).toBe(env.usuarios.admin.id);
  });

  it.each([
    ['userId ajeno', () => env.usuarios.guardia.id],
    ['userId no UUID', () => 'no-soy-uuid'],
    ['userId vacío', () => ''],
  ])('%s: 200 con data null', async (_n, userId) => {
    const s = await iniciar(env.usuarios.admin.email);
    const res = await session(env.app, s.access, { userId: userId() });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
  });

  it('sesión revocada: 200 con data null', async () => {
    const s = await iniciar();
    await logout(env.app, s.access);
    const res = await session(env.app, s.access, { userId: env.usuarios.protegido.id });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
  });

  it('usuario inactivo después de emitir: 200 con data null', async () => {
    const s = await iniciar(env.usuarios.guardia.email);
    await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: false } });
    try {
      const res = await session(env.app, s.access, { userId: env.usuarios.guardia.id });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ data: null });
    } finally {
      await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: true } });
    }
  });

  it('sin token: 401', async () => {
    const res = await session(env.app, undefined, { userId: env.usuarios.admin.id });
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('firma inválida: 401', async () => {
    const s = await iniciar();
    const res = await session(env.app, `${s.access}x`, { userId: env.usuarios.protegido.id });
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('vencido: 401 (no data null)', async () => {
    const s = await iniciar();
    const token = firmarHmac({
      sub: env.usuarios.protegido.id,
      role: 'protected_user',
      sid: s.sid,
      iat: 1_700_000_000,
      exp: 1_700_000_900,
    });
    const res = await session(env.app, token, { userId: env.usuarios.protegido.id });
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('campo extra: 400 INVALID_STATE', async () => {
    const s = await iniciar();
    const res = await session(env.app, s.access, { userId: env.usuarios.protegido.id, role: 'admin' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });

  it('userId de más de 100 caracteres o sin userId: 400', async () => {
    const s = await iniciar();
    expect((await session(env.app, s.access, { userId: 'a'.repeat(101) })).status).toBe(400);
    expect((await session(env.app, s.access, {})).status).toBe(400);
  });

  it('token válido de la sesión pero firmado con sub ajeno no restaura al otro usuario', async () => {
    const s = await iniciar();
    const token = firmarHmac({
      sub: env.usuarios.admin.id,
      role: 'admin',
      sid: s.sid,
      iat: ahora(),
      exp: ahora() + 900,
    });
    const res = await session(env.app, token, { userId: env.usuarios.admin.id });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
  });
});
