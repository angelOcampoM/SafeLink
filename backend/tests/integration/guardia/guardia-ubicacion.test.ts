// BE-04 paso 2 · PUT /guard/location contra PostgreSQL real (G-06, D31, D27).
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
// El límite de frecuencia (429) y los logs están en guardia-ubicacion-limite.test.ts: usan
// otra configuración y crearEntorno toma un bloqueo exclusivo de la base de pruebas.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { etaSeconds, roundEtaUp } from '../../../src/domain/alert-rules.js';
import { snapToGrid } from '../../../src/domain/geo.js';
import {
  alertTopic,
  alertsTopicForUser,
  createMemoryEventBus,
  dispatchTopic,
  guardTopic,
  type EventBus,
} from '../../../src/realtime/event-bus.js';
import { MSG_UNAUTHORIZED, PASSWORD, configPrueba, crearEntorno, hasherPrueba, login, type Entorno } from '../auth/helpers.js';
import { correoUnico, crearAlerta, crearUsuario } from '../db/helpers.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

const API = '/api/v1';
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const CENTRO = { lat: 18.84, lng: -99.18 };
const NUEVA = { lat: 18.85, lng: -99.17 };

let env: Entorno;
let tokenGuardia: string;
const abiertas: ConexionSse[] = [];

const token = async (email: string): Promise<string> => {
  const res = await login(env.app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
};
const put = (cuerpo: unknown, t: string | null = tokenGuardia) => {
  const r = request(env.app.server).put(`${API}/guard/location`);
  return (t === null ? r : r.set('Authorization', `Bearer ${t}`)).send(cuerpo as object);
};
const crudo = (texto: string, t: string = tokenGuardia) =>
  request(env.app.server)
    .put(`${API}/guard/location`)
    .set('Authorization', `Bearer ${t}`)
    .set('content-type', 'application/json')
    .send(texto);

async function perfil(): Promise<void> {
  const base = {
    shiftStart: '00:00', shiftEnd: '00:00', coverageCenterLat: CENTRO.lat, coverageCenterLng: CENTRO.lng,
    coverageRadiusMeters: 1000, zone: 'Zona Centro', lastLocationLat: null, lastLocationLng: null, lastLocationAt: null,
  };
  await env.prisma.guardProfile.upsert({
    where: { userId: env.usuarios.guardia.id },
    create: { userId: env.usuarios.guardia.id, ...base },
    update: base,
  });
}
const leerPerfil = () => env.prisma.guardProfile.findUniqueOrThrow({ where: { userId: env.usuarios.guardia.id } });

beforeAll(async () => {
  env = await crearEntorno();
}, 120_000);
afterAll(async () => {
  for (const c of abiertas) c.cerrar();
  await env.cerrar();
});
beforeEach(async () => {
  for (const c of abiertas.splice(0)) c.cerrar();
  await env.prisma.alert.deleteMany();
  await perfil();
  tokenGuardia = await token(env.usuarios.guardia.email);
});

describe('PUT /guard/location: éxito (G-06)', () => {
  it('200 { data: null }, guarda lat/lng y la hora del servidor, y GET /guard/me la refleja', async () => {
    const antes = Date.now();
    const res = await put({ location: NUEVA });
    const despues = Date.now();
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });

    const p = await leerPerfil();
    expect(p.lastLocationLat).toBeCloseTo(NUEVA.lat, 9);
    expect(p.lastLocationLng).toBeCloseTo(NUEVA.lng, 9);
    expect(p.lastLocationAt).not.toBeNull();
    const t = p.lastLocationAt?.getTime() ?? 0;
    expect(t).toBeGreaterThanOrEqual(antes - 2000);
    expect(t).toBeLessThanOrEqual(despues + 2000);

    const me = await request(env.app.server).get(`${API}/guard/me`).set('Authorization', `Bearer ${tokenGuardia}`);
    expect(me.status).toBe(200);
    expect(me.body.data.profile.lastLocation).toEqual(NUEVA);
    expect(new Date(me.body.data.profile.lastLocationAt as string).getTime()).toBe(t);
  });

  it('la hora es la del servidor: un lastLocationAt enviado por el cliente se rechaza (campo no permitido)', async () => {
    const res = await put({ location: NUEVA, lastLocationAt: '2000-01-01T00:00:00Z' });
    expect(res.status).toBe(400);
    expect((await leerPerfil()).lastLocationAt).toBeNull();
  });

  it('una segunda ubicación sobrescribe la primera', async () => {
    await put({ location: NUEVA });
    expect((await put({ location: CENTRO })).status).toBe(200);
    const p = await leerPerfil();
    expect({ lat: p.lastLocationLat, lng: p.lastLocationLng }).toEqual(CENTRO);
  });

  it.each([
    [{ lat: 90, lng: 180 }], [{ lat: -90, lng: -180 }], [{ lat: 0, lng: 0 }],
  ])('bordes válidos %j -> 200', async (location) => {
    expect((await put({ location })).status).toBe(200);
  });

  it('funciona fuera de turno (no exige turno)', async () => {
    // Turno de una hora que empieza dentro de 10 h (UTC): fuera de turno a cualquier hora y en cualquier zona.
    const h = (d: number) => {
      const x = new Date(Date.now() + d * 3_600_000);
      return `${String(x.getUTCHours()).padStart(2, '0')}:00`;
    };
    await env.prisma.guardProfile.update({
      where: { userId: env.usuarios.guardia.id },
      data: { shiftStart: h(10), shiftEnd: h(11) },
    });
    expect((await put({ location: NUEVA })).status).toBe(200);
    expect((await leerPerfil()).lastLocationLat).toBeCloseTo(NUEVA.lat, 9);
  });

  it('la respuesta no contiene coordenadas ni passwordHash', async () => {
    const res = await put({ location: { lat: 18.123456, lng: -99.654321 } });
    expect(res.text).not.toContain('18.123456');
    expect(res.text).not.toContain('99.654321');
    expect(res.text).not.toMatch(/passwordHash|hash/i);
    expect(Object.keys(res.body)).toEqual(['data']);
  });
});

describe('PUT /guard/location: validación (400)', () => {
  it.each([
    ['lat 90.0001', { location: { lat: 90.0001, lng: 0 } }],
    ['lat -90.0001', { location: { lat: -90.0001, lng: 0 } }],
    ['lng 180.0001', { location: { lat: 0, lng: 180.0001 } }],
    ['lng -180.0001', { location: { lat: 0, lng: -180.0001 } }],
    ['lat string', { location: { lat: '18.84', lng: -99.18 } }],
    ['lng string', { location: { lat: 18.84, lng: '-99.18' } }],
    ['lat null', { location: { lat: null, lng: -99.18 } }],
    ['lng null', { location: { lat: 18.84, lng: null } }],
    ['location null', { location: null }],
    ['location string', { location: '18.84,-99.18' }],
    ['falta lng', { location: { lat: 18.84 } }],
    ['falta lat', { location: { lng: -99.18 } }],
    ['location vacío', { location: {} }],
    ['booleanos', { location: { lat: true, lng: false } }],
  ])('%s -> 400 INVALID_STATE y no guarda nada', async (_n, cuerpo) => {
    const res = await put(cuerpo);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: { code: 'INVALID_STATE', message: expect.any(String) } });
    expect((await leerPerfil()).lastLocationAt).toBeNull();
  });

  it('fuera de rango con el mensaje propio del esquema', async () => {
    const res = await put({ location: { lat: 91, lng: 0 } });
    expect(res.body).toEqual({ error: { code: 'INVALID_STATE', message: 'La ubicación no es válida' } });
  });

  it('1e999 (infinito al parsear) -> 400', async () => {
    const res = await crudo('{"location":{"lat":1e999,"lng":0}}');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect((await leerPerfil()).lastLocationAt).toBeNull();
  });

  it.each([
    ['clave extra en la raíz', { location: NUEVA, extra: 1 }],
    ['clave extra dentro de location', { location: { ...NUEVA, alt: 5 } }],
    ['cuerpo plano {lat,lng}', NUEVA],
    ['cuerpo vacío {}', {}],
    ['arreglo', [NUEVA]],
  ])('%s -> 400', async (_n, cuerpo) => {
    const res = await put(cuerpo);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: { code: 'INVALID_STATE', message: expect.any(String) } });
    expect(Object.keys(res.body)).toEqual(['error']);
    expect((await leerPerfil()).lastLocationAt).toBeNull();
  });

  it('sin cuerpo y con JSON malformado -> 400', async () => {
    const sin = await request(env.app.server).put(`${API}/guard/location`).set('Authorization', `Bearer ${tokenGuardia}`);
    expect(sin.status).toBe(400);
    expect(sin.body.error.code).toBe('INVALID_STATE');
    const mal = await crudo('{"location": ');
    expect(mal.status).toBe(400);
    expect(mal.body.error.code).toBe('INVALID_STATE');
  });

  it('__proto__ en el cuerpo -> 400 y no guarda nada', async () => {
    const res = await crudo('{"__proto__":{"x":1},"location":{"lat":1,"lng":1}}');
    expect(res.status).toBe(400);
    expect((await leerPerfil()).lastLocationAt).toBeNull();
  });
});

describe('PUT /guard/location: permisos y recurso (401, 403, 404)', () => {
  it('sin token -> 401 con el envoltorio', async () => {
    const res = await put({ location: NUEVA }, null);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it('token basura -> 401', async () => {
    expect((await put({ location: NUEVA }, 'no.es.jwt')).status).toBe(401);
  });

  it.each(['protegido', 'admin'] as const)('rol %s -> 403 FORBIDDEN y no toca el perfil del guardia', async (quien) => {
    const res = await put({ location: NUEVA }, await token(env.usuarios[quien].email));
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    expect((await leerPerfil()).lastLocationAt).toBeNull();
  });

  it('rol incorrecto con cuerpo inválido -> 403, no 400 (el permiso va primero)', async () => {
    const res = await put({ nada: true }, await token(env.usuarios.admin.email));
    expect(res.status).toBe(403);
  });

  it('guardia sin perfil -> 404 NOT_FOUND', async () => {
    const email = correoUnico('sinperfil');
    const g = await crearUsuario(env.prisma, { role: 'guard', email, passwordHash: await hasherPrueba.hash(PASSWORD) });
    const res = await put({ location: NUEVA }, await token(email));
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
    expect(Object.keys(res.body)).toEqual(['error']);
    expect(await env.prisma.guardProfile.findUnique({ where: { userId: g.id } })).toBeNull();
  });

  it('un guardia solo modifica su propio perfil', async () => {
    const otro = await crearUsuario(env.prisma, { role: 'guard' });
    await env.prisma.guardProfile.create({ data: { userId: otro.id, shiftStart: '00:00', shiftEnd: '00:00' } });
    await put({ location: NUEVA });
    const p = await env.prisma.guardProfile.findUniqueOrThrow({ where: { userId: otro.id } });
    expect(p.lastLocationAt).toBeNull();
    expect(p.lastLocationLat).toBeNull();
  });
});

describe('PUT /guard/location: D31, el dueño de la alerta en curso recibe el ETA nuevo', () => {
  it('con alerta in_progress, el canal alerts/active del dueño recibe un snapshot con etaSeconds actualizado', async () => {
    await crearAlerta(env.prisma, env.usuarios.protegido.id, {
      status: 'in_progress', guardId: env.usuarios.guardia.id, lat: CENTRO.lat, lng: CENTRO.lng, acceptedAt: new Date(),
    });
    const c = await abrirSse(env.app, `${API}/events/alerts/active`, await token(env.usuarios.protegido.email));
    abiertas.push(c);
    const inicial = (await c.siguiente()) as { data: { status: string; etaSeconds: number | null } };
    expect(inicial.data.status).toBe('in_progress');
    expect(inicial.data.etaSeconds).toBeNull(); // el guardia aún no reporta ubicación

    expect((await put({ location: NUEVA })).status).toBe(200);
    const e = (await c.siguiente()) as { data: { etaSeconds: number | null; status: string } };
    const { ETA_ROUNDING_SECONDS: paso, ETA_GUARD_GRID_METERS: celda, GUARD_METERS_PER_MINUTE: ritmo } = configPrueba();
    const exacto = etaSeconds('in_progress', NUEVA, CENTRO, ritmo);
    expect(exacto).toBeGreaterThan(0);
    expect(e.data.status).toBe('in_progress');
    // D47: el dueño ve el ETA de la posición ajustada al centro de la celda, redondeado hacia arriba, no el exacto.
    const esperado = roundEtaUp(etaSeconds('in_progress', snapToGrid(NUEVA, celda), CENTRO, ritmo), paso) as number;
    expect(esperado % paso).toBe(0);
    expect(e.data.etaSeconds).not.toBe(exacto); // el caso sirve: el exacto no coincide
    expect(e.data.etaSeconds).toBe(esperado);

    // Un segundo movimiento (más cerca) vuelve a publicar, con un ETA menor.
    expect((await put({ location: { lat: 18.8402, lng: -99.18 } })).status).toBe(200);
    const e2 = (await c.siguiente()) as { data: { etaSeconds: number } };
    const cerca = etaSeconds('in_progress', snapToGrid({ lat: 18.8402, lng: -99.18 }, celda), CENTRO, ritmo);
    expect(e2.data.etaSeconds).toBe(roundEtaUp(cerca, paso));
    expect(e2.data.etaSeconds).toBeLessThan(esperado);
  });

  describe('con un bus espía', () => {
    let publicados: string[];
    let espia: ReturnType<typeof buildApp>;
    let tokenEspia: string;

    beforeAll(async () => {
      publicados = [];
      const real: EventBus = createMemoryEventBus();
      const bus: EventBus = {
        publish: (topic) => {
          publicados.push(topic);
          real.publish(topic);
        },
        subscribe: (topic, l) => real.subscribe(topic, l),
      };
      espia = buildApp(configPrueba(), { prisma: env.prisma, bus });
      await espia.ready();
    });
    afterAll(async () => {
      await espia.close();
    });
    beforeEach(async () => {
      publicados.length = 0;
      tokenEspia = (await login(espia, env.usuarios.guardia.email)).body.data.accessToken as string;
    });
    const putEspia = (cuerpo: unknown) =>
      request(espia.server).put(`${API}/guard/location`).set('Authorization', `Bearer ${tokenEspia}`).send(cuerpo as object);

    // Desde BE-04 paso 3, PUT /guard/location publica SIEMPRE guardTopic(guardId): el propio guardia
    // reordena su listado (D34). Lo que no debe pasar es avisar a un dueño, al despacho global ni
    // a un tema de alerta.
    const soloElGuardia = (): string[] => [guardTopic(env.usuarios.guardia.id)];
    const sinAvisosAjenos = (): void => {
      expect(publicados.filter((t) => t.startsWith('alerts:user:'))).toEqual([]);
      expect(publicados).not.toContain(dispatchTopic);
      expect(publicados.filter((t) => t.startsWith('alert:'))).toEqual([]);
      expect(publicados).toEqual(soloElGuardia());
    };

    it('sin alertas -> no avisa a ningún dueño ni al despacho; solo publica el tema del guardia', async () => {
      expect((await putEspia({ location: NUEVA })).status).toBe(200);
      sinAvisosAjenos();
    });

    it.each(['searching', 'guard_arrived', 'closed', 'no_response', 'escalated', 'pending_location'] as const)(
      'alerta en %s (no in_progress) -> no avisa a ningún dueño; solo publica el tema del guardia',
      async (status) => {
        const alerta = await crearAlerta(env.prisma, env.usuarios.protegido.id, {
          status,
          guardId: ['guard_arrived', 'closed', 'escalated'].includes(status) ? env.usuarios.guardia.id : null,
        });
        expect((await putEspia({ location: NUEVA })).status).toBe(200);
        sinAvisosAjenos();
        expect(publicados).not.toContain(alertsTopicForUser(env.usuarios.protegido.id));
        expect(publicados).not.toContain(alertTopic(alerta.id));
      },
    );

    it('una alerta in_progress de OTRO guardia -> no avisa a ningún dueño; solo publica el tema del guardia', async () => {
      const otro = await crearUsuario(env.prisma, { role: 'guard' });
      await crearAlerta(env.prisma, env.usuarios.protegido.id, { status: 'in_progress', guardId: otro.id, acceptedAt: new Date() });
      expect((await putEspia({ location: NUEVA })).status).toBe(200);
      sinAvisosAjenos();
      expect(publicados).not.toContain(guardTopic(otro.id));
    });

    it('una alerta in_progress propia publica una vez al dueño y una vez el tema del guardia, nada más', async () => {
      await crearAlerta(env.prisma, env.usuarios.protegido.id, {
        status: 'in_progress', guardId: env.usuarios.guardia.id, acceptedAt: new Date(),
      });
      expect((await putEspia({ location: NUEVA })).status).toBe(200);
      expect(publicados).toHaveLength(2);
      expect(publicados.filter((t) => t === alertsTopicForUser(env.usuarios.protegido.id))).toHaveLength(1);
      expect(publicados.filter((t) => t === guardTopic(env.usuarios.guardia.id))).toHaveLength(1);
      expect(publicados).not.toContain(dispatchTopic);
    });

    it('si el cuerpo es inválido, no se publica ni se guarda', async () => {
      await crearAlerta(env.prisma, env.usuarios.protegido.id, {
        status: 'in_progress', guardId: env.usuarios.guardia.id, acceptedAt: new Date(),
      });
      expect((await putEspia({ location: { lat: 100, lng: 0 } })).status).toBe(400);
      expect(publicados).toEqual([]);
    });
  });
});

describe('regresión: POST /alerts/:id/locations sigue validando igual', () => {
  it('mismo esquema compartido: rango, clave extra y cuerpo plano -> 400; válido -> 200; guardia -> 403', async () => {
    const tu = await token(env.usuarios.protegido.email);
    const a = await crearAlerta(env.prisma, env.usuarios.protegido.id, { status: 'searching' });
    const enviar = (cuerpo: unknown) =>
      request(env.app.server).post(`${API}/alerts/${a.id}/locations`).set('Authorization', `Bearer ${tu}`).send(cuerpo as object);
    expect((await enviar({ location: { lat: 91, lng: 0 } })).status).toBe(400);
    expect((await enviar({ location: NUEVA, extra: 1 })).status).toBe(400);
    expect((await enviar(NUEVA)).status).toBe(400);
    expect((await enviar({ location: NUEVA })).status).toBe(200);
    const rg = await request(env.app.server)
      .post(`${API}/alerts/${a.id}/locations`).set('Authorization', `Bearer ${tokenGuardia}`).send({ location: NUEVA });
    expect(rg.status).toBe(403);
  });
});
