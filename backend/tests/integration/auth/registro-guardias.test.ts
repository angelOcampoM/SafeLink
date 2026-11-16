// BE-02 · Registro, ajustes y gestión de guardias contra la base de pruebas.
// Cubre los siete pasos del issue #52 que no quedaron en BE-01.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PASSWORD, crearEntorno, login, type Entorno } from './helpers.js';

const API = '/api/v1';

let env: Entorno;

beforeAll(async () => {
  env = await crearEntorno();
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});

/** Deja solo los usuarios que creó el entorno. */
beforeEach(async () => {
  await env.prisma.refreshToken.deleteMany();
  await env.prisma.user.deleteMany({ where: { email: { endsWith: '@nuevo.test' } } });
});

const nuevo = (extra: Record<string, unknown> = {}) => ({
  name: 'Ana López Ruiz',
  email: 'ana@nuevo.test',
  phone: '7771234567',
  password: PASSWORD,
  ...extra,
});

const registrar = (body: object) => request(env.app.server).post(`${API}/auth/register`).send(body);

const comoAdmin = async (): Promise<string> => {
  const res = await login(env.app, env.usuarios.admin.email);
  return res.body.data.accessToken as string;
};

const conToken = (token: string) => ({ Authorization: `Bearer ${token}` });

// ── 1 y 2 · Registro público ──────────────────────────────────────────

describe('POST /auth/register', () => {
  it('crea un usuario protegido con sesión abierta y responde 201', async () => {
    const res = await registrar(nuevo());

    expect(res.status).toBe(201);
    expect(res.body.data.role).toBe('protected_user');
    expect(res.body.data.isActive).toBe(true);
    expect(res.body.data.accessToken).toEqual(expect.any(String));
    expect(res.body.data.refreshToken).toEqual(expect.any(String));
    expect(res.body.data).not.toHaveProperty('passwordHash');
  });

  it('el rol nunca lo elige quien se registra', async () => {
    const res = await registrar(nuevo({ role: 'admin' }));
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });

  it('un correo ya registrado da EMAIL_TAKEN y no crea la cuenta', async () => {
    await registrar(nuevo());
    const repetido = await registrar(nuevo({ name: 'Otra Persona Más' }));

    expect(repetido.status).toBe(409);
    expect(repetido.body.error.code).toBe('EMAIL_TAKEN');
    expect(await env.prisma.user.count({ where: { email: 'ana@nuevo.test' } })).toBe(1);
  });

  it('el correo se guarda normalizado', async () => {
    const res = await registrar(nuevo({ email: '  ANA@Nuevo.TEST  ' }));
    expect(res.status).toBe(201);
    expect(res.body.data.email).toBe('ana@nuevo.test');
  });

  it('la cuenta nueva sirve para iniciar sesión', async () => {
    await registrar(nuevo());
    const res = await login(env.app, 'ana@nuevo.test');
    expect(res.status).toBe(200);
    expect(res.body.data.role).toBe('protected_user');
  });
});

// ── 3 · Ajustes del usuario protegido ─────────────────────────────────

describe('PATCH /users/me/settings', () => {
  it('el usuario protegido enciende su disparo por doble clic', async () => {
    const sesion = await login(env.app, env.usuarios.protegido.email);
    const token = sesion.body.data.accessToken as string;

    const res = await request(env.app.server)
      .patch(`${API}/users/me/settings`)
      .set(conToken(token))
      .send({ volumeDoubleClickEnabled: true });

    expect(res.status).toBe(200);
    expect(res.body.data.volumeDoubleClickEnabled).toBe(true);
  });

  it('el guardia no puede tocar ese ajuste', async () => {
    const sesion = await login(env.app, env.usuarios.guardia.email);
    const res = await request(env.app.server)
      .patch(`${API}/users/me/settings`)
      .set(conToken(sesion.body.data.accessToken as string))
      .send({ volumeDoubleClickEnabled: true });

    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });
});

// ── 4, 5 y 6 · Gestión de guardias ────────────────────────────────────

describe('/admin/guards', () => {
  const alta = (token: string, body: object) =>
    request(env.app.server).post(`${API}/admin/guards`).set(conToken(token)).send(body);

  it('el administrador da de alta a un guardia con la contraseña que elige', async () => {
    const token = await comoAdmin();
    const res = await alta(token, nuevo({ email: 'guardia@nuevo.test', password: 'Guardia123' }));

    expect(res.status).toBe(201);
    expect(res.body.data.user.role).toBe('guard');
    expect(res.body.data.profile.shiftStart).toBe('08:00');
    expect(res.body.data.profile.coverageCenter).toBeNull();

    // La contraseña elegida por el admin funciona.
    const entrando = await login(env.app, 'guardia@nuevo.test', 'Guardia123');
    expect(entrando.status).toBe(200);
  });

  it('un correo repetido en el alta da EMAIL_TAKEN', async () => {
    const token = await comoAdmin();
    await alta(token, nuevo({ email: 'guardia@nuevo.test' }));
    const repetido = await alta(token, nuevo({ email: 'guardia@nuevo.test' }));

    expect(repetido.status).toBe(409);
    expect(repetido.body.error.code).toBe('EMAIL_TAKEN');
  });

  it('solo el administrador entra a la gestión de guardias', async () => {
    for (const quien of ['protegido', 'guardia'] as const) {
      const sesion = await login(env.app, env.usuarios[quien].email);
      const res = await request(env.app.server)
        .get(`${API}/admin/guards`)
        .query({ search: '' })
        .set(conToken(sesion.body.data.accessToken as string));
      expect(res.status, quien).toBe(403);
    }
  });

  it('la edición se refleja al volver a consultar al guardia', async () => {
    const token = await comoAdmin();
    const creado = await alta(token, nuevo({ email: 'guardia@nuevo.test' }));
    const id = creado.body.data.user.id as string;

    const editado = await request(env.app.server)
      .patch(`${API}/admin/guards/${id}`)
      .set(conToken(token))
      .send({ name: 'Carlos Hernández Editado', phone: '7779998877' });

    expect(editado.status).toBe(200);
    expect(editado.body.data.user.name).toBe('Carlos Hernández Editado');

    const releido = await request(env.app.server).get(`${API}/admin/guards/${id}`).set(conToken(token));
    expect(releido.body.data.user.phone).toBe('7779998877');
  });

  it('la baja es lógica: cierra el acceso pero conserva al guardia', async () => {
    const token = await comoAdmin();
    const creado = await alta(token, nuevo({ email: 'guardia@nuevo.test', password: 'Guardia123' }));
    const id = creado.body.data.user.id as string;

    const baja = await request(env.app.server).delete(`${API}/admin/guards/${id}`).set(conToken(token));
    expect(baja.status).toBe(200);
    expect(baja.body.data).toBeNull();

    // Ya no entra...
    const intento = await login(env.app, 'guardia@nuevo.test', 'Guardia123');
    expect(intento.status).toBe(401);
    expect(intento.body.error.code).toBe('INVALID_CREDENTIALS');

    // ...pero sigue en el listado, con isActive en false.
    const listado = await request(env.app.server).get(`${API}/admin/guards`).query({ search: '' }).set(conToken(token));
    const encontrado = (listado.body.data as { user: { id: string; isActive: boolean } }[]).find((g) => g.user.id === id);
    expect(encontrado?.user.isActive).toBe(false);
  });

  it('un id que no existe o que no es guardia da NOT_FOUND', async () => {
    const token = await comoAdmin();
    const ajeno = env.usuarios.protegido.id; // existe, pero no es guardia
    for (const id of ['00000000-0000-4000-8000-000000000000', ajeno]) {
      const res = await request(env.app.server).get(`${API}/admin/guards/${id}`).set(conToken(token));
      expect(res.status, id).toBe(404);
      expect(res.body.error.message).toBe('No encontramos a ese guardia');
    }
  });
});
