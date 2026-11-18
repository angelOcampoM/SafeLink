// BE-04 paso 7 · POST /guard/alerts/:id/arrive contra PostgreSQL real: G-07 (llegada con geocerca),
// D40 (404 idéntico), D47 (ETA redondeado para el dueño), K (el guardia no cierra la alerta), D34.
//
// NOTA: necesita DATABASE_URL_TEST. SSE_PING_SECONDS = 60: todo lo que el stream recibe llegó por el
// aviso inmediato. La concurrencia usa Promise.all contra la base real, sin pausas arbitrarias.
import request from 'supertest';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { etaSeconds, roundEtaUp } from '../../../src/domain/alert-rules.js';
import { haversineMeters, metersRemaining, snapToGrid } from '../../../src/domain/geo.js';
import {
  alertTopic,
  alertsTopicForUser,
  createMemoryEventBus,
  dispatchTopic,
  type EventBus,
} from '../../../src/realtime/event-bus.js';
import { ROUTE_POLICIES } from '../../../src/security/policies.js';
import {
  MSG_UNAUTHORIZED,
  PASSWORD,
  configPrueba,
  crearEntorno,
  hasherPrueba,
  login,
  type Entorno,
} from '../auth/helpers.js';
import { correoUnico, crearAlerta, crearUsuario } from '../db/helpers.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

const API = '/api/v1';
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const CUERPO_404 = { error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } };
const CUERPO_409 = { error: { code: 'INVALID_STATE', message: 'Esta alerta ya no está en atención' } };
const MSG_FUERA = 'Aún no estás en el punto de la alerta';
const UUID_INEXISTENTE = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
const CLAVES_ALERTA = [
  'acceptedAt', 'adminNote', 'arrivedAt', 'closedAt', 'escalationReason', 'etaSeconds', 'evidenceIncomplete',
  'guardId', 'guardName', 'heading', 'id', 'location', 'photoUrl', 'resolution', 'status', 'triggerMethod',
  'triggeredAt', 'userId', 'userName', 'userPhone',
].sort();

const GEOCERCA = configPrueba().GEOFENCE_METERS;
const PASO_ETA = configPrueba().ETA_ROUNDING_SECONDS;
const CELDA_ETA = configPrueba().ETA_GUARD_GRID_METERS;
const METROS_GUARDIA = configPrueba().GUARD_METERS_PER_MINUTE;

const CENTRO = { lat: 18.84, lng: -99.18 }; // ubicación de la alerta
const CERCA = { lat: 18.8402, lng: -99.18 }; // ~22 m
const LEJOS = { lat: 18.841, lng: -99.18 }; // ~111 m
const MUY_LEJOS = { lat: 18.95, lng: -99.18 };

/** Puntos justo en el borde de la geocerca respecto de CENTRO, por bisección sobre la latitud. */
function bordeGeocerca(): { dentro: { lat: number; lng: number }; fuera: { lat: number; lng: number } } {
  let lo = CENTRO.lat + 0.0003; // < GEOCERCA
  let hi = CENTRO.lat + 0.0006; // > GEOCERCA
  for (let i = 0; i < 200; i += 1) {
    const mid = (lo + hi) / 2;
    if (mid === lo || mid === hi) break;
    if (haversineMeters(CENTRO, { lat: mid, lng: CENTRO.lng }) <= GEOCERCA) lo = mid;
    else hi = mid;
  }
  return { dentro: { lat: lo, lng: CENTRO.lng }, fuera: { lat: hi, lng: CENTRO.lng } };
}

let env: Entorno;
let passwordHash: string;
let tokenGuardia: string;
let tokenProtegido: string;
let tokenAdmin: string;
const abiertas: ConexionSse[] = [];

interface Cuenta { id: string; email: string; token: string }

async function tokenDe(email: string, app = env.app): Promise<string> {
  const res = await login(app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
}

async function crearGuardia(): Promise<Cuenta> {
  const email = correoUnico('llega');
  const u = await crearUsuario(env.prisma, { role: 'guard', email, passwordHash, name: `Guardia ${email}` });
  await env.prisma.guardProfile.create({
    data: { userId: u.id, shiftStart: '00:00', shiftEnd: '00:00', lastLocationLat: CERCA.lat, lastLocationLng: CERCA.lng, lastLocationAt: new Date() },
  });
  return { id: u.id, email, token: await tokenDe(email) };
}

async function perfil(ubicacion: { lat: number; lng: number } | null): Promise<void> {
  const base = {
    shiftStart: '00:00', shiftEnd: '00:00',
    coverageCenterLat: CENTRO.lat, coverageCenterLng: CENTRO.lng, coverageRadiusMeters: 1000, zone: 'Zona Centro',
    lastLocationLat: ubicacion?.lat ?? null, lastLocationLng: ubicacion?.lng ?? null,
    lastLocationAt: ubicacion ? new Date() : null,
  };
  await env.prisma.guardProfile.upsert({
    where: { userId: env.usuarios.guardia.id },
    create: { userId: env.usuarios.guardia.id, ...base },
    update: base,
  });
}

const llegar = (id: string, token?: string, app = env.app) => {
  const r = request(app.server).post(`${API}/guard/alerts/${id}/arrive`);
  return token === undefined ? r : r.set('Authorization', `Bearer ${token}`);
};
const registrar = (id: string, token: string = tokenGuardia) => llegar(id, token);

const usuarioId = () => env.usuarios.protegido.id;
const guardiaId = () => env.usuarios.guardia.id;
/** Alerta propia del guardia principal, en curso por defecto y en CENTRO. */
const enCurso = (extra: Record<string, unknown> = {}) =>
  crearAlerta(env.prisma, usuarioId(), {
    status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, acceptedAt: new Date(), ...extra,
  });

async function estadoEnBase(id: string) {
  const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
  const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: id } });
  return { status: a.status, arrivedAt: a.arrivedAt, closedAt: a.closedAt, statusChangedAt: a.statusChangedAt, historial };
}
async function sinCambios(id: string, status = 'in_progress'): Promise<void> {
  const e = await estadoEnBase(id);
  expect(e.status).toBe(status);
  expect(e.arrivedAt).toBeNull();
  expect(e.historial).toHaveLength(0);
}

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
  await env.prisma.alert.deleteMany();
  await env.prisma.user.update({ where: { id: guardiaId() }, data: { isActive: true } });
  await perfil(CERCA);
  tokenGuardia = await tokenDe(env.usuarios.guardia.email);
});

afterEach(() => {
  for (const s of abiertas.splice(0)) s.cerrar();
});

// ── Éxito (G-07) ───────────────────────────────────────────────────────

describe('POST /guard/alerts/:id/arrive: éxito (G-07)', () => {
  it('200 dentro de la geocerca: 20 claves, guard_arrived, arrivedAt del servidor, etaSeconds null y teléfono visible', async () => {
    const a = await enCurso();
    const antes = Date.now();
    const res = await registrar(a.id);
    const despues = Date.now();
    expect(res.status).toBe(200);
    expect(Object.keys(res.body)).toEqual(['data']);
    const d = res.body.data as Record<string, unknown>;
    expect(Object.keys(d).sort()).toEqual(CLAVES_ALERTA);
    expect(d['id']).toBe(a.id);
    expect(d['status']).toBe('guard_arrived');
    expect(d['guardId']).toBe(guardiaId());
    expect(d['userId']).toBe(usuarioId());
    expect(d['userPhone']).toBe('7771234567');
    expect(d['location']).toEqual(CENTRO);
    expect(d['closedAt']).toBeNull();
    expect(d['etaSeconds']).toBeNull();
    expect(d['acceptedAt']).toBe(a.acceptedAt?.toISOString());
    const llego = Date.parse(d['arrivedAt'] as string);
    expect(llego).toBeGreaterThanOrEqual(antes - 1000);
    expect(llego).toBeLessThanOrEqual(despues + 1000);
    expect(new Date(llego).toISOString()).toBe(d['arrivedAt']);
  });

  it('el cuerpo de la petición se ignora: el servidor decide la hora y el estado', async () => {
    const a = await enCurso();
    const res = await request(env.app.server)
      .post(`${API}/guard/alerts/${a.id}/arrive`)
      .set('Authorization', `Bearer ${tokenGuardia}`)
      .send({ status: 'closed', arrivedAt: '2000-01-01T00:00:00.000Z', location: MUY_LEJOS });
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('guard_arrived');
    expect(Date.parse(res.body.data.arrivedAt as string)).toBeGreaterThan(Date.parse('2020-01-01T00:00:00.000Z'));
  });

  it('borde exacto: a GEOFENCE_METERS (distancia <= radio) cuenta como dentro', async () => {
    const { dentro, fuera } = bordeGeocerca();
    // El caso sirve: dentro está a lo sumo en el radio y el siguiente double ya está fuera.
    expect(haversineMeters(CENTRO, dentro)).toBeLessThanOrEqual(GEOCERCA);
    expect(haversineMeters(CENTRO, fuera)).toBeGreaterThan(GEOCERCA);
    expect(GEOCERCA - haversineMeters(CENTRO, dentro)).toBeLessThan(1e-6);
    await perfil(dentro);
    const a = await enCurso();
    const res = await registrar(a.id);
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('guard_arrived');
  });

  it('un instante fuera del borde (el siguiente double) es 422', async () => {
    const { fuera } = bordeGeocerca();
    await perfil(fuera);
    const a = await enCurso();
    const res = await registrar(a.id);
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('OUTSIDE_GEOFENCE');
    expect(res.body.error.remainingMeters).toBe(0); // 1 decimal: la sobra es de nanómetros
    await sinCambios(a.id);
  });

  it('en base: guard_arrived, arrivedAt = statusChangedAt y exactamente una fila de historial in_progress -> guard_arrived del guardia', async () => {
    const a = await enCurso();
    const res = await registrar(a.id);
    const e = await estadoEnBase(a.id);
    expect(e.status).toBe('guard_arrived');
    expect(e.closedAt).toBeNull();
    expect(e.arrivedAt?.toISOString()).toBe(res.body.data.arrivedAt);
    expect(e.statusChangedAt.toISOString()).toBe(res.body.data.arrivedAt);
    expect(e.historial).toHaveLength(1);
    expect(e.historial[0]).toMatchObject({ fromStatus: 'in_progress', toStatus: 'guard_arrived', actorId: guardiaId() });
    expect(e.historial[0]?.at.toISOString()).toBe(res.body.data.arrivedAt);
  });

  it('no toca la ubicación del guardia ni la de la alerta', async () => {
    const a = await enCurso();
    await registrar(a.id);
    const fila = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
    expect({ lat: fila.lat, lng: fila.lng }).toEqual(CENTRO);
    const p = await env.prisma.guardProfile.findUniqueOrThrow({ where: { userId: guardiaId() } });
    expect({ lat: p.lastLocationLat, lng: p.lastLocationLng }).toEqual(CERCA);
  });

  it('el dueño ve la alerta en guard_arrived con arrivedAt y puede confirmar (U-09)', async () => {
    const a = await enCurso();
    await registrar(a.id);
    const mine = await request(env.app.server).get(`${API}/alerts/mine`).set('Authorization', `Bearer ${tokenProtegido}`);
    const vista = (mine.body.data as Array<{ id: string; status: string; arrivedAt: string | null }>).find((x) => x.id === a.id);
    expect(vista?.status).toBe('guard_arrived');
    expect(vista?.arrivedAt).not.toBeNull();
    const conf = await request(env.app.server).post(`${API}/alerts/${a.id}/confirm`).set('Authorization', `Bearer ${tokenProtegido}`);
    expect(conf.status).toBe(200);
    expect(conf.body.data.status).toBe('closed');
  });
});

// ── 404 idéntico (D40) ─────────────────────────────────────────────────

describe('POST /guard/alerts/:id/arrive: 404 con cuerpo idéntico (D40)', () => {
  it('UUID inválido', async () => {
    const res = await registrar('no-es-un-uuid');
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
  });

  it('alerta inexistente', async () => {
    const res = await registrar(UUID_INEXISTENTE);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
  });

  it('in_progress de OTRO guardia dentro de la geocerca del mío: 404 y la alerta no cambia', async () => {
    const otro = await crearGuardia();
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'in_progress', guardId: otro.id, lat: CENTRO.lat, lng: CENTRO.lng });
    const res = await registrar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('in_progress de otro guardia FUERA de la geocerca: mismo 404, sin remainingMeters (no se filtra la distancia)', async () => {
    const otro = await crearGuardia();
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'in_progress', guardId: otro.id, lat: MUY_LEJOS.lat, lng: MUY_LEJOS.lng });
    const res = await registrar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    expect(JSON.stringify(res.body)).not.toContain('remainingMeters');
    await sinCambios(a.id);
  });

  it.each(['guard_arrived', 'closed', 'escalated'] as const)('%s de otro guardia: 404, nunca 409', async (status) => {
    const otro = await crearGuardia();
    const a = await crearAlerta(env.prisma, usuarioId(), { status, guardId: otro.id, lat: CENTRO.lat, lng: CENTRO.lng });
    const res = await registrar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    expect((await estadoEnBase(a.id)).status).toBe(status);
  });

  it('alerta searching visible para mí pero sin asignar: 404 (no es mía)', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });
    const res = await registrar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id, 'searching');
  });

  it('guardia sin perfil', async () => {
    const email = correoUnico('sinperfil');
    await crearUsuario(env.prisma, { role: 'guard', email, passwordHash });
    const a = await enCurso();
    const res = await registrar(a.id, await tokenDe(email));
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('guardia de baja: el token anterior ya no sirve, 401 y la alerta no cambia', async () => {
    const a = await enCurso();
    await env.prisma.user.update({ where: { id: guardiaId() }, data: { isActive: false } });
    const res = await registrar(a.id);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
    await sinCambios(a.id);
  });
});

// ── 409 INVALID_STATE ──────────────────────────────────────────────────

describe('POST /guard/alerts/:id/arrive: 409 INVALID_STATE en alertas propias que ya no están in_progress', () => {
  it.each(['guard_arrived', 'closed', 'escalated'] as const)('propia en %s (aunque esté fuera de la geocerca: el 409 va antes que el 422)', async (status) => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status, guardId: guardiaId(), lat: MUY_LEJOS.lat, lng: MUY_LEJOS.lng });
    const res = await registrar(a.id);
    expect(res.status).toBe(409);
    expect(res.body).toEqual(CUERPO_409);
    const e = await estadoEnBase(a.id);
    expect(e.status).toBe(status);
    expect(e.historial).toHaveLength(0);
  });

  it('un segundo arrive tras el primero: 409 y una sola fila de historial', async () => {
    const a = await enCurso();
    expect((await registrar(a.id)).status).toBe(200);
    const otra = await registrar(a.id);
    expect(otra.status).toBe(409);
    expect(otra.body).toEqual(CUERPO_409);
    expect((await estadoEnBase(a.id)).historial).toHaveLength(1);
  });
});

// ── 422 OUTSIDE_GEOFENCE ───────────────────────────────────────────────

describe('POST /guard/alerts/:id/arrive: 422 OUTSIDE_GEOFENCE', () => {
  it('fuera: remainingMeters = metersRemaining con 1 decimal y la alerta no cambia', async () => {
    await perfil(LEJOS);
    const a = await enCurso();
    const res = await registrar(a.id);
    expect(res.status).toBe(422);
    const esperado = Math.round(metersRemaining(LEJOS, CENTRO, GEOCERCA) * 10) / 10;
    expect(esperado).toBeGreaterThan(50);
    expect(res.body).toEqual({ error: { code: 'OUTSIDE_GEOFENCE', message: MSG_FUERA, remainingMeters: esperado } });
    expect(Number.isInteger(res.body.error.remainingMeters * 10)).toBe(true);
    await sinCambios(a.id);
  });

  it('muy lejos: la distancia restante es la distancia menos la geocerca', async () => {
    await perfil(MUY_LEJOS);
    const a = await enCurso();
    const res = await registrar(a.id);
    expect(res.status).toBe(422);
    expect(res.body.error.remainingMeters).toBe(Math.round((haversineMeters(MUY_LEJOS, CENTRO) - GEOCERCA) * 10) / 10);
  });

  it('sin lastLocation del guardia: 422 con remainingMeters null (el campo existe) y no cambia nada', async () => {
    await perfil(null);
    const a = await enCurso();
    const res = await registrar(a.id);
    expect(res.status).toBe(422);
    expect(res.body).toEqual({ error: { code: 'OUTSIDE_GEOFENCE', message: MSG_FUERA, remainingMeters: null } });
    expect('remainingMeters' in res.body.error).toBe(true);
    await sinCambios(a.id);
  });

  it('tras un 422 el guardia se acerca (PUT /guard/location) y el mismo arrive prospera', async () => {
    await perfil(LEJOS);
    const a = await enCurso();
    expect((await registrar(a.id)).status).toBe(422);
    const put = await request(env.app.server)
      .put(`${API}/guard/location`)
      .set('Authorization', `Bearer ${tokenGuardia}`)
      .send({ location: CERCA });
    expect(put.status).toBe(200);
    expect((await registrar(a.id)).status).toBe(200);
    expect((await estadoEnBase(a.id)).historial).toHaveLength(1);
  });
});

// ── Permisos ───────────────────────────────────────────────────────────

describe('POST /guard/alerts/:id/arrive: permisos', () => {
  it('sin token -> 401, la alerta no cambia', async () => {
    const a = await enCurso();
    const res = await llegar(a.id);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
    await sinCambios(a.id);
  });

  it('token basura -> 401', async () => {
    const a = await enCurso();
    expect((await llegar(a.id, 'no.es.jwt')).status).toBe(401);
    await sinCambios(a.id);
  });

  it.each(['protected_user', 'admin'] as const)('rol %s -> 403 FORBIDDEN, la alerta no cambia (ni siquiera el dueño)', async (rol) => {
    const a = await enCurso();
    const res = await llegar(a.id, rol === 'admin' ? tokenAdmin : tokenProtegido);
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    await sinCambios(a.id);
  });

  it('rol incorrecto con id inválido -> 403, no 404 (el permiso va primero)', async () => {
    expect((await llegar('no-es-un-uuid', tokenAdmin)).status).toBe(403);
  });
});

// ── K: el guardia no cierra la alerta ──────────────────────────────────

describe('K: el guardia no puede cerrar la alerta', () => {
  it('arrive deja guard_arrived, nunca closed ni closedAt', async () => {
    const a = await enCurso();
    const res = await registrar(a.id);
    expect(res.body.data.status).toBe('guard_arrived');
    expect(res.body.data.closedAt).toBeNull();
    expect((await estadoEnBase(a.id)).closedAt).toBeNull();
  });

  it.each(['in_progress', 'guard_arrived'] as const)('POST /alerts/:id/confirm con token de guardia sobre su alerta en %s -> 403 y no cambia', async (status) => {
    const a = await enCurso({ status, ...(status === 'guard_arrived' ? { arrivedAt: new Date() } : {}) });
    const res = await request(env.app.server).post(`${API}/alerts/${a.id}/confirm`).set('Authorization', `Bearer ${tokenGuardia}`);
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    const e = await estadoEnBase(a.id);
    expect(e.status).toBe(status);
    expect(e.closedAt).toBeNull();
  });

  const rutasDelGuardia = Object.entries(ROUTE_POLICIES)
    .filter(([clave, politica]) => /^(POST|PUT) /.test(clave) && Array.isArray(politica) && politica.includes('guard'))
    .map(([clave]) => clave);

  it('el recorrido sí encuentra las rutas de escritura del guardia (no queda vacío)', () => {
    expect(rutasDelGuardia).toEqual(expect.arrayContaining([
      'PUT /guard/location', 'POST /guard/alerts/:id/accept', 'POST /guard/alerts/:id/ignore', 'POST /guard/alerts/:id/arrive',
    ]));
  });

  it.each(['in_progress', 'guard_arrived'] as const)('ninguna ruta POST/PUT del rol guard cierra una alerta propia en %s', async (status) => {
    for (const clave of rutasDelGuardia) {
      await env.prisma.alert.deleteMany();
      const a = await enCurso({ status, ...(status === 'guard_arrived' ? { arrivedAt: new Date() } : {}) });
      const token = await tokenDe(env.usuarios.guardia.email);
      const ruta = clave.split(' ')[1]!.replace(':id', a.id);
      const metodo = clave.startsWith('PUT') ? 'put' : 'post';
      const cuerpo = clave === 'PUT /guard/location' ? { location: CERCA } : {};
      const res = await request(env.app.server)[metodo](`${API}${ruta}`).set('Authorization', `Bearer ${token}`).send(cuerpo);
      const fila = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
      expect(fila.status, `${clave} (${String(res.status)})`).not.toBe('closed');
      expect(fila.closedAt, clave).toBeNull();
      expect(fila.resolution, clave).toBeNull();
      expect(await env.prisma.alertStatusHistory.count({ where: { alertId: a.id, toStatus: 'closed' } }), clave).toBe(0);
    }
  });
});

// ── Concurrencia ───────────────────────────────────────────────────────

describe('POST /guard/alerts/:id/arrive: concurrencia', () => {
  it('10 rondas: dos arrive a la vez del mismo guardia -> exactamente un 200 y un 409, una sola fila de historial', async () => {
    for (let ronda = 0; ronda < 10; ronda += 1) {
      await env.prisma.alert.deleteMany();
      const a = await enCurso();
      const respuestas = await Promise.all([registrar(a.id), registrar(a.id)]);
      const detalle = `ronda ${String(ronda)}: ${JSON.stringify(respuestas.map((r) => [r.status, r.body.error?.code]))}`;
      expect(respuestas.map((r) => r.status).sort(), detalle).toEqual([200, 409]);
      const perdedora = respuestas.find((r) => r.status === 409);
      expect(perdedora?.body, detalle).toEqual(CUERPO_409);
      const fila = await estadoEnBase(a.id);
      expect(fila.status, detalle).toBe('guard_arrived');
      expect(fila.historial, detalle).toHaveLength(1);
      expect(fila.historial[0], detalle).toMatchObject({ fromStatus: 'in_progress', toStatus: 'guard_arrived', actorId: guardiaId() });
    }
  }, 120_000);
});

// ── Tiempo real (D34) ──────────────────────────────────────────────────

type Evento = { data?: unknown; error?: { code: string; message: string } };

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

describe('POST /guard/alerts/:id/arrive: tiempo real (D34)', () => {
  it('el dueño con alerts/active recibe guard_arrived con arrivedAt', async () => {
    const a = await enCurso();
    const s = await abrir('/events/alerts/active', tokenProtegido);
    const inicial = (await s.siguiente()) as { data: { status: string } };
    expect(inicial.data.status).toBe('in_progress');
    expect((await registrar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => (ev.data as { status?: string } | null)?.status === 'guard_arrived');
    expect(e.data).toMatchObject({ id: a.id, status: 'guard_arrived', guardId: guardiaId() });
    expect((e.data as { arrivedAt: string | null }).arrivedAt).not.toBeNull();
  });

  it('el guardia con guard/alerts/:id recibe guard_arrived con el teléfono del dueño', async () => {
    const a = await enCurso();
    const s = await abrir(`/events/guard/alerts/${a.id}`, tokenGuardia);
    const inicial = (await s.siguiente()) as { data: { status: string } };
    expect(inicial.data.status).toBe('in_progress');
    expect((await registrar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => (ev.data as { status?: string } | undefined)?.status === 'guard_arrived');
    expect(e.data).toMatchObject({ id: a.id, guardId: guardiaId(), userPhone: '7771234567', etaSeconds: null });
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
      await new Promise<void>((resolve) => espia.server.listen(0, '127.0.0.1', resolve));
    });
    afterAll(async () => {
      await espia.close();
    });
    beforeEach(async () => {
      tokenEspia = await tokenDe(env.usuarios.guardia.email, espia);
      publicados.length = 0;
    });

    it('éxito: publica el tema del dueño y el de la alerta, nunca el despacho', async () => {
      const a = await enCurso();
      expect((await llegar(a.id, tokenEspia, espia)).status).toBe(200);
      expect([...publicados].sort()).toEqual([alertsTopicForUser(usuarioId()), alertTopic(a.id)].sort());
      expect(publicados).not.toContain(dispatchTopic);
    });

    it.each([
      ['inexistente', () => Promise.resolve(UUID_INEXISTENTE)],
      ['ajena', async () => (await crearAlerta(env.prisma, usuarioId(), { status: 'in_progress', guardId: (await crearGuardia()).id, lat: CENTRO.lat, lng: CENTRO.lng })).id],
      ['propia en guard_arrived (409)', async () => (await enCurso({ status: 'guard_arrived', arrivedAt: new Date() })).id],
    ] as const)('4xx (%s): no publica nada', async (_nombre, crear) => {
      const id = await crear();
      publicados.length = 0;
      const res = await llegar(id, tokenEspia, espia);
      expect([404, 409]).toContain(res.status);
      expect(publicados).toEqual([]);
    });

    it('422 fuera de la geocerca: no publica nada', async () => {
      await perfil(LEJOS);
      const a = await enCurso();
      publicados.length = 0;
      expect((await llegar(a.id, tokenEspia, espia)).status).toBe(422);
      expect(publicados).toEqual([]);
    });
  });
});

// ── D47 de extremo a extremo ───────────────────────────────────────────

describe('D47: con ubicaciones falsas el dueño solo distingue la celda del guardia', () => {
  const GUARDIA_EN = { lat: 18.85, lng: -99.18 };
  // ~1112 m, ~1045 m y ~979 m del guardia: ETAs exactos no múltiplos del paso.
  const FALSAS = [
    { lat: 18.84, lng: -99.18 },
    { lat: 18.8406, lng: -99.18 },
    { lat: 18.8412, lng: -99.18 },
  ];
  const exactoPara = (p: { lat: number; lng: number }) => etaSeconds('in_progress', GUARDIA_EN, p, METROS_GUARDIA) as number;
  /** Lo que debe ver el dueño: ETA desde el centro de la celda del guardia, redondeado hacia arriba. */
  const paraDueno = (guardia: { lat: number; lng: number }, p: { lat: number; lng: number }) =>
    roundEtaUp(etaSeconds('in_progress', snapToGrid(guardia, CELDA_ETA), p, METROS_GUARDIA), PASO_ETA) as number;

  it('en GET /alerts/mine y alerts/active el etaSeconds del dueño siempre es múltiplo del paso; el guardia ve el exacto', async () => {
    await perfil(GUARDIA_EN);
    const a = await enCurso();

    const exactos = FALSAS.map(exactoPara);
    expect(new Set(exactos).size).toBe(exactos.length); // el guardia, sin redondeo, sí se triangularía
    for (const e of exactos) expect(e % PASO_ETA, `exacto ${String(e)}`).not.toBe(0);

    const vistos: number[] = [];
    for (const [i, p] of FALSAS.entries()) {
      const envio = await request(env.app.server)
        .post(`${API}/alerts/${a.id}/locations`)
        .set('Authorization', `Bearer ${tokenProtegido}`)
        .send({ location: p });
      expect(envio.status, `ubicación ${String(i)}`).toBe(200);

      const mine = await request(env.app.server).get(`${API}/alerts/mine`).set('Authorization', `Bearer ${tokenProtegido}`);
      const vista = (mine.body.data as Array<{ id: string; etaSeconds: number | null }>).find((x) => x.id === a.id);
      const eta = vista?.etaSeconds as number;
      expect(eta % PASO_ETA, `mine ${String(i)}`).toBe(0);
      expect(eta, `mine ${String(i)}`).toBe(paraDueno(GUARDIA_EN, p));
      expect(eta, `mine ${String(i)}`).not.toBe(exactos[i]);
      vistos.push(eta);

      const guardia = await request(env.app.server).get(`${API}/guard/alerts/${a.id}`).set('Authorization', `Bearer ${tokenGuardia}`);
      expect(guardia.status).toBe(200);
      expect(guardia.body.data.etaSeconds, `guardia ${String(i)}`).toBe(exactos[i]);
    }
    // Los exactos son tres valores distintos; el dueño ve menos valores distintos que el guardia.
    expect(new Set(vistos).size).toBeLessThan(new Set(exactos).size);

    const s = await abrir('/events/alerts/active', tokenProtegido);
    const inicial = (await s.siguiente()) as { data: { etaSeconds: number } };
    expect(inicial.data.etaSeconds % PASO_ETA).toBe(0);
    expect(inicial.data.etaSeconds).toBe(paraDueno(GUARDIA_EN, FALSAS[2] as { lat: number; lng: number }));
  });

  it('mitigación: con el guardia quieto, moverse dentro de su celda no cambia nada para el dueño pero sí para el guardia', async () => {
    const A = { lat: 18.85, lng: -99.18 };
    const B = { lat: 18.8504, lng: -99.1803 };
    expect(snapToGrid(A, CELDA_ETA)).toEqual(snapToGrid(B, CELDA_ETA)); // el caso sirve: misma celda
    await perfil(A);
    const a = await enCurso();

    const ver = async (falsa: { lat: number; lng: number }) => {
      const envio = await request(env.app.server)
        .post(`${API}/alerts/${a.id}/locations`)
        .set('Authorization', `Bearer ${tokenProtegido}`)
        .send({ location: falsa });
      expect(envio.status).toBe(200);
      const mine = await request(env.app.server).get(`${API}/alerts/mine`).set('Authorization', `Bearer ${tokenProtegido}`);
      const dueno = (mine.body.data as Array<{ id: string; etaSeconds: number | null }>).find((x) => x.id === a.id)?.etaSeconds;
      const g = await request(env.app.server).get(`${API}/guard/alerts/${a.id}`).set('Authorization', `Bearer ${tokenGuardia}`);
      expect(g.status).toBe(200);
      return { dueno, guardia: g.body.data.etaSeconds as number };
    };
    const moverGuardia = async (p: { lat: number; lng: number }) => {
      const r = await request(env.app.server)
        .put(`${API}/guard/location`)
        .set('Authorization', `Bearer ${tokenGuardia}`)
        .send({ location: p });
      expect(r.status).toBe(200);
    };

    const enA: Array<{ dueno: number | null | undefined; guardia: number }> = [];
    await moverGuardia(A);
    for (const f of FALSAS) enA.push(await ver(f));
    const enB: Array<{ dueno: number | null | undefined; guardia: number }> = [];
    await moverGuardia(B);
    for (const f of FALSAS) enB.push(await ver(f));

    for (const [i, f] of FALSAS.entries()) {
      expect(enA[i]?.dueno, `dueño en A, falsa ${String(i)}`).toBe(paraDueno(A, f));
      // Misma celda: para la misma ubicación falsa, el dueño no distingue A de B.
      expect(enB[i]?.dueno, `dueño en B, falsa ${String(i)}`).toBe(enA[i]?.dueno);
      // El guardia sí ve ETAs distintos, y exactos.
      expect(enA[i]?.guardia, `guardia en A, falsa ${String(i)}`).toBe(etaSeconds('in_progress', A, f, METROS_GUARDIA));
      expect(enB[i]?.guardia, `guardia en B, falsa ${String(i)}`).toBe(etaSeconds('in_progress', B, f, METROS_GUARDIA));
      expect(enB[i]?.guardia, `guardia falsa ${String(i)}`).not.toBe(enA[i]?.guardia);
    }
  });
});
