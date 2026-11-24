// BE-04 paso 4 · Canal guard/alerts/:id (SSE) contra PostgreSQL real: G-04 (detalle), G-06 (movimiento
// del usuario y ETA en vivo), D22 (visibilidad), D23 (vista del guardia), D34, D40 (NOT_FOUND idéntico).
//
// NOTA: necesita DATABASE_URL_TEST. Turnos de 24 h o relativos a "ahora"; el canal manda un snapshot
// en cada ping (SSE_PING_SECONDS = 1) y las esperas son acotadas.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { PASSWORD, MSG_UNAUTHORIZED, crearEntorno, hasherPrueba, login, type Entorno } from '../auth/helpers.js';
import { correoUnico, crearAlerta, crearUsuario } from '../db/helpers.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

const API = '/api/v1';
const ZONA = 'America/Mexico_City';
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const EVENTO_404 = { error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } };
const UUID_INEXISTENTE = '00000000-0000-4000-8000-000000000000';
const CLAVES_ALERTA = [
  'acceptedAt', 'adminNote', 'arrivedAt', 'closedAt', 'escalationReason', 'etaSeconds', 'evidenceIncomplete',
  'guardId', 'guardName', 'heading', 'id', 'location', 'photoUrl', 'resolution', 'status', 'triggerMethod',
  'triggeredAt', 'userId', 'userName', 'userPhone',
];

const CENTRO = { lat: 18.84, lng: -99.18 };
const punto = (dLat: number, dLng = 0) => ({ lat: CENTRO.lat + dLat, lng: CENTRO.lng + dLng });
const FUERA = { lat: 18.95, lng: -99.18 };
const TURNO_24H = { shiftStart: '00:00', shiftEnd: '00:00' };

type AlertaVista = Record<string, unknown> & {
  id: string;
  status: string;
  userPhone: string | null;
  location: { lat: number; lng: number } | null;
  etaSeconds: number | null;
};

let env: Entorno;
let passwordHash: string;
const abiertas: ConexionSse[] = [];

function horaLocal(minutos: number): string {
  const partes = new Intl.DateTimeFormat('en-US', { timeZone: ZONA, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(Date.now() + minutos * 60_000));
  const h = partes.find((p) => p.type === 'hour')?.value ?? '00';
  const m = partes.find((p) => p.type === 'minute')?.value ?? '00';
  return `${h === '24' ? '00' : h}:${m}`;
}

interface Cuenta {
  id: string;
  email: string;
  token: string;
}
async function conToken(id: string, email: string): Promise<Cuenta> {
  const res = await login(env.app, email);
  expect(res.status).toBe(200);
  return { id, email, token: res.body.data.accessToken as string };
}
async function guardia(perfil: Record<string, unknown> = {}): Promise<Cuenta> {
  const email = correoUnico('detg');
  const u = await crearUsuario(env.prisma, { role: 'guard', email, passwordHash });
  await env.prisma.guardProfile.create({
    data: {
      userId: u.id,
      ...TURNO_24H,
      coverageCenterLat: CENTRO.lat,
      coverageCenterLng: CENTRO.lng,
      coverageRadiusMeters: 2000,
      ...perfil,
    },
  });
  return conToken(u.id, email);
}
async function protegido(): Promise<Cuenta & { phone: string }> {
  const email = correoUnico('detp');
  const phone = '7775550123';
  const u = await crearUsuario(env.prisma, { role: 'protected_user', email, passwordHash, phone });
  return { ...(await conToken(u.id, email)), phone };
}

const ruta = (id: string) => `${API}/events/guard/alerts/${id}`;
async function abrir(c: Cuenta | null, id: string): Promise<ConexionSse> {
  const s = await abrirSse(env.app, ruta(id), c?.token);
  abiertas.push(s);
  return s;
}
/** Abre y devuelve el primer evento ya extraído como AlertaVista. */
async function abrirYLeer(c: Cuenta, id: string): Promise<{ s: ConexionSse; alerta: AlertaVista }> {
  const s = await abrir(c, id);
  expect(s.status).toBe(200);
  const e = (await s.siguiente()) as { data: AlertaVista };
  return { s, alerta: e.data };
}
async function esperarAlerta(s: ConexionSse, pred: (a: AlertaVista) => boolean, ms = 6000): Promise<AlertaVista> {
  const limite = Date.now() + ms;
  let ultima: unknown;
  while (Date.now() < limite) {
    try {
      ultima = await s.siguiente(Math.max(50, limite - Date.now()));
    } catch {
      break;
    }
    const d = (ultima as { data?: AlertaVista }).data;
    if (d && pred(d)) return d;
  }
  throw new Error(`Ningún evento cumplió la condición; último: ${JSON.stringify(ultima)}`);
}
async function esperarCierre(s: ConexionSse, ms = 3000): Promise<void> {
  const limite = Date.now() + ms;
  while (!s.cerrado() && Date.now() < limite) await new Promise((r) => setTimeout(r, 20));
  expect(s.cerrado()).toBe(true);
}
/** Lee eventos hasta ver el error NOT_FOUND (descarta snapshots previos válidos). */
async function esperarNotFound(s: ConexionSse, ms = 5000): Promise<unknown> {
  const limite = Date.now() + ms;
  let e: unknown;
  while (Date.now() < limite) {
    e = await s.siguiente(Math.max(50, limite - Date.now()));
    if (e && typeof e === 'object' && 'error' in e) return e;
  }
  throw new Error('No llegó NOT_FOUND');
}

const postUbicacion = (t: string, alertId: string, location: { lat: number; lng: number }) =>
  request(env.app.server).post(`${API}/alerts/${alertId}/locations`).set('Authorization', `Bearer ${t}`).send({ location });
const putUbicacionGuardia = (t: string, location: { lat: number; lng: number }) =>
  request(env.app.server).put(`${API}/guard/location`).set('Authorization', `Bearer ${t}`).send({ location });
const confirmar = (t: string, alertId: string) =>
  request(env.app.server).post(`${API}/alerts/${alertId}/confirm`).set('Authorization', `Bearer ${t}`).send({});

async function alertaDisponible(location = punto(0.002), extra: Record<string, unknown> = {}) {
  const p = await protegido();
  return { p, alerta: await crearAlerta(env.prisma, p.id, { status: 'searching', lat: location.lat, lng: location.lng, ...extra }) };
}
async function alertaAsignada(g: Cuenta, extra: Record<string, unknown> = {}) {
  const p = await protegido();
  const alerta = await crearAlerta(env.prisma, p.id, {
    status: 'in_progress',
    guardId: g.id,
    acceptedAt: new Date(),
    lat: punto(0.002).lat,
    lng: punto(0.002).lng,
    ...extra,
  });
  return { p, alerta };
}

beforeAll(async () => {
  env = await crearEntorno({ SSE_PING_SECONDS: '1' });
  passwordHash = await hasherPrueba.hash(PASSWORD);
}, 120_000);
afterAll(async () => {
  for (const c of abiertas) c.cerrar();
  await env.cerrar();
});
beforeEach(async () => {
  for (const c of abiertas.splice(0)) c.cerrar();
  await env.prisma.alert.deleteMany();
});

describe('GET /events/guard/alerts/:id: permisos (antes de abrir el stream)', () => {
  it('sin token -> 401 con el envoltorio', async () => {
    const s = await abrir(null, UUID_INEXISTENTE);
    expect(s.status).toBe(401);
    expect(s.json).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it('token basura -> 401', async () => {
    const s = await abrirSse(env.app, ruta(UUID_INEXISTENTE), 'no.es.jwt');
    abiertas.push(s);
    expect(s.status).toBe(401);
  });

  it.each(['protegido', 'admin'] as const)('rol %s -> 403 FORBIDDEN, sin abrir stream', async (quien) => {
    const { alerta } = await alertaDisponible();
    const t = await conToken(env.usuarios[quien].id, env.usuarios[quien].email);
    const s = await abrir(t, alerta.id);
    expect(s.status).toBe(403);
    expect(s.json).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    expect(s.headers['content-type']).not.toMatch(/event-stream/);
  });

  it('guardia dado de baja -> 401 antes de abrir', async () => {
    const g = await guardia();
    const { alerta } = await alertaDisponible();
    await env.prisma.user.update({ where: { id: g.id }, data: { isActive: false } });
    const s = await abrir(g, alerta.id);
    expect(s.status).toBe(401);
    expect(s.json).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });
});

describe('GET /events/guard/alerts/:id: alerta asignada (G-04, G-06, D23)', () => {
  it('primer evento: AlertJson de 20 claves con userPhone del dueño y location', async () => {
    const g = await guardia();
    const { p, alerta } = await alertaAsignada(g);
    const s = await abrir(g, alerta.id);
    expect(s.status).toBe(200);
    expect(s.headers['content-type']).toMatch(/^text\/event-stream/);
    const e = (await s.siguiente()) as { data: AlertaVista };
    expect(Object.keys(e)).toEqual(['data']);
    expect(Object.keys(e.data).sort()).toEqual(CLAVES_ALERTA);
    expect(e.data.id).toBe(alerta.id);
    expect(e.data.status).toBe('in_progress');
    expect(e.data.userPhone).toBe(p.phone);
    expect(e.data.location).toEqual(punto(0.002));
    expect(e.data.guardId).toBe(g.id);
  });

  it('G-06: cuando el dueño se mueve llega un snapshot con la nueva location', async () => {
    const g = await guardia();
    const { p, alerta } = await alertaAsignada(g);
    const { s, alerta: inicial } = await abrirYLeer(g, alerta.id);
    expect(inicial.location).toEqual(punto(0.002));
    const destino = punto(0.006, 0.001);
    expect((await postUbicacion(p.token, alerta.id, destino)).status).toBe(200);
    const nueva = await esperarAlerta(s, (a) => a.location?.lat === destino.lat);
    expect(nueva.location).toEqual(destino);
    expect(nueva.userPhone).toBe(p.phone);
  });

  it('G-06/U-08: PUT /guard/location del guardia manda un snapshot con etaSeconds actualizado', async () => {
    const g = await guardia();
    const { alerta } = await alertaAsignada(g);
    const lejos = punto(0.02);
    expect((await putUbicacionGuardia(g.token, lejos)).status).toBe(200);
    const { s, alerta: inicial } = await abrirYLeer(g, alerta.id);
    expect(inicial.etaSeconds).toBeGreaterThan(0);
    const cerca = punto(0.0021);
    expect((await putUbicacionGuardia(g.token, cerca)).status).toBe(200);
    const nueva = await esperarAlerta(s, (a) => a.etaSeconds !== null && a.etaSeconds < (inicial.etaSeconds as number));
    expect(nueva.etaSeconds).toBeLessThan(inicial.etaSeconds as number);
  });

  it(':id en mayúsculas: los avisos del bus llegan igual (G-06 sin esperar el ping)', async () => {
    const g = await guardia();
    const { p, alerta } = await alertaAsignada(g);
    const { s } = await abrirYLeer(g, alerta.id.toUpperCase());
    const destino = punto(0.007, 0.001);
    expect((await postUbicacion(p.token, alerta.id, destino)).status).toBe(200);
    // Menos que el ping (1 s): solo pasa si el aviso llegó por alertTopic.
    const nueva = await esperarAlerta(s, (a) => a.location?.lat === destino.lat, 900);
    expect(nueva.location).toEqual(destino);
  });

  it('guardia dado de baja con el stream abierto: el siguiente snapshot es NOT_FOUND, nunca su teléfono', async () => {
    const g = await guardia();
    const { p, alerta } = await alertaAsignada(g);
    const { s, alerta: inicial } = await abrirYLeer(g, alerta.id);
    expect(inicial.userPhone).toBe(p.phone);
    await env.prisma.user.update({ where: { id: g.id }, data: { isActive: false } });
    // Un aviso del bus (el dueño se mueve) llega antes del ping que revisa la sesión.
    expect((await postUbicacion(p.token, alerta.id, punto(0.004))).status).toBe(200);
    const e = (await s.siguiente(3000)) as { data?: AlertaVista; error?: { code: string } };
    expect(e.data).toBeUndefined();
    expect(['NOT_FOUND', 'UNAUTHORIZED']).toContain(e.error?.code);
    await esperarCierre(s);
  });

  it('el dueño confirma (guard_arrived -> closed): snapshot sin location ni userPhone y el stream SIGUE abierto', async () => {
    const g = await guardia();
    const { p, alerta } = await alertaAsignada(g, { status: 'guard_arrived', arrivedAt: new Date() });
    const { s, alerta: antes } = await abrirYLeer(g, alerta.id);
    expect(antes.status).toBe('guard_arrived');
    expect(antes.userPhone).toBe(p.phone);
    expect((await confirmar(p.token, alerta.id)).status).toBe(200);
    const cerrada = await esperarAlerta(s, (a) => a.status === 'closed');
    expect(cerrada.location).toBeNull();
    expect(cerrada.userPhone).toBeNull();
    expect(cerrada.guardId).toBe(g.id);
    // Sigue llegando un snapshot en cada ping y no es un error.
    const siguiente = (await s.siguiente(4000)) as { data?: AlertaVista; error?: unknown };
    expect(siguiente.error).toBeUndefined();
    expect(siguiente.data?.status).toBe('closed');
    expect(s.cerrado()).toBe(false);
  });
});

describe('GET /events/guard/alerts/:id: alerta disponible (D22, D23)', () => {
  it('searching en turno y radio: primer evento con userPhone null', async () => {
    const g = await guardia();
    const { alerta } = await alertaDisponible();
    const { alerta: vista } = await abrirYLeer(g, alerta.id);
    expect(vista.id).toBe(alerta.id);
    expect(vista.status).toBe('searching');
    expect(vista.userPhone).toBeNull();
    expect(Object.keys(vista).sort()).toEqual(CLAVES_ALERTA);
  });

  it('deja de ser visible porque la toma OTRO guardia: NOT_FOUND exacto y cierre', async () => {
    const g = await guardia();
    const otro = await guardia();
    const { alerta } = await alertaDisponible();
    const { s } = await abrirYLeer(g, alerta.id);
    await env.prisma.alert.update({ where: { id: alerta.id }, data: { status: 'in_progress', guardId: otro.id, acceptedAt: new Date() } });
    expect(await esperarNotFound(s)).toEqual(EVENTO_404);
    await esperarCierre(s);
  });

  it('el guardia la ignora (registro en base + ping): NOT_FOUND y cierre', async () => {
    const g = await guardia();
    const { alerta } = await alertaDisponible();
    const { s } = await abrirYLeer(g, alerta.id);
    await env.prisma.alertIgnore.create({ data: { guardId: g.id, alertId: alerta.id } });
    expect(await esperarNotFound(s)).toEqual(EVENTO_404);
    await esperarCierre(s);
  });

  it('el dueño la mueve fuera de la cobertura: NOT_FOUND y cierre', async () => {
    const g = await guardia();
    const { p, alerta } = await alertaDisponible();
    const { s } = await abrirYLeer(g, alerta.id);
    expect((await postUbicacion(p.token, alerta.id, FUERA)).status).toBe(200);
    expect(await esperarNotFound(s)).toEqual(EVENTO_404);
    await esperarCierre(s);
  });

  it('termina su turno (cambio de perfil): NOT_FOUND en el siguiente ping y cierre', async () => {
    const g = await guardia();
    const { alerta } = await alertaDisponible();
    const { s } = await abrirYLeer(g, alerta.id);
    await env.prisma.guardProfile.update({
      where: { userId: g.id },
      data: { shiftStart: horaLocal(180), shiftEnd: horaLocal(300) },
    });
    expect(await esperarNotFound(s)).toEqual(EVENTO_404);
    await esperarCierre(s);
  });

  it('pierde la cobertura (perfil sin cobertura): NOT_FOUND y cierre', async () => {
    const g = await guardia();
    const { alerta } = await alertaDisponible();
    const { s } = await abrirYLeer(g, alerta.id);
    await env.prisma.guardProfile.update({
      where: { userId: g.id },
      data: { coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null },
    });
    expect(await esperarNotFound(s)).toEqual(EVENTO_404);
    await esperarCierre(s);
  });
});

describe('GET /events/guard/alerts/:id: ajena desde el inicio (D40: cuerpo idéntico)', () => {
  it('in_progress de otro, fuera de radio, ignorada, fuera de turno e inexistente -> mismo NOT_FOUND y cierre', async () => {
    const g = await guardia();
    const otro = await guardia();
    const ajena = await alertaAsignada(otro);
    const lejana = await alertaDisponible(FUERA);
    const ignorada = await alertaDisponible();
    await env.prisma.alertIgnore.create({ data: { guardId: g.id, alertId: ignorada.alerta.id } });
    const sinTurno = await guardia({ shiftStart: horaLocal(180), shiftEnd: horaLocal(300) });
    const delTurno = await alertaDisponible();

    const casos: Array<[string, Cuenta, string]> = [
      ['ajena', g, ajena.alerta.id],
      ['fuera de radio', g, lejana.alerta.id],
      ['ignorada', g, ignorada.alerta.id],
      ['fuera de turno', sinTurno, delTurno.alerta.id],
      ['inexistente', g, UUID_INEXISTENTE],
    ];
    for (const [nombre, quien, id] of casos) {
      const s = await abrir(quien, id);
      expect(s.status, nombre).toBe(200);
      expect(await s.siguiente(), nombre).toEqual(EVENTO_404);
      await esperarCierre(s);
    }
  });
});

describe(':id que no es UUID: evento NOT_FOUND, no 404 HTTP', () => {
  it.each(['abc', '123', "1'%20OR%20'1'='1", '%27%3B%20DROP%20TABLE%20alerts%3B--', '00000000-0000-0000-0000-00000000000z'])(
    'id %s',
    async (id) => {
      const g = await guardia();
      const s = await abrir(g, id);
      expect(s.status).toBe(200);
      expect(s.headers['content-type']).toMatch(/^text\/event-stream/);
      expect(await s.siguiente()).toEqual(EVENTO_404);
      await esperarCierre(s);
    },
  );

  it('las alertas siguen intactas tras el intento de inyección', async () => {
    const g = await guardia();
    const { alerta } = await alertaDisponible();
    const s = await abrir(g, "x'%3B%20DELETE%20FROM%20alerts%3B--");
    await s.siguiente();
    expect(await env.prisma.alert.count({ where: { id: alerta.id } })).toBe(1);
  });
});

describe('GET /events/guard/alerts/:id: límite de conexiones por (usuario, canal)', () => {
  it('el 4.º stream (ids distintos) cierra el más antiguo de ese canal y no afecta a guard/alerts', async () => {
    const g = await guardia();
    const alertas: string[] = [];
    for (let i = 0; i < 4; i++) alertas.push((await alertaDisponible(punto(0.002 + i * 0.0001))).alerta.id);

    const lista = await abrirSse(env.app, `${API}/events/guard/alerts`, g.token);
    abiertas.push(lista);
    await lista.siguiente();

    const detalles: ConexionSse[] = [];
    for (let i = 0; i < 3; i++) {
      const { s } = await abrirYLeer(g, alertas[i] as string);
      detalles.push(s);
    }
    const cuarto = await abrirYLeer(g, alertas[3] as string);
    await esperarCierre(detalles[0] as ConexionSse);
    expect(detalles[1]?.cerrado()).toBe(false);
    expect(detalles[2]?.cerrado()).toBe(false);
    expect(cuarto.s.cerrado()).toBe(false);
    expect(lista.cerrado()).toBe(false);
  });
});

describe('GET /events/guard/alerts/:id: seguridad de los datos', () => {
  it('ningún evento contiene passwordHash, email del dueño ni lastLocation del guardia', async () => {
    const g = await guardia({ lastLocationLat: punto(0.01).lat, lastLocationLng: punto(0.01).lng });
    const { p, alerta } = await alertaAsignada(g);
    const { s } = await abrirYLeer(g, alerta.id);
    expect((await postUbicacion(p.token, alerta.id, punto(0.004))).status).toBe(200);
    const eventos: unknown[] = [];
    const limite = Date.now() + 2500;
    while (Date.now() < limite) {
      try {
        eventos.push(await s.siguiente(Math.max(50, limite - Date.now())));
      } catch {
        break;
      }
    }
    expect(eventos.length).toBeGreaterThan(0);
    const texto = JSON.stringify(eventos);
    expect(texto).not.toMatch(/passwordHash|password_hash|\$argon2/i);
    expect(texto).not.toContain(p.email);
    expect(texto).not.toContain(g.email);
    expect(texto).not.toMatch(/lastLocation/i);
    expect(texto).not.toContain(String(punto(0.01).lat));
  });
});
