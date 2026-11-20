// BE-04 paso 5 · POST /guard/alerts/:id/accept contra PostgreSQL real: G-05 (aceptación única),
// D22 (404 idéntico), D35 (asignación atómica), D36 (un guardia, una alerta en atención), D40, D34.
//
// NOTA: necesita DATABASE_URL_TEST. Turnos de 24 h o relativos a "ahora". SSE_PING_SECONDS = 60:
// ningún snapshot llega por el ping dentro de una prueba, así que todo lo que el stream recibe
// llegó por el aviso inmediato (dispatchTopic / alertsTopicForUser / alertTopic).
// La concurrencia usa Promise.all contra la base real, sin pausas arbitrarias.
import request from 'supertest';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { MSG_UNAUTHORIZED, PASSWORD, crearEntorno, hasherPrueba, login, type Entorno } from '../auth/helpers.js';
import { correoUnico, crearAlerta, crearUsuario } from '../db/helpers.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

const API = '/api/v1';
const ZONA = 'America/Mexico_City';
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const CUERPO_404 = { error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } };
const MSG_OCUPADO = 'Ya estás atendiendo otra alerta';
const UUID_INEXISTENTE = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
const CLAVES_ALERTA = [
  'acceptedAt', 'adminNote', 'arrivedAt', 'closedAt', 'escalationReason', 'etaSeconds', 'evidenceIncomplete',
  'guardId', 'guardName', 'heading', 'id', 'location', 'photoUrl', 'resolution', 'status', 'triggerMethod',
  'triggeredAt', 'userId', 'userName', 'userPhone',
].sort();

const CENTRO = { lat: 18.84, lng: -99.18 };
const DENTRO = { lat: 18.8405, lng: -99.18 };
const FUERA = { lat: 18.95, lng: -99.18 };

let env: Entorno;
let passwordHash: string;
let tokenGuardia: string; // guardia principal de env.usuarios
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

async function tokenDe(email: string): Promise<string> {
  const res = await login(env.app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
}

async function crearGuardia(): Promise<Cuenta> {
  const email = correoUnico('acep');
  const u = await crearUsuario(env.prisma, { role: 'guard', email, passwordHash, name: `Guardia ${email}` });
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

const post = (id: string, token?: string) => {
  const r = request(env.app.server).post(`${API}/guard/alerts/${id}/accept`);
  return token === undefined ? r : r.set('Authorization', `Bearer ${token}`);
};
const aceptar = (id: string, token: string = tokenGuardia) => post(id, token);

const usuarioId = () => env.usuarios.protegido.id;
const guardiaId = () => env.usuarios.guardia.id;
const buscando = (extra: Record<string, unknown> = {}) =>
  crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng, ...extra });
const nuevoDueno = () => crearUsuario(env.prisma, { passwordHash });

async function estadoEnBase(id: string) {
  const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
  const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: id } });
  return { status: a.status, guardId: a.guardId, acceptedAt: a.acceptedAt, historial };
}
async function sinCambios(id: string): Promise<void> {
  const e = await estadoEnBase(id);
  expect(e.status).toBe('searching');
  expect(e.guardId).toBeNull();
  expect(e.acceptedAt).toBeNull();
  expect(e.historial).toHaveLength(0);
}

beforeAll(async () => {
  env = await crearEntorno({ SSE_PING_SECONDS: '60' });
  passwordHash = await hasherPrueba.hash(PASSWORD);
  // Escucha una vez, antes de la concurrencia: supertest no debe intentar abrir el puerto en paralelo.
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
  await perfil();
  tokenGuardia = await tokenDe(env.usuarios.guardia.email);
});

afterEach(() => {
  for (const s of abiertas.splice(0)) s.cerrar();
});

// ── Éxito (G-05) ───────────────────────────────────────────────────────

describe('POST /guard/alerts/:id/accept: éxito (G-05)', () => {
  it('200 con las 20 claves, in_progress, guardia, acceptedAt del servidor y teléfono del dueño', async () => {
    const a = await buscando();
    const antes = Date.now();
    const res = await aceptar(a.id);
    const despues = Date.now();
    expect(res.status).toBe(200);
    expect(Object.keys(res.body)).toEqual(['data']);
    const d = res.body.data as Record<string, unknown>;
    expect(Object.keys(d).sort()).toEqual(CLAVES_ALERTA);
    expect(d['id']).toBe(a.id);
    expect(d['status']).toBe('in_progress');
    expect(d['guardId']).toBe(guardiaId());
    expect(d['guardName']).toBe('Nombre guardia');
    expect(d['userId']).toBe(usuarioId());
    expect(d['userName']).toBe('Nombre protegido');
    expect(d['userPhone']).toBe('7771234567');
    expect(d['location']).toEqual(CENTRO);
    expect(d['arrivedAt']).toBeNull();
    expect(d['closedAt']).toBeNull();
    const aceptada = Date.parse(d['acceptedAt'] as string);
    expect(aceptada).toBeGreaterThanOrEqual(antes - 1000);
    expect(aceptada).toBeLessThanOrEqual(despues + 1000);
    expect(new Date(aceptada).toISOString()).toBe(d['acceptedAt']);
  });

  it('etaSeconds es null si el guardia no tiene última ubicación', async () => {
    const a = await buscando();
    const res = await aceptar(a.id);
    expect(res.status).toBe(200);
    expect(res.body.data.etaSeconds).toBeNull();
  });

  it('etaSeconds es un número positivo si el guardia tiene última ubicación', async () => {
    await perfil({ lastLocationLat: 18.85, lastLocationLng: -99.18, lastLocationAt: new Date() });
    const a = await buscando();
    const res = await aceptar(a.id);
    expect(res.status).toBe(200);
    expect(typeof res.body.data.etaSeconds).toBe('number');
    expect(res.body.data.etaSeconds).toBeGreaterThan(0);
  });

  it('en base: asignada, statusChangedAt = acceptedAt y exactamente una fila de historial searching -> in_progress del guardia', async () => {
    const a = await buscando();
    const res = await aceptar(a.id);
    const fila = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
    expect(fila.status).toBe('in_progress');
    expect(fila.guardId).toBe(guardiaId());
    expect(fila.acceptedAt?.toISOString()).toBe(res.body.data.acceptedAt);
    expect(fila.statusChangedAt.toISOString()).toBe(res.body.data.acceptedAt);
    const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: a.id } });
    expect(historial).toHaveLength(1);
    expect(historial[0]).toMatchObject({ fromStatus: 'searching', toStatus: 'in_progress', actorId: guardiaId() });
    expect(historial[0]?.at.toISOString()).toBe(res.body.data.acceptedAt);
  });

  it('el guardia puede aceptar otra cuando ya cerró la anterior (D36 se libera con el cierre)', async () => {
    const primera = await buscando();
    expect((await aceptar(primera.id)).status).toBe(200);
    await env.prisma.alert.update({ where: { id: primera.id }, data: { status: 'closed', closedAt: new Date() } });
    const segunda = await crearAlerta(env.prisma, (await nuevoDueno()).id, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });
    expect((await aceptar(segunda.id)).status).toBe(200);
  });
});

// ── 404: no la ve (D22, D40) ───────────────────────────────────────────

describe('POST /guard/alerts/:id/accept: 404 con cuerpo idéntico (D22, D40)', () => {
  it('UUID inválido', async () => {
    const res = await aceptar('no-es-un-uuid');
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
  });

  it('alerta inexistente', async () => {
    const res = await aceptar(UUID_INEXISTENTE);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
  });

  it('fuera del radio de cobertura', async () => {
    const a = await buscando({ lat: FUERA.lat, lng: FUERA.lng });
    const res = await aceptar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('fuera de turno', async () => {
    await perfil(FUERA_DE_TURNO());
    const a = await buscando({ lat: DENTRO.lat, lng: DENTRO.lng });
    const res = await aceptar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('ignorada por el guardia', async () => {
    const a = await buscando();
    await env.prisma.alertIgnore.create({ data: { guardId: guardiaId(), alertId: a.id } });
    const res = await aceptar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('pending_location (sin ubicación aún)', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'pending_location' });
    const res = await aceptar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    const fila = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
    expect(fila.status).toBe('pending_location');
    expect(fila.guardId).toBeNull();
  });

  it('guardia sin cobertura asignada', async () => {
    await perfil({ coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null });
    const a = await buscando();
    const res = await aceptar(a.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('guardia sin perfil', async () => {
    const email = correoUnico('sinperfil');
    await crearUsuario(env.prisma, { role: 'guard', email, passwordHash });
    const a = await buscando();
    const res = await aceptar(a.id, await tokenDe(email));
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(a.id);
  });

  it('guardia de baja: el token anterior ya no sirve, 401 por autenticación (no llega a accept) y la alerta no cambia', async () => {
    const a = await buscando();
    await env.prisma.user.update({ where: { id: guardiaId() }, data: { isActive: false } });
    const res = await aceptar(a.id);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
    await sinCambios(a.id);
  });

  it('un guardia ocupado recibe el mismo 404 ante una alerta fuera de cobertura (el tipo de error no revela nada)', async () => {
    await crearAlerta(env.prisma, (await nuevoDueno()).id, { status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng });
    const lejos = await buscando({ lat: FUERA.lat, lng: FUERA.lng });
    const res = await aceptar(lejos.id);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    await sinCambios(lejos.id);
  });
});

// ── 409 ALERT_TAKEN (D35) ──────────────────────────────────────────────

describe('POST /guard/alerts/:id/accept: 409 ALERT_TAKEN (D35)', () => {
  function esperarTomada(res: { status: number; body: { error?: { code?: string; message?: string } } }): void {
    expect(res.status).toBe(409);
    expect(res.body.error?.code).toBe('ALERT_TAKEN');
    expect(typeof res.body.error?.message).toBe('string');
    expect(Object.keys(res.body)).toEqual(['error']);
  }

  it('ya tomada por otro guardia dentro de mi cobertura', async () => {
    const otro = await crearGuardia();
    const a = await buscando();
    expect((await aceptar(a.id, otro.token)).status).toBe(200);
    esperarTomada(await aceptar(a.id));
    const e = await estadoEnBase(a.id);
    expect(e.guardId).toBe(otro.id);
    expect(e.historial).toHaveLength(1);
  });

  it('reintento del mismo guardia sobre su propia alerta in_progress', async () => {
    const a = await buscando();
    expect((await aceptar(a.id)).status).toBe(200);
    esperarTomada(await aceptar(a.id));
    const e = await estadoEnBase(a.id);
    expect(e.status).toBe('in_progress');
    expect(e.historial).toHaveLength(1);
  });

  it.each(['in_progress', 'guard_arrived', 'closed', 'escalated'] as const)(
    'alerta de otro guardia en %s dentro de mi cobertura',
    async (status) => {
      const a = await crearAlerta(env.prisma, usuarioId(), { status, lat: DENTRO.lat, lng: DENTRO.lng });
      esperarTomada(await aceptar(a.id));
      const e = await estadoEnBase(a.id);
      expect(e.status).toBe(status);
      expect(e.guardId).toBe(a.guardId);
    },
  );

  it('no_response sin guardia dentro de mi cobertura (visible pero no en searching)', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'no_response', lat: CENTRO.lat, lng: CENTRO.lng });
    esperarTomada(await aceptar(a.id));
    expect((await estadoEnBase(a.id)).status).toBe('no_response');
  });

  it('alerta propia ya cerrada (asignada a mí, fuera de cobertura): 409 y no se reabre', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: guardiaId(), lat: FUERA.lat, lng: FUERA.lng });
    esperarTomada(await aceptar(a.id));
    expect((await estadoEnBase(a.id)).status).toBe('closed');
  });
});

// ── 409 INVALID_STATE (D36) ────────────────────────────────────────────

describe('POST /guard/alerts/:id/accept: 409 INVALID_STATE, ya atiende otra (D36)', () => {
  it.each(['in_progress', 'guard_arrived'] as const)('con otra alerta en %s', async (status) => {
    const enCurso = await crearAlerta(env.prisma, (await nuevoDueno()).id, { status, guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng });
    const nueva = await buscando();
    const res = await aceptar(nueva.id);
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: { code: 'INVALID_STATE', message: MSG_OCUPADO } });
    await sinCambios(nueva.id);
    expect((await estadoEnBase(enCurso.id)).status).toBe(status);
  });

  it('con alertas cerradas o escaladas previas sí puede aceptar', async () => {
    await crearAlerta(env.prisma, (await nuevoDueno()).id, { status: 'closed', guardId: guardiaId() });
    await crearAlerta(env.prisma, (await nuevoDueno()).id, { status: 'escalated', guardId: guardiaId() });
    const nueva = await buscando();
    expect((await aceptar(nueva.id)).status).toBe(200);
  });
});

// ── Permisos ───────────────────────────────────────────────────────────

describe('POST /guard/alerts/:id/accept: permisos', () => {
  it('sin token -> 401, la alerta no cambia', async () => {
    const a = await buscando();
    const res = await post(a.id);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
    await sinCambios(a.id);
  });

  it('token basura -> 401', async () => {
    const a = await buscando();
    expect((await post(a.id, 'no.es.jwt')).status).toBe(401);
    await sinCambios(a.id);
  });

  it.each(['protected_user', 'admin'] as const)('rol %s -> 403 FORBIDDEN, la alerta no cambia', async (rol) => {
    const a = await buscando();
    const res = await post(a.id, rol === 'admin' ? tokenAdmin : tokenProtegido);
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    await sinCambios(a.id);
  });
});

// ── K: el guardia no cierra la alerta ──────────────────────────────────

describe('K: el guardia no puede cerrar la alerta', () => {
  it('POST /alerts/:id/confirm con token de guardia -> 403 y la alerta sigue en curso', async () => {
    const a = await buscando();
    expect((await aceptar(a.id)).status).toBe(200);
    const res = await request(env.app.server)
      .post(`${API}/alerts/${a.id}/confirm`)
      .set('Authorization', `Bearer ${tokenGuardia}`);
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    expect((await estadoEnBase(a.id)).status).toBe('in_progress');
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } })).closedAt).toBeNull();
  });

  it('accept nunca produce closed: queda in_progress sin closedAt', async () => {
    const a = await buscando();
    const res = await aceptar(a.id);
    expect(res.body.data.status).toBe('in_progress');
    expect(res.body.data.closedAt).toBeNull();
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } })).closedAt).toBeNull();
  });

  it('el dueño tampoco puede confirmar antes de que el guardia llegue (sigue in_progress)', async () => {
    const a = await buscando();
    expect((await aceptar(a.id)).status).toBe(200);
    const res = await request(env.app.server)
      .post(`${API}/alerts/${a.id}/confirm`)
      .set('Authorization', `Bearer ${tokenProtegido}`);
    expect(res.status).not.toBe(200);
    expect((await estadoEnBase(a.id)).status).toBe('in_progress');
  });
});

// ── Concurrencia (criterio de terminado de la tarjeta) ─────────────────

describe('POST /guard/alerts/:id/accept: concurrencia (D35, D36)', () => {
  let guardias: Cuenta[] = [];

  beforeAll(async () => {
    guardias = [];
    for (let i = 0; i < 5; i += 1) guardias.push(await crearGuardia());
  }, 120_000);

  it('25 rondas: varios guardias aceptan la misma alerta a la vez; exactamente uno gana (G-05, D35)', async () => {
    const dueno = usuarioId();
    for (let ronda = 0; ronda < 25; ronda += 1) {
      const n = 2 + (ronda % 4); // 2..5 guardias
      const participantes = guardias.slice(0, n);
      await env.prisma.alert.deleteMany();
      const a = await crearAlerta(env.prisma, dueno, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });

      const respuestas = await Promise.all(participantes.map((g) => aceptar(a.id, g.token)));
      const ganadores = respuestas.flatMap((r, i) => (r.status === 200 ? [i] : []));
      const detalle = `ronda ${String(ronda)}: ${JSON.stringify(respuestas.map((r) => [r.status, r.body.error?.code]))}`;
      expect(ganadores, detalle).toHaveLength(1);
      respuestas.forEach((r, i) => {
        if (i === ganadores[0]) return;
        expect(r.status, detalle).toBe(409);
        expect(r.body.error?.code, detalle).toBe('ALERT_TAKEN');
      });

      const ganador = participantes[ganadores[0] as number] as Cuenta;
      expect(respuestas[ganadores[0] as number]?.body.data.guardId, detalle).toBe(ganador.id);
      const fila = await env.prisma.alert.findUniqueOrThrow({ where: { id: a.id } });
      expect(fila.status, detalle).toBe('in_progress');
      expect(fila.guardId, detalle).toBe(ganador.id);
      const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: a.id } });
      expect(historial, detalle).toHaveLength(1);
      expect(historial[0], detalle).toMatchObject({ fromStatus: 'searching', toStatus: 'in_progress', actorId: ganador.id });
      expect(await env.prisma.alert.count({ where: { status: 'in_progress' } }), detalle).toBe(1);
    }
  }, 120_000);

  it('15 rondas: el MISMO guardia acepta 2 o 3 alertas distintas a la vez; solo una prospera (D36)', async () => {
    const duenos = [usuarioId(), (await nuevoDueno()).id, (await nuevoDueno()).id];
    const g = guardias[0] as Cuenta;
    for (let ronda = 0; ronda < 15; ronda += 1) {
      const n = 2 + (ronda % 2); // 2 o 3 alertas
      await env.prisma.alert.deleteMany();
      const alertas = [];
      for (let i = 0; i < n; i += 1) {
        alertas.push(await crearAlerta(env.prisma, duenos[i] as string, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng }));
      }

      const respuestas = await Promise.all(alertas.map((a) => aceptar(a.id, g.token)));
      const detalle = `ronda ${String(ronda)}: ${JSON.stringify(respuestas.map((r) => [r.status, r.body.error?.code, r.body.error?.message]))}`;
      const ok = respuestas.flatMap((r, i) => (r.status === 200 ? [i] : []));
      expect(ok, detalle).toHaveLength(1);
      for (const r of respuestas) {
        if (r.status === 200) continue;
        expect(r.status, detalle).toBe(409);
        expect(r.body, detalle).toEqual({ error: { code: 'INVALID_STATE', message: MSG_OCUPADO } });
      }

      const enCurso = await env.prisma.alert.findMany({ where: { guardId: g.id, status: { in: ['in_progress', 'guard_arrived'] } } });
      expect(enCurso, detalle).toHaveLength(1);
      expect(enCurso[0]?.id, detalle).toBe(alertas[ok[0] as number]?.id);
      // Las perdedoras siguen en searching, sin guardia y sin historial.
      for (const [i, a] of alertas.entries()) {
        if (i === ok[0]) continue;
        const e = await estadoEnBase(a.id);
        expect(e.status, detalle).toBe('searching');
        expect(e.guardId, detalle).toBeNull();
        expect(e.historial, detalle).toHaveLength(0);
      }
      expect(await env.prisma.alertStatusHistory.count(), detalle).toBe(1);
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

describe('POST /guard/alerts/:id/accept: tiempo real (D34)', () => {
  it('el dueño con alerts/active recibe la alerta en in_progress con su guardia', async () => {
    const a = await buscando();
    const s = await abrir('/events/alerts/active', tokenProtegido);
    const inicial = (await s.siguiente()) as { data: { status: string } };
    expect(inicial.data.status).toBe('searching');
    expect((await aceptar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => (ev.data as { status?: string } | null)?.status === 'in_progress');
    expect(e.data).toMatchObject({ id: a.id, status: 'in_progress', guardId: guardiaId() });
  });

  it('otro guardia con guard/alerts abierto deja de ver la alerta sin esperar el ping (dispatchTopic)', async () => {
    const otro = await crearGuardia();
    const a = await buscando();
    const s = await abrir('/events/guard/alerts', otro.token);
    const inicial = (await s.siguiente()) as { data: Array<{ alert: { id: string } }> };
    expect(inicial.data.map((i) => i.alert.id)).toEqual([a.id]);
    expect((await aceptar(a.id)).status).toBe(200);
    // El ping es de 60 s: lo que llega ahora lo provocó el aviso de la aceptación.
    const e = await esperarEvento(s, (ev) => Array.isArray(ev.data) && ev.data.length === 0);
    expect(e.data).toEqual([]);
  });

  it('otro guardia con guard/alerts/:id abierto recibe NOT_FOUND y se cierra el stream', async () => {
    const otro = await crearGuardia();
    const a = await buscando();
    const s = await abrir(`/events/guard/alerts/${a.id}`, otro.token);
    const inicial = (await s.siguiente()) as { data: { status: string; userPhone: string | null } };
    expect(inicial.data.status).toBe('searching');
    expect(inicial.data.userPhone).toBeNull();
    expect((await aceptar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => ev.error !== undefined);
    expect(e).toEqual(CUERPO_404);
    const limite = Date.now() + 3000;
    while (!s.cerrado() && Date.now() < limite) await new Promise((r) => setTimeout(r, 20));
    expect(s.cerrado()).toBe(true);
  });

  it('el ganador con guard/alerts/:id abierto recibe in_progress con el teléfono del dueño', async () => {
    const a = await buscando();
    const s = await abrir(`/events/guard/alerts/${a.id}`, tokenGuardia);
    const inicial = (await s.siguiente()) as { data: { status: string; userPhone: string | null } };
    expect(inicial.data.status).toBe('searching');
    expect(inicial.data.userPhone).toBeNull();
    expect((await aceptar(a.id)).status).toBe(200);
    const e = await esperarEvento(s, (ev) => (ev.data as { status?: string } | undefined)?.status === 'in_progress');
    expect(e.data).toMatchObject({ id: a.id, guardId: guardiaId(), userPhone: '7771234567' });
  });
});
