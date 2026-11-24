// BE-04 paso 9 (D42): PUT /users/me/device-token y findLiveTokens. Contra PostgreSQL real.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { revokeAllUserFamilies } from '../../../src/auth/tokens.js';
import { createDevicesService } from '../../../src/modules/devices/service.js';
import {
  MSG_UNAUTHORIZED,
  PASSWORD,
  crearEntorno,
  decodificar,
  hasherPrueba,
  login,
  logout,
  refresh,
  type Entorno,
} from '../auth/helpers.js';

const RUTA = '/api/v1/users/me/device-token';
const MSG_TOKEN = 'El token del dispositivo no es válido';
const ERROR_401 = { error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } };

let env: Entorno;
let n = 0;
const nuevoToken = (): string => `fcm-token-${String((n += 1))}-${'x'.repeat(40)}`;

beforeAll(async () => {
  env = await crearEntorno();
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});
beforeEach(async () => {
  await env.prisma.deviceToken.deleteMany();
  await env.prisma.refreshToken.deleteMany();
  await env.prisma.user.updateMany({
    data: { isActive: true },
    where: { email: { not: env.usuarios.inactivo.email } },
  });
});

interface Sesion {
  access: string;
  sid: string;
}

async function iniciar(email = env.usuarios.guardia.email): Promise<Sesion> {
  const res = await login(env.app, email);
  const access = res.body.data.accessToken as string;
  return { access, sid: decodificar(access).payload['sid'] as string };
}

const put = (access: string | undefined, cuerpo?: unknown) => {
  let r = request(env.app.server).put(RUTA);
  if (access !== undefined) r = r.set('Authorization', `Bearer ${access}`);
  return cuerpo === undefined ? r : r.send(cuerpo as object);
};

const filas = () => env.prisma.deviceToken.findMany();

async function crearGuardia(slug: string): Promise<{ id: string; email: string }> {
  const u = await env.prisma.user.create({
    data: {
      name: `G ${slug}`,
      email: `${slug}@prueba.test`,
      phone: '7771234567',
      passwordHash: await hasherPrueba.hash(PASSWORD),
      role: 'guard',
    },
  });
  return { id: u.id, email: u.email };
}

describe('PUT /users/me/device-token - registro (D42)', () => {
  it('200 {data:null}; guarda userId, familyId = sid y lastSeenAt', async () => {
    const s = await iniciar();
    const t = nuevoToken();
    const res = await put(s.access, { token: t });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
    const f = await filas();
    expect(f).toHaveLength(1);
    expect(f[0]?.token).toBe(t);
    expect(f[0]?.userId).toBe(env.usuarios.guardia.id);
    expect(f[0]?.familyId).toBe(s.sid);
    expect(f[0]?.lastSeenAt).toBeInstanceOf(Date);
  });

  it('idempotente: segundo PUT con el mismo token -> 200, una fila y lastSeenAt no retrocede', async () => {
    const s = await iniciar();
    const t = nuevoToken();
    await put(s.access, { token: t });
    const antes = (await filas())[0]!;
    const res = await put(s.access, { token: t });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
    const f = await filas();
    expect(f).toHaveLength(1);
    expect(f[0]?.id).toBe(antes.id);
    expect(f[0]!.lastSeenAt.getTime()).toBeGreaterThanOrEqual(antes.lastSeenAt.getTime());
  });

  it('un token de 512 caracteres es válido', async () => {
    const s = await iniciar();
    const res = await put(s.access, { token: 'a'.repeat(512) });
    expect(res.status).toBe(200);
    expect(await filas()).toHaveLength(1);
  });

  it('reasignación: guardia A registra T y guardia B registra T -> una fila de B', async () => {
    const b = await crearGuardia('guardia-b');
    const sa = await iniciar();
    const sb = await iniciar(b.email);
    const t = nuevoToken();
    expect((await put(sa.access, { token: t })).status).toBe(200);
    expect((await put(sb.access, { token: t })).status).toBe(200);
    const f = await filas();
    expect(f).toHaveLength(1);
    expect(f[0]?.userId).toBe(b.id);
    expect(f[0]?.familyId).toBe(sb.sid);
  });

  it('varios tokens por usuario (dos sesiones) conviven', async () => {
    const s1 = await iniciar();
    const s2 = await iniciar();
    expect(s1.sid).not.toBe(s2.sid);
    const [t1, t2] = [nuevoToken(), nuevoToken()];
    await put(s1.access, { token: t1 });
    await put(s2.access, { token: t2 });
    const f = await filas();
    expect(f.map((x) => x.token).sort()).toEqual([t1, t2].sort());
    expect(new Set(f.map((x) => x.userId))).toEqual(new Set([env.usuarios.guardia.id]));
  });

  it('dos tokens en la misma sesión conviven', async () => {
    const s = await iniciar();
    await put(s.access, { token: nuevoToken() });
    await put(s.access, { token: nuevoToken() });
    expect(await filas()).toHaveLength(2);
  });

  it('la respuesta no contiene el token', async () => {
    const s = await iniciar();
    const t = nuevoToken();
    const res = await put(s.access, { token: t });
    expect(res.text).not.toContain(t);
    expect(JSON.stringify(res.headers)).not.toContain(t);
  });
});

describe('PUT /users/me/device-token - validación (400)', () => {
  const MSG_GENERICO = 'Los datos enviados no son válidos';
  const casos: Array<[string, unknown, string]> = [
    ['vacío', { token: '' }, MSG_TOKEN],
    ['solo espacios', { token: '   ' }, MSG_TOKEN],
    ['espacio interno', { token: 'abc def' }, MSG_TOKEN],
    ['espacio al inicio', { token: ' abc' }, MSG_TOKEN],
    ['salto de línea', { token: 'abc\ndef' }, MSG_TOKEN],
    ['carácter nulo', { token: 'abc\u0000def' }, MSG_TOKEN],
    ['otro control', { token: 'abc\u0007def' }, MSG_TOKEN],
    ['no ASCII', { token: 'tokén' }, MSG_TOKEN],
    ['símbolo fuera del alfabeto', { token: 'abc/def' }, MSG_TOKEN],
    ['513 caracteres', { token: 'a'.repeat(513) }, MSG_TOKEN],
    ['número', { token: 123 }, MSG_TOKEN],
    ['null', { token: null }, MSG_TOKEN],
    ['objeto', { token: { a: 1 } }, MSG_TOKEN],
    ['arreglo', { token: ['a'] }, MSG_TOKEN],
    ['sin clave token', {}, MSG_TOKEN],
    ['clave extra', { token: 'abc', extra: 1 }, 'Campos no permitidos: extra'],
    ['cuerpo null', null, MSG_GENERICO],
    ['cuerpo arreglo', ['abc'], MSG_GENERICO],
  ];
  it.each(casos)('%s -> 400 sin filas', async (_n, cuerpo, mensaje) => {
    const s = await iniciar();
    const res = await put(s.access, cuerpo);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: { code: 'INVALID_STATE', message: mensaje } });
    expect(await filas()).toHaveLength(0);
  });

  it('sin cuerpo -> 400 sin filas', async () => {
    const s = await iniciar();
    const res = await put(s.access);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(await filas()).toHaveLength(0);
  });

  it('__proto__ en el cuerpo -> 400 sin filas', async () => {
    const s = await iniciar();
    const res = await request(env.app.server)
      .put(RUTA)
      .set('Authorization', `Bearer ${s.access}`)
      .set('content-type', 'application/json')
      .send('{"__proto__":{"token":"abc"},"token":"abc"}');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(await filas()).toHaveLength(0);
  });

  it('JSON malformado -> 400 sin filas', async () => {
    const s = await iniciar();
    const res = await request(env.app.server)
      .put(RUTA)
      .set('Authorization', `Bearer ${s.access}`)
      .set('content-type', 'application/json')
      .send('{"token": ');
    expect(res.status).toBe(400);
    expect(await filas()).toHaveLength(0);
  });
});

describe('PUT /users/me/device-token - permisos', () => {
  it('sin token -> 401', async () => {
    const res = await put(undefined, { token: nuevoToken() });
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
    expect(await filas()).toHaveLength(0);
  });

  it('token basura -> 401', async () => {
    expect((await put('a.b.c', { token: nuevoToken() })).status).toBe(401);
  });

  it.each([
    ['protected_user', () => env.usuarios.protegido.email],
    ['admin', () => env.usuarios.admin.email],
  ])('%s -> 403 sin filas', async (_rol, email) => {
    const s = await iniciar(email());
    const res = await put(s.access, { token: nuevoToken() });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
    expect(await filas()).toHaveLength(0);
  });

  it('rol incorrecto con cuerpo inválido -> 403, no 400', async () => {
    const s = await iniciar(env.usuarios.admin.email);
    expect((await put(s.access, { token: '' })).status).toBe(403);
  });

  it('guardia dado de baja con access ya emitido -> 401 y sin filas', async () => {
    const s = await iniciar();
    await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: false } });
    const res = await put(s.access, { token: nuevoToken() });
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
    expect(await filas()).toHaveLength(0);
  });
});

describe('PUT /users/me/device-token - sesión revocada y borrado de tokens', () => {
  it('tras logout el mismo access -> 401 y sin filas', async () => {
    const s = await iniciar();
    expect((await logout(env.app, s.access)).status).toBeLessThan(300);
    const res = await put(s.access, { token: nuevoToken() });
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
    expect(await filas()).toHaveLength(0);
  });

  it('la comprobación bajo el lock: register con una familia revocada -> 401 y sin filas', async () => {
    // Simula la carrera: authenticate pasó, pero la familia se revocó antes de tomar el lock.
    const s = await iniciar();
    await logout(env.app, s.access);
    const svc = createDevicesService({ prisma: env.prisma });
    await expect(svc.register(env.usuarios.guardia.id, s.sid, nuevoToken())).rejects.toMatchObject({
      httpStatus: 401,
    });
    expect(await filas()).toHaveLength(0);
  });

  it('register con una sesión inexistente -> 401 y sin filas', async () => {
    const svc = createDevicesService({ prisma: env.prisma });
    await expect(
      svc.register(env.usuarios.guardia.id, '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11', nuevoToken()),
    ).rejects.toMatchObject({ httpStatus: 401 });
    expect(await filas()).toHaveLength(0);
  });

  it('logout borra SOLO los tokens de su sid', async () => {
    const s1 = await iniciar();
    const s2 = await iniciar();
    const [t1, t2] = [nuevoToken(), nuevoToken()];
    await put(s1.access, { token: t1 });
    await put(s2.access, { token: t2 });
    expect((await logout(env.app, s1.access)).status).toBeLessThan(300);
    const f = await filas();
    expect(f.map((x) => x.token)).toEqual([t2]);
  });

  it('logout no toca los tokens de otro guardia', async () => {
    const b = await crearGuardia('guardia-c');
    const sa = await iniciar();
    const sb = await iniciar(b.email);
    await put(sa.access, { token: nuevoToken() });
    const tb = nuevoToken();
    await put(sb.access, { token: tb });
    await logout(env.app, sa.access);
    expect((await filas()).map((x) => x.token)).toEqual([tb]);
  });

  it('reutilización de refresh detectada: la familia se revoca y sus tokens se borran', async () => {
    const res = await login(env.app, env.usuarios.guardia.email);
    const access = res.body.data.accessToken as string;
    const refreshTok = res.body.data.refreshToken as string;
    const otra = await iniciar();
    const [t1, t2] = [nuevoToken(), nuevoToken()];
    await put(access, { token: t1 });
    await put(otra.access, { token: t2 });
    expect((await refresh(env.app, refreshTok)).status).toBe(200);
    expect((await refresh(env.app, refreshTok)).status).toBe(200); // gracia
    expect((await refresh(env.app, refreshTok)).status).toBe(401); // reutilización
    // Solo se borra la familia comprometida; la otra sesión conserva su token.
    expect((await filas()).map((x) => x.token)).toEqual([t2]);
  });

  it('revokeAllUserFamilies borra todos los tokens del usuario y no los de otros', async () => {
    const b = await crearGuardia('guardia-d');
    const s1 = await iniciar();
    const s2 = await iniciar();
    const sb = await iniciar(b.email);
    await put(s1.access, { token: nuevoToken() });
    await put(s2.access, { token: nuevoToken() });
    const tb = nuevoToken();
    await put(sb.access, { token: tb });
    await revokeAllUserFamilies(env.prisma, env.usuarios.guardia.id);
    expect((await filas()).map((x) => x.token)).toEqual([tb]);
  });
});

describe('devicesService.findLiveTokens', () => {
  const svc = () => createDevicesService({ prisma: env.prisma });

  it('lista vacía -> []', async () => {
    expect(await svc().findLiveTokens([])).toEqual([]);
  });

  it('sin tokens registrados -> []', async () => {
    expect(await svc().findLiveTokens([env.usuarios.guardia.id])).toEqual([]);
  });

  it('incluye los tokens de familias vivas de los guardias pedidos y excluye a los demás', async () => {
    const b = await crearGuardia('guardia-e');
    const sa = await iniciar();
    const sa2 = await iniciar();
    const sb = await iniciar(b.email);
    const [ta, ta2, tb] = [nuevoToken(), nuevoToken(), nuevoToken()];
    await put(sa.access, { token: ta });
    await put(sa2.access, { token: ta2 });
    await put(sb.access, { token: tb });
    expect((await svc().findLiveTokens([env.usuarios.guardia.id])).sort()).toEqual([ta, ta2].sort());
    expect(await svc().findLiveTokens([b.id])).toEqual([tb]);
    expect((await svc().findLiveTokens([env.usuarios.guardia.id, b.id])).sort()).toEqual(
      [ta, ta2, tb].sort(),
    );
    expect(await svc().findLiveTokens([env.usuarios.admin.id])).toEqual([]);
  });

  it('excluye la familia revocada (aunque la fila del token siga)', async () => {
    const sa = await iniciar();
    const sa2 = await iniciar();
    const [ta, ta2] = [nuevoToken(), nuevoToken()];
    await put(sa.access, { token: ta });
    await put(sa2.access, { token: ta2 });
    await env.prisma.refreshToken.updateMany({
      where: { familyId: sa.sid },
      data: { revokedAt: new Date() },
    });
    expect(await svc().findLiveTokens([env.usuarios.guardia.id])).toEqual([ta2]);
  });

  it('excluye el refresh vencido y acepta el reloj inyectado', async () => {
    const sa = await iniciar();
    const t = nuevoToken();
    await put(sa.access, { token: t });
    const fila = await env.prisma.refreshToken.findFirstOrThrow({ where: { familyId: sa.sid } });
    const id = [env.usuarios.guardia.id];
    expect(await svc().findLiveTokens(id, new Date(fila.expiresAt.getTime() - 1000))).toEqual([t]);
    expect(await svc().findLiveTokens(id, new Date(fila.expiresAt.getTime() + 1000))).toEqual([]);
    await env.prisma.refreshToken.updateMany({
      where: { familyId: sa.sid },
      data: { expiresAt: new Date('2000-01-01T00:00:00Z') },
    });
    expect(await svc().findLiveTokens(id)).toEqual([]);
  });

  it('excluye al usuario inactivo', async () => {
    const sa = await iniciar();
    await put(sa.access, { token: nuevoToken() });
    await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: false } });
    expect(await svc().findLiveTokens([env.usuarios.guardia.id])).toEqual([]);
  });

  it('una familia con un refresh rotado vivo sigue incluida', async () => {
    const res = await login(env.app, env.usuarios.guardia.email);
    const access = res.body.data.accessToken as string;
    const t = nuevoToken();
    await put(access, { token: t });
    expect((await refresh(env.app, res.body.data.refreshToken as string)).status).toBe(200);
    expect(await svc().findLiveTokens([env.usuarios.guardia.id])).toEqual([t]);
  });
});
