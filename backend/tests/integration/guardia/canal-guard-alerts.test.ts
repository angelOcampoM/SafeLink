// BE-04 paso 3 · Canal guard/alerts (SSE) contra PostgreSQL real: G-03 (lista priorizada),
// D22 (visibilidad por guardia en cada emisión), D23 (userPhone null), D24, D34, D37.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
// Los turnos son relativos a "ahora" (hora local de TZ_SHIFTS) o de 24 h: nunca horas fijas.
// El canal manda un snapshot en cada ping (SSE_PING_SECONDS = 1): las comprobaciones negativas
// leen eventos durante un tiempo acotado y exigen que NINGUNO contenga la alerta.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { haversineMeters } from '../../../src/domain/geo.js';
import { createGuardService } from '../../../src/modules/guard/service.js';
import { MSG_UNAUTHORIZED, PASSWORD, crearEntorno, hasherPrueba, login, type Entorno } from '../auth/helpers.js';
import { correoUnico, crearAlerta, crearUsuario } from '../db/helpers.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

const API = '/api/v1';
const CANAL = `${API}/events/guard/alerts`;
const ZONA = 'America/Mexico_City'; // TZ_SHIFTS por defecto
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';

const CENTRO = { lat: 18.84, lng: -99.18 };
/** Puntos al norte/sur del centro (0.001 grados ~ 111 m). Todos dentro de 2 km de cobertura. */
const punto = (dLat: number, dLng = 0) => ({ lat: CENTRO.lat + dLat, lng: CENTRO.lng + dLng });
const FUERA = { lat: 18.95, lng: -99.18 }; // ~12 km del centro

interface ItemPriorizado {
  alert: { id: string; userPhone: string | null; status: string; location: { lat: number; lng: number } | null };
  distanceMeters: number;
  waitingMinutes: number;
  score: number;
}
type Evento = { data: ItemPriorizado[] };

let env: Entorno;
let passwordHash: string;
const abiertas: ConexionSse[] = [];

/** "HH:mm" local de (ahora + minutos) en la zona de los turnos. */
function horaLocal(minutos: number): string {
  const partes = new Intl.DateTimeFormat('en-US', { timeZone: ZONA, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(Date.now() + minutos * 60_000));
  const h = partes.find((p) => p.type === 'hour')?.value ?? '00';
  const m = partes.find((p) => p.type === 'minute')?.value ?? '00';
  return `${h === '24' ? '00' : h}:${m}`;
}
const EN_TURNO = () => ({ shiftStart: horaLocal(-120), shiftEnd: horaLocal(120) });
const FUERA_DE_TURNO = () => ({ shiftStart: horaLocal(180), shiftEnd: horaLocal(300) });
const TURNO_24H = { shiftStart: '00:00', shiftEnd: '00:00' };

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

async function guardia(
  perfil: Partial<{
    shiftStart: string;
    shiftEnd: string;
    coverageCenterLat: number | null;
    coverageCenterLng: number | null;
    coverageRadiusMeters: number | null;
    lastLocationLat: number | null;
    lastLocationLng: number | null;
  }> = {},
): Promise<Cuenta> {
  const email = correoUnico('canalg');
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

async function protegido(): Promise<Cuenta> {
  const email = correoUnico('canalp');
  const u = await crearUsuario(env.prisma, { role: 'protected_user', email, passwordHash, phone: '7771112233' });
  return conToken(u.id, email);
}

async function abrir(c: Cuenta | null): Promise<ConexionSse> {
  const s = await abrirSse(env.app, CANAL, c?.token);
  abiertas.push(s);
  return s;
}
/** Abre el canal y devuelve la conexión junto con el snapshot inicial. */
async function abrirYLeer(c: Cuenta): Promise<{ s: ConexionSse; lista: ItemPriorizado[] }> {
  const s = await abrir(c);
  expect(s.status).toBe(200);
  return { s, lista: ((await s.siguiente()) as Evento).data };
}
const idsDe = (lista: ItemPriorizado[]): string[] => lista.map((i) => i.alert.id);

/** Lee eventos hasta que `pred` se cumpla (devuelve esa lista) o se acabe el tiempo (falla). */
async function esperarLista(s: ConexionSse, pred: (l: ItemPriorizado[]) => boolean, ms = 6000): Promise<ItemPriorizado[]> {
  const limite = Date.now() + ms;
  let ultima: ItemPriorizado[] = [];
  while (Date.now() < limite) {
    let e: Evento;
    try {
      e = (await s.siguiente(Math.max(50, limite - Date.now()))) as Evento;
    } catch {
      break;
    }
    ultima = e.data;
    if (pred(ultima)) return ultima;
  }
  throw new Error(`Ninguna lista cumplió la condición; última: ${JSON.stringify(idsDe(ultima))}`);
}

/** Lee todo lo que llegue durante `ms` y devuelve las listas recibidas. */
async function leerDurante(s: ConexionSse, ms: number): Promise<ItemPriorizado[][]> {
  const limite = Date.now() + ms;
  const listas: ItemPriorizado[][] = [];
  while (Date.now() < limite) {
    try {
      listas.push(((await s.siguiente(Math.max(50, limite - Date.now()))) as Evento).data);
    } catch {
      break;
    }
  }
  return listas;
}
async function nuncaAparece(s: ConexionSse, alertId: string, ms = 1800): Promise<void> {
  const listas = await leerDurante(s, ms);
  for (const l of listas) expect(idsDe(l)).not.toContain(alertId);
}

const postAlerta = (t: string, cuerpo: Record<string, unknown> = {}) =>
  request(env.app.server)
    .post(`${API}/alerts`)
    .set('Authorization', `Bearer ${t}`)
    .send({ triggerMethod: 'tap', triggeredAt: new Date().toISOString(), location: punto(0.002), heading: 35, photoPath: null, ...cuerpo });
const postUbicacion = (t: string, alertId: string, location: { lat: number; lng: number }) =>
  request(env.app.server).post(`${API}/alerts/${alertId}/locations`).set('Authorization', `Bearer ${t}`).send({ location });
const putUbicacionGuardia = (t: string, location: { lat: number; lng: number }) =>
  request(env.app.server).put(`${API}/guard/location`).set('Authorization', `Bearer ${t}`).send({ location });

/** Alerta `searching` con ubicación para un usuario protegido nuevo. */
async function alertaEn(location: { lat: number; lng: number }, extra: Record<string, unknown> = {}) {
  const p = await protegido();
  return crearAlerta(env.prisma, p.id, { status: 'searching', lat: location.lat, lng: location.lng, ...extra });
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

describe('GET /events/guard/alerts: permisos (antes de abrir el stream)', () => {
  it('sin token -> 401 con el envoltorio', async () => {
    const s = await abrir(null);
    expect(s.status).toBe(401);
    expect(s.json).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it('token basura -> 401', async () => {
    const s = await abrirSse(env.app, CANAL, 'no.es.jwt');
    abiertas.push(s);
    expect(s.status).toBe(401);
  });

  it.each(['protegido', 'admin'] as const)('rol %s -> 403 FORBIDDEN, sin abrir stream', async (quien) => {
    const t = await conToken(env.usuarios[quien].id, env.usuarios[quien].email);
    const s = await abrir(t);
    expect(s.status).toBe(403);
    expect(s.json).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    expect(s.headers['content-type']).not.toMatch(/event-stream/);
  });

  it('guardia dado de baja (token anterior a la baja) -> 401 antes de abrir', async () => {
    const g = await guardia();
    await env.prisma.user.update({ where: { id: g.id }, data: { isActive: false } });
    const s = await abrir(g);
    expect(s.status).toBe(401);
    expect(s.json).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it('D25: si lo dan de baja con el stream abierto, el siguiente ping avisa UNAUTHORIZED y cierra', async () => {
    const g = await guardia();
    const { s } = await abrirYLeer(g);
    await env.prisma.user.update({ where: { id: g.id }, data: { isActive: false } });
    const limite = Date.now() + 4000;
    let ultimo: unknown;
    while (Date.now() < limite) {
      ultimo = await s.siguiente(Math.max(50, limite - Date.now())).catch(() => undefined);
      if (ultimo && typeof ultimo === 'object' && 'error' in ultimo) break;
    }
    expect(ultimo).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });
});

describe('GET /events/guard/alerts: snapshot inicial y visibilidad (G-03, D22)', () => {
  it('abre un stream sin caché; sin alertas manda { data: [] }', async () => {
    const g = await guardia();
    const s = await abrir(g);
    expect(s.status).toBe(200);
    expect(s.headers['content-type']).toMatch(/^text\/event-stream/);
    expect(s.headers['cache-control']).toBe('no-store');
    expect(await s.siguiente()).toEqual({ data: [] });
  });

  it('una alerta searching con ubicación dentro de la cobertura y en turno aparece, con la forma de PrioritizedAlert', async () => {
    const g = await guardia();
    const a = await alertaEn(punto(0.002));
    const { lista } = await abrirYLeer(g);
    expect(idsDe(lista)).toEqual([a.id]);
    const item = lista[0] as ItemPriorizado;
    expect(Object.keys(item).sort()).toEqual(['alert', 'distanceMeters', 'score', 'waitingMinutes']);
    expect(item.alert.status).toBe('searching');
    expect(item.alert.location).toEqual(punto(0.002));
    expect(item.waitingMinutes).toBeGreaterThanOrEqual(0);
    expect(item.score).toBeCloseTo(item.distanceMeters - item.waitingMinutes * 100, 6);
  });

  it('D23: userPhone siempre null en el listado, aunque el usuario tenga teléfono', async () => {
    const g = await guardia();
    const p = await protegido();
    await crearAlerta(env.prisma, p.id, { status: 'searching', lat: punto(0.001).lat, lng: CENTRO.lng });
    const { lista } = await abrirYLeer(g);
    expect(lista).toHaveLength(1);
    expect(lista[0]?.alert.userPhone).toBeNull();
    expect(JSON.stringify(lista)).not.toContain('7771112233');
  });

  it('D37: sin última ubicación, la distancia parte del centro de cobertura', async () => {
    const g = await guardia();
    const destino = punto(0.004, 0.002);
    await alertaEn(destino);
    const { lista } = await abrirYLeer(g);
    expect(lista[0]?.distanceMeters).toBe(haversineMeters(CENTRO, destino));
  });

  it('con última ubicación, la distancia parte de ella (no del centro)', async () => {
    const mia = punto(0.01);
    const g = await guardia({ lastLocationLat: mia.lat, lastLocationLng: mia.lng });
    const destino = punto(0.004);
    await alertaEn(destino);
    const { lista } = await abrirYLeer(g);
    expect(lista[0]?.distanceMeters).toBe(haversineMeters(mia, destino));
    expect(lista[0]?.distanceMeters).not.toBe(haversineMeters(CENTRO, destino));
  });

  it('fuera de turno -> lista vacía', async () => {
    const g = await guardia(FUERA_DE_TURNO());
    await alertaEn(punto(0.002));
    expect((await abrirYLeer(g)).lista).toEqual([]);
  });

  it('en un turno relativo a "ahora" -> la ve', async () => {
    const g = await guardia(EN_TURNO());
    const a = await alertaEn(punto(0.002));
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual([a.id]);
  });

  it('turno de 24 h (inicio = fin) -> la ve', async () => {
    const g = await guardia({ shiftStart: '08:30', shiftEnd: '08:30' });
    const a = await alertaEn(punto(0.002));
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual([a.id]);
  });

  it('turno que ya terminó hace un minuto -> lista vacía; turno que empieza en un minuto -> lista vacía', async () => {
    const termino = await guardia({ shiftStart: horaLocal(-180), shiftEnd: horaLocal(-1) });
    const empieza = await guardia({ shiftStart: horaLocal(1), shiftEnd: horaLocal(180) });
    await alertaEn(punto(0.002));
    expect((await abrirYLeer(termino)).lista).toEqual([]);
    expect((await abrirYLeer(empieza)).lista).toEqual([]);
  });

  it('sin cobertura asignada -> lista vacía', async () => {
    const g = await guardia({ coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null });
    await alertaEn(punto(0.002));
    expect((await abrirYLeer(g)).lista).toEqual([]);
  });

  it('alerta fuera del radio de cobertura -> no aparece; una dentro, sí', async () => {
    const g = await guardia();
    await alertaEn(FUERA);
    const dentro = await alertaEn(punto(0.002));
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual([dentro.id]);
  });

  it('el borde del radio: un punto apenas fuera del radio no aparece', async () => {
    const g = await guardia({ coverageRadiusMeters: 500 });
    // 0.0046 grados ~ 511 m (fuera), 0.0044 ~ 489 m (dentro).
    await alertaEn(punto(0.0046));
    const dentro = await alertaEn(punto(0.0044));
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual([dentro.id]);
  });

  it('pending_location (sin ubicación) no aparece', async () => {
    const g = await guardia();
    const p = await protegido();
    await crearAlerta(env.prisma, p.id, { status: 'pending_location' });
    expect((await abrirYLeer(g)).lista).toEqual([]);
  });

  it('searching sin ubicación no aparece', async () => {
    const g = await guardia();
    const p = await protegido();
    await crearAlerta(env.prisma, p.id, { status: 'searching' });
    expect((await abrirYLeer(g)).lista).toEqual([]);
  });

  it.each(['in_progress', 'guard_arrived', 'closed', 'no_response', 'escalated'] as const)(
    'una alerta en %s no aparece (solo searching sin asignar)',
    async (status) => {
      const g = await guardia();
      const p = await protegido();
      await crearAlerta(env.prisma, p.id, {
        status,
        lat: punto(0.002).lat,
        lng: CENTRO.lng,
        guardId: ['in_progress', 'guard_arrived', 'closed', 'escalated'].includes(status) ? g.id : null,
        acceptedAt: new Date(),
      });
      expect((await abrirYLeer(g)).lista).toEqual([]);
    },
  );

  it('una alerta in_progress de OTRO guardia tampoco aparece', async () => {
    const g = await guardia();
    const otro = await guardia();
    const p = await protegido();
    await crearAlerta(env.prisma, p.id, { status: 'in_progress', guardId: otro.id, lat: punto(0.002).lat, lng: CENTRO.lng, acceptedAt: new Date() });
    expect((await abrirYLeer(g)).lista).toEqual([]);
  });

  it('ignorada por él no aparece, pero sigue apareciendo para otro guardia (D22)', async () => {
    const yo = await guardia();
    const otro = await guardia();
    const ignorada = await alertaEn(punto(0.002));
    const normal = await alertaEn(punto(0.003));
    await env.prisma.alertIgnore.create({ data: { guardId: yo.id, alertId: ignorada.id } });
    expect(idsDe((await abrirYLeer(yo)).lista)).toEqual([normal.id]);
    expect(idsDe((await abrirYLeer(otro)).lista).sort()).toEqual([ignorada.id, normal.id].sort());
  });

  it('cada guardia recibe su propia lista y distancias (nunca un snapshot compartido)', async () => {
    const cerca = await guardia({ lastLocationLat: punto(0.0).lat, lastLocationLng: CENTRO.lng });
    const lejos = await guardia({ lastLocationLat: punto(0.015).lat, lastLocationLng: CENTRO.lng });
    await alertaEn(punto(0.001));
    const a = (await abrirYLeer(cerca)).lista[0] as ItemPriorizado;
    const b = (await abrirYLeer(lejos)).lista[0] as ItemPriorizado;
    expect(a.distanceMeters).toBeLessThan(b.distanceMeters);
  });
});

describe('GET /events/guard/alerts: orden (G-03, D24)', () => {
  it('la más cercana al guardia va primero', async () => {
    const g = await guardia({ lastLocationLat: punto(0.01).lat, lastLocationLng: CENTRO.lng });
    const lejana = await alertaEn(punto(-0.01));
    const cercana = await alertaEn(punto(0.008));
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual([cercana.id, lejana.id]);
  });

  it('una urgente (shake) va primero aunque esté más lejos', async () => {
    const g = await guardia({ lastLocationLat: punto(0.01).lat, lastLocationLng: CENTRO.lng });
    const cercana = await alertaEn(punto(0.009));
    const urgente = await alertaEn(punto(-0.01), { triggerMethod: 'shake' });
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual([urgente.id, cercana.id]);
  });

  it('la espera (receivedAt, hora del servidor) sube la prioridad; triggeredAt del cliente no cuenta', async () => {
    const g = await guardia({ lastLocationLat: CENTRO.lat, lastLocationLng: CENTRO.lng });
    // ~222 m con 10 min de espera -> score ~ -778; ~111 m recién llegada -> ~111.
    const vieja = await alertaEn(punto(0.002), { receivedAt: new Date(Date.now() - 10 * 60_000) });
    const nueva = await alertaEn(punto(0.001), {
      // El reloj del teléfono dice que fue hace una hora: no debe influir (D24).
      triggeredAt: new Date(Date.now() - 3_600_000),
    });
    const { lista } = await abrirYLeer(g);
    expect(idsDe(lista)).toEqual([vieja.id, nueva.id]);
    expect(lista[0]?.waitingMinutes).toBeGreaterThanOrEqual(9.9);
    expect(lista[1]?.waitingMinutes).toBeLessThan(1);
  });

  it('empate exacto: desempata receivedAt más antiguo y luego id', async () => {
    const g = await guardia({ lastLocationLat: CENTRO.lat, lastLocationLng: CENTRO.lng });
    const mismaHora = new Date(Date.now() - 120_000);
    const a1 = await alertaEn(punto(0.002), { receivedAt: mismaHora });
    const a2 = await alertaEn(punto(0.002), { receivedAt: mismaHora });
    const esperado = [a1.id, a2.id].sort();
    expect(idsDe((await abrirYLeer(g)).lista)).toEqual(esperado);
  });
});

describe('GET /events/guard/alerts: cambios en vivo (D34)', () => {
  it('G-06: cuando el guardia hace PUT /guard/location llega un snapshot reordenado por su nueva posición', async () => {
    const norte = punto(0.01);
    const sur = punto(-0.01);
    const g = await guardia({ lastLocationLat: norte.lat, lastLocationLng: norte.lng });
    const alN = await alertaEn(norte);
    const alS = await alertaEn(sur);
    const { s, lista } = await abrirYLeer(g);
    expect(idsDe(lista)).toEqual([alN.id, alS.id]);

    expect((await putUbicacionGuardia(g.token, sur)).status).toBe(200);
    const nueva = await esperarLista(s, (l) => l[0]?.alert.id === alS.id);
    expect(idsDe(nueva)).toEqual([alS.id, alN.id]);
    expect(nueva[0]?.distanceMeters).toBeLessThan(1);

    expect((await putUbicacionGuardia(g.token, norte)).status).toBe(200);
    expect(idsDe(await esperarLista(s, (l) => l[0]?.alert.id === alN.id))).toEqual([alN.id, alS.id]);
  });

  it('el PUT /guard/location de OTRO guardia no cambia mi lista', async () => {
    const norte = punto(0.01);
    const sur = punto(-0.01);
    const yo = await guardia({ lastLocationLat: norte.lat, lastLocationLng: norte.lng });
    const otro = await guardia();
    const alN = await alertaEn(norte);
    const alS = await alertaEn(sur);
    const { s } = await abrirYLeer(yo);
    expect((await putUbicacionGuardia(otro.token, sur)).status).toBe(200);
    const listas = await leerDurante(s, 1800);
    for (const l of listas) expect(idsDe(l)).toEqual([alN.id, alS.id]);
  });

  it('U-05: una alerta nueva (POST /alerts con ubicación) aparece en el stream de los guardias que la ven y NO en los demás', async () => {
    const ve1 = await guardia();
    const ve2 = await guardia();
    const sinCobertura = await guardia({ coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null });
    const fueraDeTurno = await guardia(FUERA_DE_TURNO());
    const lejos = await guardia({ coverageCenterLat: FUERA.lat, coverageCenterLng: FUERA.lng, coverageRadiusMeters: 500 });
    const conexiones = {
      ve1: await abrirYLeer(ve1),
      ve2: await abrirYLeer(ve2),
      sinCobertura: await abrirYLeer(sinCobertura),
      fueraDeTurno: await abrirYLeer(fueraDeTurno),
      lejos: await abrirYLeer(lejos),
    };
    for (const { lista } of Object.values(conexiones)) expect(lista).toEqual([]);

    const p = await protegido();
    const res = await postAlerta(p.token);
    expect(res.status).toBe(201);
    const id = res.body.data.id as string;

    for (const quien of ['ve1', 've2'] as const) {
      const lista = await esperarLista(conexiones[quien].s, (l) => idsDe(l).includes(id));
      expect(lista[0]?.alert.userPhone).toBeNull();
      expect(lista[0]?.alert.status).toBe('searching');
    }
    await Promise.all(
      (['sinCobertura', 'fueraDeTurno', 'lejos'] as const).map((quien) => nuncaAparece(conexiones[quien].s, id, 1500)),
    );
  }, 30_000);

  it('pending_location que recibe ubicación (POST /alerts/:id/locations) aparece en el stream', async () => {
    const g = await guardia();
    const p = await protegido();
    const creada = await postAlerta(p.token, { location: null });
    expect(creada.status).toBe(201);
    const id = creada.body.data.id as string;
    expect(creada.body.data.status).toBe('pending_location');

    const { s, lista } = await abrirYLeer(g);
    expect(lista).toEqual([]);
    expect((await postUbicacion(p.token, id, punto(0.002))).status).toBe(200);
    const nueva = await esperarLista(s, (l) => idsDe(l).includes(id));
    expect(nueva.find((i) => i.alert.id === id)?.alert.location).toEqual(punto(0.002));
  });

  it('un movimiento del usuario en searching manda un snapshot nuevo con la ubicación y distancia actualizadas', async () => {
    const g = await guardia();
    const p = await protegido();
    const creada = await postAlerta(p.token, { location: punto(0.002) });
    const id = creada.body.data.id as string;
    const { s, lista } = await abrirYLeer(g);
    expect(lista[0]?.alert.location).toEqual(punto(0.002));

    const destino = punto(0.006, 0.001);
    expect((await postUbicacion(p.token, id, destino)).status).toBe(200);
    const nueva = await esperarLista(s, (l) => l[0]?.alert.location?.lat === destino.lat);
    expect(nueva[0]?.distanceMeters).toBe(haversineMeters(CENTRO, destino));
  });

  it('si el usuario se mueve fuera de la cobertura, la alerta sale de la lista del guardia', async () => {
    const g = await guardia();
    const p = await protegido();
    const id = (await postAlerta(p.token, { location: punto(0.002) })).body.data.id as string;
    const { s, lista } = await abrirYLeer(g);
    expect(idsDe(lista)).toEqual([id]);
    expect((await postUbicacion(p.token, id, FUERA)).status).toBe(200);
    expect(await esperarLista(s, (l) => l.length === 0)).toEqual([]);
  });

  it('el ping manda un snapshot nuevo aunque nadie publique (refleja el paso del tiempo y los cambios en la base)', async () => {
    const g = await guardia();
    const { s, lista } = await abrirYLeer(g);
    expect(lista).toEqual([]);
    // Cambio directo en la base: no pasa por el servicio, así que no hay aviso en el bus.
    const a = await alertaEn(punto(0.002));
    const nueva = await esperarLista(s, (l) => idsDe(l).includes(a.id), 4000);
    expect(idsDe(nueva)).toEqual([a.id]);
  });

  it('una alerta que sale de searching (la toma otro guardia) desaparece de la lista en el siguiente snapshot', async () => {
    const g = await guardia();
    const otro = await guardia();
    const a = await alertaEn(punto(0.002));
    const { s } = await abrirYLeer(g);
    await env.prisma.alert.update({ where: { id: a.id }, data: { status: 'in_progress', guardId: otro.id, acceptedAt: new Date() } });
    expect(await esperarLista(s, (l) => l.length === 0, 4000)).toEqual([]);
  });
});

describe('GET /events/guard/alerts: límite de conexiones por (usuario, canal)', () => {
  it('el 4.º stream del mismo guardia cierra el más antiguo; los otros siguen abiertos', async () => {
    const g = await guardia();
    const abiertos: ConexionSse[] = [];
    for (let i = 0; i < 3; i++) {
      const s = await abrir(g);
      await s.siguiente();
      abiertos.push(s);
    }
    const cuarto = await abrir(g);
    expect(await cuarto.siguiente()).toEqual({ data: [] });
    const limite = Date.now() + 2000;
    while (!abiertos[0]?.cerrado() && Date.now() < limite) await new Promise((r) => setTimeout(r, 20));
    expect(abiertos[0]?.cerrado()).toBe(true);
    expect(abiertos[1]?.cerrado()).toBe(false);
    expect(abiertos[2]?.cerrado()).toBe(false);
    expect(cuarto.cerrado()).toBe(false);
  });
});

describe('listAvailable con reloj inyectado (turno que cruza medianoche, D1, D22)', () => {
  // America/Mexico_City es UTC-6 todo el año desde 2022.
  const LOCAL_2330 = new Date('2026-06-02T05:30:00.000Z'); // 23:30 del 1 de junio
  const LOCAL_0200 = new Date('2026-06-02T08:00:00.000Z'); // 02:00 del 2 de junio
  const LOCAL_1200 = new Date('2026-06-02T18:00:00.000Z'); // 12:00 del 2 de junio
  const servicio = (ahora: Date) =>
    createGuardService({
      prisma: env.prisma,
      serialize: { photoUrl: () => null, guardMetersPerMinute: 100 },
      timeZone: ZONA,
      waitMetersPerMinute: 100,
      now: () => ahora,
    });

  it('turno 22:00-06:00: dentro a las 23:30 y a las 02:00 (ambos lados de la medianoche) y fuera a las 12:00', async () => {
    const g = await guardia({ shiftStart: '22:00', shiftEnd: '06:00' });
    const a = await alertaEn(punto(0.002));
    expect(idsDe(await servicio(LOCAL_2330).listAvailable(g.id))).toEqual([a.id]);
    expect(idsDe(await servicio(LOCAL_0200).listAvailable(g.id))).toEqual([a.id]);
    expect(await servicio(LOCAL_1200).listAvailable(g.id)).toEqual([]);
  });

  it('turno 22:00-06:00: a las 06:00 en punto ya terminó y a las 22:00 en punto ya empezó', async () => {
    const g = await guardia({ shiftStart: '22:00', shiftEnd: '06:00' });
    await alertaEn(punto(0.002));
    expect(await servicio(new Date('2026-06-02T12:00:00.000Z')).listAvailable(g.id)).toEqual([]); // 06:00 local
    expect(await servicio(new Date('2026-06-03T04:00:00.000Z')).listAvailable(g.id)).toHaveLength(1); // 22:00 local
  });

  it('waitingMinutes sale de receivedAt y del reloj inyectado, y el score usa el peso configurado', async () => {
    const g = await guardia({ lastLocationLat: CENTRO.lat, lastLocationLng: CENTRO.lng });
    const destino = punto(0.002);
    await alertaEn(destino, { receivedAt: new Date('2026-06-02T05:00:00.000Z') });
    const [item] = await servicio(LOCAL_2330).listAvailable(g.id);
    expect(item?.waitingMinutes).toBe(30);
    expect(item?.distanceMeters).toBe(haversineMeters(CENTRO, destino));
    expect(item?.score).toBe(haversineMeters(CENTRO, destino) - 30 * 100);
  });

  it('un guardia dado de baja recibe lista vacía aunque haya alertas visibles', async () => {
    const g = await guardia();
    await alertaEn(punto(0.002));
    await env.prisma.user.update({ where: { id: g.id }, data: { isActive: false } });
    expect(await servicio(LOCAL_2330).listAvailable(g.id)).toEqual([]);
  });
});
