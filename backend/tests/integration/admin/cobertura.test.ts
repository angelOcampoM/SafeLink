// BE-06 · A-03 Cobertura del guardia (turno, centro, radio y zona) contra la base de pruebas.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { crearEntorno, login, type Entorno } from '../auth/helpers.js';

const API = '/api/v1';

let env: Entorno;
let adminToken = '';
let guardiaId = '';

const COBERTURA = {
  shiftStart: '22:00',
  shiftEnd: '06:00', // cruza medianoche a propósito (D1)
  center: { lat: 18.8512, lng: -99.2016 },
  radiusMeters: 4000,
  zone: 'Emiliano Zapata',
};

beforeAll(async () => {
  env = await crearEntorno();
  adminToken = (await login(env.app, env.usuarios.admin.email)).body.data.accessToken as string;
  guardiaId = env.usuarios.guardia.id;
}, 120_000);

afterAll(async () => {
  await env.cerrar();
});

/** Cada prueba parte de un perfil recién creado, sin cobertura definida. */
beforeEach(async () => {
  await env.prisma.guardProfile.deleteMany();
  await env.prisma.guardProfile.create({
    data: { userId: guardiaId, shiftStart: '08:00', shiftEnd: '16:00' },
  });
});

const poner = (id: string, body: unknown) =>
  request(env.app.server)
    .put(`${API}/admin/guards/${id}/coverage`)
    .set({ Authorization: `Bearer ${adminToken}` })
    .send(body as object);

describe('PUT /admin/guards/:id/coverage', () => {
  it('guarda turno, centro, radio y zona, y devuelve el guardia completo', async () => {
    const res = await poner(guardiaId, COBERTURA);
    expect(res.status).toBe(200);

    const perfil = res.body.data.profile as Record<string, unknown>;
    expect(perfil).toMatchObject({
      userId: guardiaId,
      shiftStart: '22:00',
      shiftEnd: '06:00',
      coverageCenter: { lat: 18.8512, lng: -99.2016 },
      coverageRadiusMeters: 4000,
      zone: 'Emiliano Zapata',
    });
    expect(res.body.data.user).toMatchObject({ id: guardiaId, role: 'guard' });
  });

  it('el radio viaja como entero, no como 4000.0 (el front lo castea con as int)', async () => {
    const res = await poner(guardiaId, COBERTURA);
    expect(Number.isInteger(res.body.data.profile.coverageRadiusMeters)).toBe(true);
  });

  it('lo guardado queda en la base y se ve en GET /admin/guards/:id', async () => {
    await poner(guardiaId, COBERTURA);
    const res = await request(env.app.server)
      .get(`${API}/admin/guards/${guardiaId}`)
      .set({ Authorization: `Bearer ${adminToken}` });
    expect(res.body.data.profile).toMatchObject({ zone: 'Emiliano Zapata', coverageRadiusMeters: 4000 });
  });

  it('se puede volver a definir: sobrescribe, no acumula', async () => {
    await poner(guardiaId, COBERTURA);
    const res = await poner(guardiaId, { ...COBERTURA, zone: 'Acapantzingo', radiusMeters: 1500 });
    expect(res.body.data.profile).toMatchObject({ zone: 'Acapantzingo', coverageRadiusMeters: 1500 });
  });

  it('la zona se guarda recortada', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, zone: '  Lomas  ' });
    expect(res.body.data.profile.zone).toBe('Lomas');
  });

  it('un turno de 24 h (inicio = fin) es válido (D1)', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, shiftStart: '00:00', shiftEnd: '00:00' });
    expect(res.status).toBe(200);
  });

  // ── Errores, en el orden del front: turno, radio y zona ──

  it('un turno con formato inválido es 400 con el mensaje del front', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, shiftStart: '25:00' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('Usa el formato HH:mm');
  });

  it.each(['8:00', '08:0', '0800', '08:60'])('el turno %s no vale', async (hora) => {
    const res = await poner(guardiaId, { ...COBERTURA, shiftStart: hora });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('Usa el formato HH:mm');
  });

  it('un radio por debajo del mínimo es 400 con el mínimo configurado', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, radiusMeters: 499 });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('El radio mínimo es de 500 m');
  });

  it('un radio por encima del máximo es 400 con el máximo configurado', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, radiusMeters: 10_001 });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('El radio máximo es de 10000 m');
  });

  it('el mínimo y el máximo exactos sí valen (el borde cuenta como dentro)', async () => {
    expect((await poner(guardiaId, { ...COBERTURA, radiusMeters: 500 })).status).toBe(200);
    expect((await poner(guardiaId, { ...COBERTURA, radiusMeters: 10_000 })).status).toBe(200);
  });

  it('una zona vacía o de solo espacios es 400 con el mensaje del front', async () => {
    for (const zone of ['', '   ']) {
      const res = await poner(guardiaId, { ...COBERTURA, zone });
      expect(res.status, zone).toBe(400);
      expect(res.body.error.message).toBe('Escribe la zona de cobertura');
    }
  });

  it('con turno Y radio malos contesta por el turno: el front muestra un error a la vez', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, shiftStart: 'xx', radiusMeters: 1 });
    expect(res.body.error.message).toBe('Usa el formato HH:mm');
  });

  it('con radio Y zona malos contesta por el radio', async () => {
    const res = await poner(guardiaId, { ...COBERTURA, radiusMeters: 1, zone: '' });
    expect(res.body.error.message).toBe('El radio mínimo es de 500 m');
  });

  it('nada se guarda cuando el cuerpo es inválido', async () => {
    await poner(guardiaId, { ...COBERTURA, radiusMeters: 1 });
    const perfil = await env.prisma.guardProfile.findUniqueOrThrow({ where: { userId: guardiaId } });
    expect(perfil.zone).toBeNull();
    expect(perfil.coverageRadiusMeters).toBeNull();
    expect(perfil.shiftStart).toBe('08:00'); // el turno inicial, intacto
  });

  // ── Quién existe y quién no ──

  it('un id que no es de un guardia es NOT_FOUND', async () => {
    const res = await poner(env.usuarios.protegido.id, COBERTURA);
    expect(res.status).toBe(404);
    expect(res.body.error.message).toBe('No encontramos a ese guardia');
  });

  it('un id que no existe es NOT_FOUND', async () => {
    const res = await poner('3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11', COBERTURA);
    expect(res.status).toBe(404);
  });

  it('un id mal formado es NOT_FOUND, no 400', async () => {
    const res = await poner('no-es-un-id', COBERTURA);
    expect(res.status).toBe(404);
  });

  it('NOT_FOUND gana al cuerpo inválido: primero se comprueba quién es', async () => {
    const res = await poner(env.usuarios.protegido.id, { ...COBERTURA, radiusMeters: 1 });
    expect(res.status).toBe(404);
  });

  // ── Para qué sirve: el despacho y las métricas ──

  it('la zona recién definida es la que agrupa las métricas generales', async () => {
    await poner(guardiaId, COBERTURA);
    await env.prisma.alert.create({
      data: {
        userId: env.usuarios.protegido.id,
        guardId: guardiaId,
        status: 'closed',
        triggerMethod: 'shake',
        triggeredAt: new Date('2026-03-01T18:00:00Z'),
        receivedAt: new Date('2026-03-01T18:00:00Z'),
        statusChangedAt: new Date('2026-03-01T18:00:00Z'),
      },
    });
    const res = await request(env.app.server)
      .get(`${API}/admin/metrics`)
      .set({ Authorization: `Bearer ${adminToken}` });
    expect(res.body.data.alertsByZone).toEqual([{ zone: 'Emiliano Zapata', count: 1 }]);
    await env.prisma.alert.deleteMany();
  });
});
