// BE-01 paso 5: login y verificación del JWT (D7, D8, D25; API_CONTRATO §5.1).
import { generateKeyPairSync, sign as firmarRsa } from 'node:crypto';
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  MSG_CREDENCIALES,
  MSG_UNAUTHORIZED,
  USER_KEYS,
  crearEntorno,
  decodificar,
  firmarHmac,
  forjarJwt,
  login,
  me,
  type Entorno,
} from './helpers.js';

const ERROR_401 = { error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

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

describe('POST /auth/login - éxito', () => {
  it.each(['protegido', 'guardia', 'admin'] as const)(
    'rol %s: 200 con User exacto + accessToken + refreshToken',
    async (clave) => {
      const u = env.usuarios[clave];
      const res = await login(env.app, u.email);
      expect(res.status).toBe(200);
      expect(Object.keys(res.body)).toEqual(['data']);
      const data = res.body.data as Record<string, unknown>;
      expect(Object.keys(data).sort()).toEqual([...USER_KEYS, 'accessToken', 'refreshToken'].sort());
      expect(data['id']).toBe(u.id);
      expect(data['email']).toBe(u.email);
      expect(data['role']).toBe({ protegido: 'protected_user', guardia: 'guard', admin: 'admin' }[clave]);
      expect(data['isActive']).toBe(true);
      expect(data['volumeDoubleClickEnabled']).toBe(false);
      expect(data['falseAlarmCount']).toBe(0);
      expect(data['blockedUntil']).toBeNull();
      expect(new Date(data['createdAt'] as string).toISOString()).toBe(data['createdAt']);
      expect(typeof data['accessToken']).toBe('string');
      expect(typeof data['refreshToken']).toBe('string');
      expect(JSON.stringify(res.body)).not.toMatch(/passwordHash|password_hash|argon2/i);
    },
  );

  it('normaliza correo con mayúsculas y espacios', async () => {
    const res = await login(env.app, `  ${env.usuarios.admin.email.toUpperCase()}  `);
    expect(res.status).toBe(200);
    expect(res.body.data.email).toBe(env.usuarios.admin.email);
  });

  it('un usuario bloqueado (blocked_until) SÍ inicia sesión y ve su bloqueo', async () => {
    const res = await login(env.app, env.usuarios.bloqueado.email);
    expect(res.status).toBe(200);
    expect(res.body.data.blockedUntil).toBe('2099-01-01T00:00:00.000Z');
    expect(res.body.data.falseAlarmCount).toBe(3);
  });

  it('en BD solo se guarda el hash hexadecimal de 64 caracteres, nunca el token', async () => {
    const res = await login(env.app, env.usuarios.protegido.email);
    const filas = await env.prisma.refreshToken.findMany();
    expect(filas).toHaveLength(1);
    expect(filas[0]?.tokenHash).toMatch(/^[0-9a-f]{64}$/);
    expect(filas[0]?.tokenHash).not.toBe(res.body.data.refreshToken);
    expect(filas[0]?.usedAt).toBeNull();
    expect(filas[0]?.revokedAt).toBeNull();
  });

  it('cada login abre una familia nueva y refresh tokens distintos', async () => {
    const a = await login(env.app, env.usuarios.protegido.email);
    const b = await login(env.app, env.usuarios.protegido.email);
    expect(a.body.data.refreshToken).not.toBe(b.body.data.refreshToken);
    const sidA = decodificar(a.body.data.accessToken).payload['sid'];
    const sidB = decodificar(b.body.data.accessToken).payload['sid'];
    expect(sidA).not.toBe(sidB);
  });
});

describe('POST /auth/login - credenciales (INVALID_CREDENTIALS)', () => {
  it('contraseña mala, correo inexistente e inactivo dan respuestas idénticas', async () => {
    const mala = await login(env.app, env.usuarios.protegido.email, 'OtraClave99');
    const inexistente = await login(env.app, 'nadie@prueba.test');
    const inactivo = await login(env.app, env.usuarios.inactivo.email);
    const inactivoMala = await login(env.app, env.usuarios.inactivo.email, 'OtraClave99');
    for (const r of [mala, inexistente, inactivo, inactivoMala]) {
      expect(r.status).toBe(401);
      expect(r.body).toEqual({ error: { code: 'INVALID_CREDENTIALS', message: MSG_CREDENCIALES } });
    }
    expect(inexistente.text).toBe(mala.text);
    expect(inactivo.text).toBe(mala.text);
    expect(inactivoMala.text).toBe(mala.text);
  });

  it('un login fallido no crea refresh tokens', async () => {
    await login(env.app, env.usuarios.protegido.email, 'mala');
    await login(env.app, env.usuarios.inactivo.email);
    expect(await env.prisma.refreshToken.count()).toBe(0);
  });

  it('password de exactamente 128 caracteres se procesa (borde) y falla por credenciales', async () => {
    const res = await login(env.app, env.usuarios.protegido.email, 'p'.repeat(128));
    expect(res.status).toBe(401);
    expect(res.body.error.code).toBe('INVALID_CREDENTIALS');
  });
});

describe('POST /auth/login - validación (400 INVALID_STATE)', () => {
  const casos: [string, unknown][] = [
    ['campo extra (role)', { email: 'a@b.c', password: 'x', role: 'admin' }],
    ['email de más de 254 caracteres', { email: `${'a'.repeat(250)}@b.cc`, password: 'x' }],
    ['password de más de 128 caracteres', { email: 'a@b.c', password: 'p'.repeat(129) }],
    ['email vacío', { email: '   ', password: 'x' }],
    ['password vacía', { email: 'a@b.c', password: '' }],
    ['sin password', { email: 'a@b.c' }],
    ['tipos incorrectos', { email: 5, password: ['x'] }],
    ['cuerpo arreglo', []],
  ];
  it.each(casos)('%s', async (_n, cuerpo) => {
    const res = await request(env.app.server).post('/api/v1/auth/login').send(cuerpo as object);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(typeof res.body.error.message).toBe('string');
    expect(Object.keys(res.body)).toEqual(['error']);
  });

  it('el campo extra role con credenciales válidas no inicia sesión', async () => {
    const res = await request(env.app.server)
      .post('/api/v1/auth/login')
      .send({ email: env.usuarios.protegido.email, password: 'SafeLink1', role: 'admin' });
    expect(res.status).toBe(400);
    expect(res.text).not.toContain('accessToken');
  });

  it('JSON malformado: 400 INVALID_STATE', async () => {
    const res = await request(env.app.server)
      .post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{"email": ');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });
});

describe('JWT en GET /auth/me', () => {
  let access: string;
  let sid: string;
  const ahora = () => Math.floor(Date.now() / 1000);
  const claimsDe = (sub: string, role: string, sidX = sid) => ({
    sub,
    role,
    sid: sidX,
    iat: ahora(),
    exp: ahora() + 900,
  });

  beforeEach(async () => {
    const res = await login(env.app, env.usuarios.guardia.email);
    access = res.body.data.accessToken as string;
    sid = decodificar(access).payload['sid'] as string;
  });

  it('válido: 200 con User exacto (sin tokens)', async () => {
    const res = await me(env.app, access);
    expect(res.status).toBe(200);
    expect(Object.keys(res.body.data).sort()).toEqual([...USER_KEYS].sort());
    expect(res.body.data.id).toBe(env.usuarios.guardia.id);
    expect(res.body.data.role).toBe('guard');
  });

  it('claims: sub, role, sid (UUID), alg HS256 y 15 minutos de vigencia', () => {
    const { header, payload } = decodificar(access);
    expect(header['alg']).toBe('HS256');
    expect(payload['sub']).toBe(env.usuarios.guardia.id);
    expect(payload['role']).toBe('guard');
    expect(payload['sid']).toMatch(UUID);
    expect((payload['exp'] as number) - (payload['iat'] as number)).toBe(15 * 60);
    expect(Object.keys(payload).sort()).toEqual(['exp', 'iat', 'role', 'sid', 'sub']);
  });

  it('sin token', async () => {
    const res = await me(env.app);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it.each([
    ['Bearer basura', 'Bearer basura'],
    ['esquema distinto (Basic)', 'Basic abc'],
    ['sin esquema', 'abc.def.ghi'],
    ['Bearer vacío', 'Bearer '],
  ])('Authorization inválido: %s', async (_n, valor) => {
    const res = await request(env.app.server).get('/api/v1/auth/me').set('Authorization', valor);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('firma alterada', async () => {
    const [h, p, s] = access.split('.');
    const mala = `${h}.${p}.${s?.slice(0, -2)}${s?.endsWith('AA') ? 'BB' : 'AA'}`;
    const res = await me(env.app, mala);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('payload alterado (escalada de rol) con la firma original', async () => {
    const [h, , s] = access.split('.');
    const { payload } = decodificar(access);
    const p2 = Buffer.from(JSON.stringify({ ...payload, role: 'admin' })).toString('base64url');
    const res = await me(env.app, `${h}.${p2}.${s}`);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('alg none forjado (en varias capitalizaciones)', async () => {
    const claims = claimsDe(env.usuarios.admin.id, 'admin');
    for (const alg of ['none', 'None', 'NONE']) {
      const res = await me(env.app, forjarJwt({ alg, typ: 'JWT' }, claims));
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    }
  });

  it('HS512 y HS384 forjados con el secreto correcto: rechazados (solo HS256)', async () => {
    const claims = claimsDe(env.usuarios.guardia.id, 'guard');
    for (const alg of ['HS512', 'HS384'] as const) {
      const res = await me(env.app, firmarHmac(claims, alg));
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    }
  });

  it('RS256 forjado con una clave RSA propia: rechazado', async () => {
    const claims = claimsDe(env.usuarios.guardia.id, 'guard');
    const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const header = { alg: 'RS256', typ: 'JWT' };
    const sinFirma = forjarJwt(header, claims);
    const firma = firmarRsa('sha256', Buffer.from(sinFirma.slice(0, -1)), privateKey);
    const res = await me(env.app, forjarJwt(header, claims, firma));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('firmado con otro secreto', async () => {
    const claims = claimsDe(env.usuarios.guardia.id, 'guard');
    const res = await me(env.app, firmarHmac(claims, 'HS256', 'otro-secreto-de-al-menos-32-caracteres!!'));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('vencido (exp pasado, firma válida)', async () => {
    const claims = { ...claimsDe(env.usuarios.guardia.id, 'guard'), iat: 1_700_000_000, exp: 1_700_000_900 };
    const res = await me(env.app, firmarHmac(claims));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('control: el mismo token firmado a mano y vigente sí funciona', async () => {
    const res = await me(env.app, firmarHmac(claimsDe(env.usuarios.guardia.id, 'guard')));
    expect(res.status).toBe(200);
  });

  it('claims con tipos incorrectos (sin sid, sub no UUID, role desconocido)', async () => {
    const base = claimsDe(env.usuarios.guardia.id, 'guard');
    const variantes = [
      { ...base, sid: undefined },
      { ...base, sub: 'no-uuid' },
      { ...base, role: 'superadmin' },
    ];
    for (const v of variantes) {
      const res = await me(env.app, firmarHmac(v));
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    }
  });

  it('usuario desactivado después de emitir el token', async () => {
    await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: false } });
    try {
      const res = await me(env.app, access);
      expect(res.status).toBe(401);
      expect(res.body).toEqual(ERROR_401);
    } finally {
      await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: true } });
    }
  });

  it('sid revocado', async () => {
    await env.prisma.refreshToken.updateMany({ where: { familyId: sid }, data: { revokedAt: new Date() } });
    const res = await me(env.app, access);
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('sid inexistente con firma válida', async () => {
    const claims = claimsDe(env.usuarios.guardia.id, 'guard', '11111111-1111-4111-8111-111111111111');
    const res = await me(env.app, firmarHmac(claims));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('sid de la sesión de otro usuario (sub ajeno con sid propio)', async () => {
    const res = await me(env.app, firmarHmac(claimsDe(env.usuarios.admin.id, 'admin')));
    expect(res.status).toBe(401);
    expect(res.body).toEqual(ERROR_401);
  });

  it('el rol sale de la base, no del token (role distinto con sub/sid válidos)', async () => {
    const res = await me(env.app, firmarHmac(claimsDe(env.usuarios.guardia.id, 'admin')));
    expect(res.status).toBe(200);
    expect(res.body.data.role).toBe('guard');
  });
});
