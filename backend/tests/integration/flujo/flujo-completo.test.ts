// BE-04 paso 8 · Flujo de extremo a extremo con PostgreSQL real y solo rutas públicas (D46):
// U-03 (crear) -> G-04 (el guardia la ve) -> G-05 (accept) -> U-08 (nombre y ETA del dueño, D47)
// -> G-06 (se acerca) -> G-07 (arrive) -> U-09 (confirma) -> historial y métricas del guardia (D41).
// Regla K: el guardia nunca pasa la alerta a closed.
//
// NOTA: necesita DATABASE_URL_TEST. SSE_PING_SECONDS = 60: todo lo que llega por el stream es aviso inmediato.
import request from 'supertest';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { etaSeconds, roundEtaUp } from '../../../src/domain/alert-rules.js';
import { snapToGrid } from '../../../src/domain/geo.js';
import { configPrueba, crearEntorno, type Entorno } from '../auth/helpers.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';
import {
  API,
  CENTRO_ALERTA,
  JUNTO_A_ALERTA,
  LEJOS_DE_ALERTA,
  aceptarAlerta,
  moverGuardia,
  prepararPerfilGuardia,
  registrarLlegada,
  tokenDe,
} from './guardia-flujo.js';

const cfg = configPrueba();
const MSG_CONFIRMAR = 'Solo puedes confirmar cuando el guardia ya llegó';

let env: Entorno;
let tokenUsuario: string;
let tokenGuardia: string;
const abiertas: ConexionSse[] = [];

beforeAll(async () => {
  env = await crearEntorno({ SSE_PING_SECONDS: '60' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});
beforeEach(async () => {
  await env.prisma.alert.deleteMany();
  await prepararPerfilGuardia(env, env.usuarios.guardia.id);
  tokenUsuario = await tokenDe(env, env.usuarios.protegido.email);
  tokenGuardia = await tokenDe(env, env.usuarios.guardia.email);
});
afterEach(() => {
  for (const c of abiertas.splice(0)) c.cerrar();
});

const auth = (t: string) => ({ Authorization: `Bearer ${t}` });
const get = (ruta: string, t: string) => request(env.app.server).get(`${API}${ruta}`).set(auth(t));
const post = (ruta: string, t: string) => request(env.app.server).post(`${API}${ruta}`).set(auth(t));

const crearAlerta = (triggerMethod = 'tap') =>
  request(env.app.server)
    .post(`${API}/alerts`)
    .set(auth(tokenUsuario))
    .send({ triggerMethod, triggeredAt: new Date().toISOString(), location: CENTRO_ALERTA, heading: 35, photoPath: null });

async function abrir(ruta: string, t: string): Promise<ConexionSse> {
  const c = await abrirSse(env.app, `${API}${ruta}`, t);
  abiertas.push(c);
  expect(c.status).toBe(200);
  return c;
}

/** Lee eventos del canal hasta que `pred` se cumpla; falla con el último evento si se acaba el tiempo. */
async function hasta<T>(c: ConexionSse, pred: (e: T) => boolean, ms = 6000): Promise<T> {
  const limite = Date.now() + ms;
  let ultimo: unknown = undefined;
  while (Date.now() < limite) {
    try {
      ultimo = await c.siguiente(Math.max(50, limite - Date.now()));
    } catch {
      break;
    }
    if (pred(ultimo as T)) return ultimo as T;
  }
  throw new Error(`Ningún evento cumplió la condición; último: ${JSON.stringify(ultimo)}`);
}

interface VistaDueno {
  data: { id: string; status: string; guardName: string | null; etaSeconds: number | null; guardId: string | null } | null;
}
interface ListaGuardia {
  data: Array<{ alert: { id: string; status: string } }>;
}

/** ETA que define el contrato para el dueño (D47) con el guardia en `posicion`. */
const etaDueno = (posicion: { lat: number; lng: number }) =>
  roundEtaUp(
    etaSeconds('in_progress', snapToGrid(posicion, cfg.ETA_GUARD_GRID_METERS), CENTRO_ALERTA, cfg.GUARD_METERS_PER_MINUTE),
    cfg.ETA_ROUNDING_SECONDS,
  );

async function estadoEnBase(id: string) {
  return (await env.prisma.alert.findUniqueOrThrow({ where: { id } })).status;
}

describe('Flujo completo de una alerta (U-03, G-04, G-05, G-06, G-07, U-08, U-09)', () => {
  it('protegido crea -> guardia acepta -> dueño ve in_progress con ETA -> guardia llega -> dueño confirma -> closed', async () => {
    const dueno = await abrir('/events/alerts/active', tokenUsuario);
    expect(await dueno.siguiente()).toEqual({ data: null });
    const canalGuardia = await abrir('/events/guard/alerts', tokenGuardia);
    expect(((await canalGuardia.siguiente()) as ListaGuardia).data).toEqual([]);

    // U-03: el usuario crea la alerta con ubicación.
    const creada = await crearAlerta();
    expect(creada.status).toBe(201);
    expect(creada.body.data.status).toBe('searching');
    const id = creada.body.data.id as string;
    expect(((await dueno.siguiente()) as VistaDueno).data?.status).toBe('searching');

    // G-04: el guardia la ve en su canal y por GET /guard/alerts/:id.
    const lista = await hasta<ListaGuardia>(canalGuardia, (l) => l.data.some((i) => i.alert.id === id));
    expect(lista.data.find((i) => i.alert.id === id)?.alert.status).toBe('searching');
    const detalle = await get(`/guard/alerts/${id}`, tokenGuardia);
    expect(detalle.status).toBe(200);
    expect(detalle.body.data.status).toBe('searching');
    expect(detalle.body.data.guardId).toBeNull();

    // G-06 + G-05: reporta su posición (lejos) y acepta.
    await moverGuardia(env, tokenGuardia, LEJOS_DE_ALERTA);
    const acepto = await aceptarAlerta(env, tokenGuardia, id);
    expect(acepto.status).toBe(200);
    expect(acepto.body.data.status).toBe('in_progress');
    expect(acepto.body.data.guardId).toBe(env.usuarios.guardia.id);

    // U-08 · D47: el dueño ve in_progress con el nombre y el ETA ya redondeado.
    const enCamino = await hasta<VistaDueno>(dueno, (e) => e.data?.status === 'in_progress');
    expect(enCamino.data?.guardName).toBe('Nombre guardia');
    const etaLejos = etaDueno(LEJOS_DE_ALERTA);
    expect(etaLejos).toBeGreaterThan(0);
    expect(etaLejos! % cfg.ETA_ROUNDING_SECONDS).toBe(0);
    expect(enCamino.data?.etaSeconds).toBe(etaLejos);

    // Antes de llegar, el dueño no puede confirmar y el guardia no puede cerrar (regla K).
    const confirmaPronto = await post(`/alerts/${id}/confirm`, tokenUsuario);
    expect(confirmaPronto.status).toBe(409);
    expect(confirmaPronto.body.error).toEqual({ code: 'INVALID_STATE', message: MSG_CONFIRMAR });
    expect((await post(`/alerts/${id}/confirm`, tokenGuardia)).status).toBe(403);
    expect(await estadoEnBase(id)).toBe('in_progress');

    // Estando lejos de la geocerca, llegar es 422 y no cambia nada.
    const llegaLejos = await registrarLlegada(env, tokenGuardia, id);
    expect(llegaLejos.status).toBe(422);
    expect(llegaLejos.body.error.code).toBe('OUTSIDE_GEOFENCE');
    expect(await estadoEnBase(id)).toBe('in_progress');

    // G-06: se acerca; el dueño recibe el ETA menor.
    await moverGuardia(env, tokenGuardia, JUNTO_A_ALERTA);
    const etaCerca = etaDueno(JUNTO_A_ALERTA);
    const acercandose = await hasta<VistaDueno>(dueno, (e) => e.data?.etaSeconds === etaCerca);
    expect(acercandose.data?.status).toBe('in_progress');
    expect(etaCerca!).toBeLessThan(etaLejos!);

    // G-07: llegada dentro de la geocerca.
    const llego = await registrarLlegada(env, tokenGuardia, id);
    expect(llego.status).toBe(200);
    expect(llego.body.data.status).toBe('guard_arrived');
    const llegada = await hasta<VistaDueno>(dueno, (e) => e.data?.status === 'guard_arrived');
    expect(llegada.data?.guardName).toBe('Nombre guardia');
    expect(llegada.data?.etaSeconds).toBeNull();

    // Regla K: llegado el guardia, aún no puede cerrar ni repetir la llegada.
    expect((await post(`/alerts/${id}/confirm`, tokenGuardia)).status).toBe(403);
    expect((await registrarLlegada(env, tokenGuardia, id)).status).toBe(409);
    expect(await estadoEnBase(id)).toBe('guard_arrived');

    // U-09: solo el dueño confirma.
    const confirma = await post(`/alerts/${id}/confirm`, tokenUsuario);
    expect(confirma.status).toBe(200);
    expect(confirma.body.data.status).toBe('closed');
    expect(confirma.body.data.guardName).toBe('Nombre guardia');
    await hasta<VistaDueno>(dueno, (e) => e.data === null);
    expect(await estadoEnBase(id)).toBe('closed');

    // Historial y métricas del guardia (D41).
    const historial = await get('/guard/history', tokenGuardia);
    expect(historial.status).toBe(200);
    expect((historial.body.data as Array<{ id: string; status: string }>).map((a) => [a.id, a.status])).toEqual([[id, 'closed']]);
    const metricas = await get('/guard/metrics', tokenGuardia);
    expect(metricas.status).toBe(200);
    expect(metricas.body.data.attendedCount).toBe(1);
    expect(metricas.body.data.escalatedCount).toBe(0);
    expect(Number.isInteger(metricas.body.data.avgAcceptanceSeconds)).toBe(true);
    expect(Number.isInteger(metricas.body.data.avgArrivalSeconds)).toBe(true);

    // alert_status_history: exactamente estos cuatro pasos, con sus actores.
    const pasos = await env.prisma.alertStatusHistory.findMany({ where: { alertId: id }, orderBy: { at: 'asc' } });
    expect(pasos.map((p) => [p.fromStatus, p.toStatus, p.actorId])).toEqual([
      [null, 'searching', env.usuarios.protegido.id],
      ['searching', 'in_progress', env.usuarios.guardia.id],
      ['in_progress', 'guard_arrived', env.usuarios.guardia.id],
      ['guard_arrived', 'closed', env.usuarios.protegido.id],
    ]);

    // Ya cerrada, el guardia no puede reabrirla ni repetir la llegada.
    expect((await registrarLlegada(env, tokenGuardia, id)).status).toBe(409);
    expect(await estadoEnBase(id)).toBe('closed');
  }, 60_000);

  it('el guardia no puede cerrar la alerta con ninguna ruta (regla K)', async () => {
    const id = (await crearAlerta('hold')).body.data.id as string;
    await moverGuardia(env, tokenGuardia, JUNTO_A_ALERTA);
    expect((await aceptarAlerta(env, tokenGuardia, id)).status).toBe(200);
    expect((await registrarLlegada(env, tokenGuardia, id)).status).toBe(200);

    expect((await post(`/guard/alerts/${id}/close`, tokenGuardia)).status).toBe(404);
    expect((await post(`/guard/alerts/${id}/confirm`, tokenGuardia)).status).toBe(404);
    expect((await post(`/alerts/${id}/confirm`, tokenGuardia)).status).toBe(403);
    expect((await aceptarAlerta(env, tokenGuardia, id)).status).toBe(409);

    expect(await estadoEnBase(id)).toBe('guard_arrived');
    expect(await env.prisma.alertStatusHistory.count({ where: { alertId: id, toStatus: 'closed' } })).toBe(0);
  }, 60_000);
});
