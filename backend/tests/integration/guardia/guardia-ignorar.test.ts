// BE-04 paso 6 · POST /guard/alerts/:id/ignore contra PostgreSQL real: G-03 (extra del front),
// D22 (404 idéntico), D36 (una en curso por guardia), D39 (alert_ignores), D40, D34.
//
// NOTA: necesita DATABASE_URL_TEST. SSE_PING_SECONDS = 60: ningún snapshot llega por el ping dentro
// de una prueba, así que todo lo que un stream recibe llegó por el aviso inmediato del bus.
import request from 'supertest';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../../src/app.js';
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
const ZONA = 'America/Mexico_City';
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const CUERPO_404 = { error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } };
const UUID_INEXISTENTE = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
const CENTRO = { lat: 18.84, lng: -99.18 };
const FUERA = { lat: 18.95, lng: -99.18 };

let env: Entorno;
let passwordHash: string;
let tokenGuardia: string;
let tokenProtegido: string;
let tokenAdmin: string;
const abiertas: ConexionSse[] = [];

function horaLocal(minutos: number): string {
  const partes = new Intl.DateTimeFormat('en-US', { timeZone: ZONA, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(Date.now() + minutos * 60_000));
  const h = partes.find((p) => p.type === 'hour')?.value ?? '00';
  const m = partes.find((p) => p.type === 'minute')?.value ?? '00';
  return `${h === '24' ? '00' : h}:${m}`;
}
const FUERA_DE_TURNO = () => ({ shiftStart: horaLocal(120), shiftEnd: horaLocal(180) });

interface Cuenta { id: string; email: string; token: string }

async function tokenDe(email: string, app = env.app): Promise<string> {
  const res = await login(app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
}

async function crearGuardia(): Promise<Cuenta> {
  const email = correoUnico('ign');
  const u = await crearUsuario(env.prisma, { role: 'guard', email, passwordHash });
  await env.prisma.guardProfile.create({
    data: {
      userId: u.id, shiftStart: '00:00', shiftEnd: '00:00',
      coverageCenterLat: CENTRO.lat, coverageCenterLng: CENTRO.lng, coverageRadiusMeters: 2000,
    },
  });
  return { id: u.id, email, token: await tokenDe(email) };
}

async function perfil(datos: Record<string, unknown> = {}): Promise<void> {
  const base = {
    shiftStart: '00:00', shiftEnd: '00:00',
    coverageCenterLat: CENTRO.lat, coverageCenterLng: CENTRO.lng, coverageRadiusMeters: 1000,
    zone: 'Zona Centro', lastLocationLat: null, lastLocationLng: null, lastLocationAt: null,
    ...datos,
  };
  await env.prisma.guardProfile.upsert({
    where: { userId: env.usuarios.guardia.id },
    create: { userId: env.usuarios.guardia.id, ...base },
    update: base,
  });
}

const llamar = (id: string, token?: string) => {
  const r = request(env.app.server).post(`${API}/guard/alerts/${id}/ignore`);
  return token === undefined ? r : r.set('Authorization', `Bearer ${token}`);
};
const ignorar = (id: string, token: string = tokenGuardia) => llamar(id, token);
const verAlerta = (id: string, token: string = tokenGuardia) =>
  request(env.app.server).get(`${API}/guard/alerts/${id}`).set('Authorization', `Bearer ${token}`);
const aceptar = (id: string, token: string = tokenGuardia) =>
  request(env.app.server).post(`${API}/guard/alerts/${id}/accept`).set('Authorization', `Bearer ${token}`);

const guardiaId = () => env.usuarios.guardia.id;
const nuevoDueno = () => crearUsuario(env.prisma, { passwordHash });
async function buscando(extra: Record<string, unknown> = {}) {
  return crearAlerta(env.prisma, (await nuevoDueno()).id, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng, ...extra });
}
const filas = () => env.prisma.alertIgnore.findMany();

beforeAll(async () => {
  env = await crearEntorno({ SSE_PING_SECONDS: '60' });
  passwordHash = await hasherPrueba.hash(PASSWORD);
  await new Promise<void>((resolve) => env.app.server.listen(0, '127.0.0.1', resolve));
  tokenProtegido = await tokenDe(env.usuarios.protegido.email);
  tokenAdmin = await tokenDe(env.usuarios.admin.email);
}, 120_000);

afterAll(async () => {
  await env.cerrar();
});

beforeEach(async () => {
  await env.prisma.alertIgnore.deleteMany();
  await env.prisma.alert.deleteMany();
  await env.prisma.user.update({ where: { id: guardiaId() }, data: { isActive: true } });
  await perfil();
  tokenGuardia = await tokenDe(env.usuarios.guardia.email);
});

afterEach(() => {
  for (const s of abiertas.splice(0)) s.cerrar();
});

describe('POST /guard/alerts/:id/ignore: éxito (G-03)', () => {
  it('200 {data:null}, una fila (guardId, alertId); el segundo ignore es 200 y sigue una sola fila', async () => {
    const a = await buscando();
    const res = await ignorar(a.id);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
    expect(await filas()).toMatchObject([{ guardId: guardiaId(), alertId: a.id }]);
    const otra = await ignorar(a.id);
    expect(otra.status).toBe(200);
    expect(otra.body).toEqual({ data: null });
    expect(await filas()).toHaveLength(1);
  });

  it('no modifica la alerta (sigue searching, sin guardia, sin historial)', async () => {
    const a = await buscando();
    expect((await ignorar(a.id)).status).toBe(200);
    const e = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
    expect(e.status).toBe('searching');
    expect(e.guardId).toBeNull();
    expect(await env.prisma.alertStatusHistory.count({ where: { alertId: a.id } })).toBe(0);
  });
});

describe('POST /guard/alerts/:id/ignore: desaparece solo para ese guardia', () => {
  it('GET del que ignoró -> 404 idéntico; otro guardia con cobertura la sigue viendo (GET y listado SSE)', async () => {
    const otro = await crearGuardia();
    const a = await buscando();
    expect((await ignorar(a.id)).status).toBe(200);
    const propio = await verAlerta(a.id);
    expect(propio.status).toBe(404);
    expect(propio.body).toEqual(CUERPO_404);
    const ajeno = await verAlerta(a.id, otro.token);
    expect(ajeno.status).toBe(200);
    expect(ajeno.body.data.id).toBe(a.id);

    const s = await abrirSse(env.app, `${API}/events/guard/alerts`, otro.token);
    abiertas.push(s);
    const lista = (await s.siguiente()) as { data: Array<{ alert: { id: string } }> };
    expect(lista.data.map((i) => i.alert.id)).toEqual([a.id]);
  });

  it('el propio guardia no la ve en su listado SSE inicial después de ignorar', async () => {
    const a = await buscando();
    expect((await ignorar(a.id)).status).toBe(200);
    const s = await abrirSse(env.app, `${API}/events/guard/alerts`, tokenGuardia);
    abiertas.push(s);
    const lista = (await s.siguiente()) as { data: unknown[] };
    expect(lista.data).toEqual([]);
  });

  it('accept después de ignorar -> 404 idéntico y la alerta sigue sin asignar', async () => {
    const a = await buscando();
    expect((await ignorar(a.id)).status).toBe(200);
    const res = await aceptar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    const e = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
    expect(e.status).toBe('searching');
    expect(e.guardId).toBeNull();
  });
});

describe('POST /guard/alerts/:id/ignore: 404 idéntico (D22, D40)', () => {
  async function esperar404(id: string, token: string = tokenGuardia): Promise<void> {
    const res = await ignorar(id, token);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    expect(await filas()).toEqual([]);
  }

  it('UUID inválido', async () => {
    await esperar404('no-es-uuid');
  });
  it('UUID inexistente', async () => {
    await esperar404(UUID_INEXISTENTE);
  });
  it('fuera de radio', async () => {
    const a = await buscando({ lat: FUERA.lat, lng: FUERA.lng });
    await esperar404(a.id);
  });
  it('fuera de turno', async () => {
    await perfil(FUERA_DE_TURNO());
    const a = await buscando();
    await esperar404(a.id);
  });
  it('sin cobertura', async () => {
    await perfil({ coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null });
    const a = await buscando();
    await esperar404(a.id);
  });
  it('pending_location', async () => {
    const a = await buscando({ status: 'pending_location', lat: null, lng: null });
    await esperar404(a.id);
  });
  it('in_progress de otro guardia', async () => {
    const otro = await crearGuardia();
    const a = await buscando({ status: 'in_progress', guardId: otro.id, acceptedAt: new Date() });
    await esperar404(a.id);
  });
  it('guardia sin perfil', async () => {
    const email = correoUnico('sinperfil');
    await crearUsuario(env.prisma, { role: 'guard', email, passwordHash });
    const token = await tokenDe(email);
    const a = await buscando();
    await esperar404(a.id, token);
  });
  it('guardia de baja -> 401 (autenticación) sin filas nuevas', async () => {
    const a = await buscando();
    await env.prisma.user.update({ where: { id: guardiaId() }, data: { isActive: false } });
    const res = await ignorar(a.id);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
    expect(await filas()).toEqual([]);
  });
});

describe('POST /guard/alerts/:id/ignore: alerta propia asignada (D22, D36)', () => {
  it.each(['in_progress', 'guard_arrived'] as const)('%s propia -> 200, sin fila, sigue asignada y visible', async (status) => {
    const a = await buscando({ status, guardId: guardiaId(), acceptedAt: new Date() });
    const res = await ignorar(a.id);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
    expect(await filas()).toEqual([]);
    const e = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
    expect(e.status).toBe(status);
    expect(e.guardId).toBe(guardiaId());
    expect((await verAlerta(a.id)).status).toBe(200);
  });
});

describe('POST /guard/alerts/:id/ignore: permisos', () => {
  it('sin token -> 401, sin filas', async () => {
    const a = await buscando();
    const res = await llamar(a.id);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
    expect(await filas()).toEqual([]);
  });
  it('token inválido -> 401', async () => {
    const a = await buscando();
    expect((await llamar(a.id, 'token.invalido.x')).status).toBe(401);
    expect(await filas()).toEqual([]);
  });
  it.each(['protegido', 'admin'] as const)('%s -> 403, sin filas', async (quien) => {
    const a = await buscando();
    const res = await ignorar(a.id, quien === 'protegido' ? tokenProtegido : tokenAdmin);
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    expect(await filas()).toEqual([]);
  });
});

// ── Tiempo real (D34) ──────────────────────────────────────────────────

type Evento = { data?: unknown; error?: { code: string; message: string } };
type Lista = Array<{ alert: { id: string } }>;

async function esperarEvento(s: ConexionSse, pred: (e: Evento) => boolean, ms = 5000): Promise<Evento> {
  const limite = Date.now() + ms;
  let ultimo: unknown;
  while (Date.now() < limite) {
    ultimo = await s.siguiente(Math.max(50, limite - Date.now()));
    if (pred(ultimo as Evento)) return ultimo as Evento;
  }
  throw new Error(`Ningún evento cumplió la condición; último: ${JSON.stringify(ultimo)}`);
}
async function abrir(ruta: string, token: string): Promise<ConexionSse> {
  const s = await abrirSse(env.app, `${API}${ruta}`, token);
  abiertas.push(s);
  expect(s.status).toBe(200);
  return s;
}
/** Espera acotada: no debe llegar ningún evento (el ping es de 60 s, solo el bus podría traerlo). */
async function nadaNuevo(s: ConexionSse): Promise<void> {
  await expect(s.siguiente(500)).rejects.toThrow('No llegó ningún evento SSE');
}

describe('POST /guard/alerts/:id/ignore: tiempo real (D34)', () => {
  it('el que ignora, con guard/alerts abierto, recibe un snapshot sin la alerta', async () => {
    const a = await buscando();
    const s = await abrir('/events/guard/alerts', tokenGuardia);
    const inicial = (await s.siguiente()) as { data: Lista };
    expect(inicial.data.map((i) => i.alert.id)).toEqual([a.id]);
    expect((await ignorar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => Array.isArray(ev.data) && !(ev.data as Lista).some((i) => i.alert.id === a.id));
    expect(e.data).toEqual([]);
  });

  it('el que ignora, con guard/alerts/:id abierto, recibe NOT_FOUND y se cierra el stream', async () => {
    const a = await buscando();
    const s = await abrir(`/events/guard/alerts/${a.id}`, tokenGuardia);
    expect(((await s.siguiente()) as { data: { id: string } }).data.id).toBe(a.id);
    expect((await ignorar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => ev.error !== undefined);
    expect(e).toEqual(CUERPO_404);
    const limite = Date.now() + 3000;
    while (!s.cerrado() && Date.now() < limite) await new Promise((r) => setTimeout(r, 20));
    expect(s.cerrado()).toBe(true);
  });

  it('otro guardia con guard/alerts abierto no recibe nada por este ignore', async () => {
    const otro = await crearGuardia();
    const a = await buscando();
    const s = await abrir('/events/guard/alerts', otro.token);
    const inicial = (await s.siguiente()) as { data: Lista };
    expect(inicial.data.map((i) => i.alert.id)).toEqual([a.id]);
    expect((await ignorar(a.id)).status).toBe(200);
    await nadaNuevo(s);
  });

  it('el dueño con alerts/active no recibe evento nuevo', async () => {
    const dueno = await nuevoDueno();
    const a = await crearAlerta(env.prisma, dueno.id, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });
    const token = await tokenDe(dueno.email);
    const s = await abrir('/events/alerts/active', token);
    expect(((await s.siguiente()) as { data: { id: string } }).data.id).toBe(a.id);
    expect((await ignorar(a.id)).status).toBe(200);
    await nadaNuevo(s);
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
      tokenEspia = await tokenDe(env.usuarios.guardia.email, espia);
    });
    const ignorarEspia = (id: string) =>
      request(espia.server).post(`${API}/guard/alerts/${id}/ignore`).set('Authorization', `Bearer ${tokenEspia}`);

    it('ignorar publica exactamente [guardTopic(guardId)]', async () => {
      const a = await buscando();
      expect((await ignorarEspia(a.id)).status).toBe(200);
      expect(publicados).toEqual([guardTopic(guardiaId())]);
      expect(publicados).not.toContain(dispatchTopic);
      expect(publicados).not.toContain(alertTopic(a.id));
      expect(publicados).not.toContain(alertsTopicForUser(a.userId));
    });

    it('segundo ignore (ya existía): no publica nada y no duplica la fila', async () => {
      const a = await buscando();
      expect((await ignorarEspia(a.id)).status).toBe(200);
      publicados.length = 0;
      expect((await ignorarEspia(a.id)).status).toBe(200);
      // createMany con skipDuplicates no insertó nada: no hay nada que recalcular.
      expect(publicados).toEqual([]);
      expect(await filas()).toHaveLength(1);
    });

    it.each(['in_progress', 'guard_arrived'] as const)('alerta propia %s -> no publica nada', async (status) => {
      const a = await buscando({ status, guardId: guardiaId(), acceptedAt: new Date() });
      expect((await ignorarEspia(a.id)).status).toBe(200);
      expect(publicados).toEqual([]);
    });

    it('404 (inexistente y no visible) -> no publica nada', async () => {
      expect((await ignorarEspia(UUID_INEXISTENTE)).status).toBe(404);
      const lejos = await buscando({ lat: FUERA.lat, lng: FUERA.lng });
      expect((await ignorarEspia(lejos.id)).status).toBe(404);
      expect(publicados).toEqual([]);
    });
  });
});
