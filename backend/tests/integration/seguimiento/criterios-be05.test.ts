// BE-05 (issue #55) · Criterios de terminado de "Seguimiento, llegada y cierre", de extremo a
// extremo con PostgreSQL real y solo rutas públicas del usuario y del guardia:
//   1. El guardia ve la posición del usuario actualizándose.
//   2. El usuario nunca recibe la posición del guardia.
//   3. La llegada fuera de la geocerca es rechazada.
//   4. Una alerta sin guardia asignado no se puede cerrar.
//   + Al cerrarse la alerta deja de transmitirse la ubicación.
//
// NOTA: necesita DATABASE_URL_TEST. SSE_PING_SECONDS = 60: lo que llega por el stream es aviso inmediato.
import request from 'supertest';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { crearEntorno, type Entorno } from '../auth/helpers.js';
import {
  API,
  CENTRO_ALERTA,
  JUNTO_A_ALERTA,
  LEJOS_DE_ALERTA,
  aceptarAlerta,
  asignarGuardia,
  moverGuardia,
  prepararPerfilGuardia,
  registrarLlegada,
  tokenDe,
} from '../flujo/guardia-flujo.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

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

async function crearAlerta(): Promise<string> {
  const res = await request(env.app.server)
    .post(`${API}/alerts`)
    .set(auth(tokenUsuario))
    .send({ triggerMethod: 'tap', triggeredAt: new Date().toISOString(), location: CENTRO_ALERTA, heading: 35, photoPath: null });
  expect(res.status, JSON.stringify(res.body)).toBe(201);
  return res.body.data.id as string;
}

const enviarUbicacion = (alertId: string, location: { lat: number; lng: number }) =>
  request(env.app.server).post(`${API}/alerts/${alertId}/locations`).set(auth(tokenUsuario)).send({ location });

const confirmar = (alertId: string) =>
  request(env.app.server).post(`${API}/alerts/${alertId}/confirm`).set(auth(tokenUsuario));

async function abrir(ruta: string, t: string): Promise<ConexionSse> {
  const c = await abrirSse(env.app, `${API}${ruta}`, t);
  abiertas.push(c);
  return c;
}

/** ¿Aparece en el JSON algún número igual a una coordenada del guardia? */
function contieneCoordenada(valor: unknown, punto: { lat: number; lng: number }): boolean {
  const texto = JSON.stringify(valor);
  return texto.includes(String(punto.lat)) && texto.includes(String(punto.lng));
}

describe('BE-05 · criterios de terminado (issue #55)', () => {
  it('1. el guardia ve la posición del usuario actualizándose en tiempo real', async () => {
    const id = await crearAlerta();
    await asignarGuardia(env, tokenGuardia, id, 'in_progress', LEJOS_DE_ALERTA);
    const c = await abrir(`/events/guard/alerts/${id}`, tokenGuardia);
    expect(((await c.siguiente()) as { data: { location: unknown } }).data.location).toEqual(CENTRO_ALERTA);

    const nueva = { lat: 18.8412, lng: -99.1785 };
    expect((await enviarUbicacion(id, nueva)).status).toBe(200);

    const e = (await c.siguiente()) as { data: { location: unknown; status: string } };
    expect(e.data.status).toBe('in_progress');
    expect(e.data.location).toEqual(nueva);
  });

  it('2. el usuario nunca recibe la posición del guardia (REST ni tiempo real), solo nombre y ETA', async () => {
    const id = await crearAlerta();
    const canal = await abrir('/events/alerts/active', tokenUsuario);
    await canal.siguiente();
    await asignarGuardia(env, tokenGuardia, id, 'in_progress', LEJOS_DE_ALERTA);

    const evento = (await canal.siguiente()) as { data: Record<string, unknown> };
    const mias = await request(env.app.server).get(`${API}/alerts/mine`).set(auth(tokenUsuario));

    for (const vista of [evento.data, mias.body.data[0] as Record<string, unknown>]) {
      expect(vista['guardName']).toBe('Nombre guardia');
      expect(vista['etaSeconds']).toEqual(expect.any(Number));
      // Las mismas 20 claves del contrato: ninguna trae la ubicación del guardia.
      expect(Object.keys(vista)).toHaveLength(20);
      expect(vista['location']).toEqual(CENTRO_ALERTA); // la del usuario, no la del guardia
      expect(contieneCoordenada(vista, LEJOS_DE_ALERTA)).toBe(false);
    }
  });

  it('3. la llegada fuera de la geocerca es rechazada y no cambia la alerta', async () => {
    const id = await crearAlerta();
    await moverGuardia(env, tokenGuardia, LEJOS_DE_ALERTA);
    expect((await aceptarAlerta(env, tokenGuardia, id)).status).toBe(200);

    const res = await registrarLlegada(env, tokenGuardia, id);

    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('OUTSIDE_GEOFENCE');
    expect(res.body.error.remainingMeters).toBeGreaterThan(0);
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id } })).status).toBe('in_progress');

    // Ya dentro del radio, la llegada se registra con hora.
    await moverGuardia(env, tokenGuardia, JUNTO_A_ALERTA);
    const llego = await registrarLlegada(env, tokenGuardia, id);
    expect(llego.status).toBe(200);
    expect(llego.body.data.arrivedAt).toEqual(expect.any(String));
  });

  it('4. una alerta sin guardia asignado no se puede cerrar (ni buscando ni con el guardia en camino)', async () => {
    const id = await crearAlerta();
    const buscando = await confirmar(id);
    expect(buscando.status).toBe(409);
    expect(buscando.body.error.message).toBe('Solo puedes confirmar cuando el guardia ya llegó');

    await asignarGuardia(env, tokenGuardia, id, 'in_progress');
    expect((await confirmar(id)).status).toBe(409);
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id } })).status).toBe('in_progress');
  });

  it('cerrar con guardia en el lugar funciona y desde ahí deja de transmitirse la ubicación', async () => {
    const id = await crearAlerta();
    await asignarGuardia(env, tokenGuardia, id, 'guard_arrived');

    const cerrada = await confirmar(id);
    expect(cerrada.status).toBe(200);
    expect(cerrada.body.data.status).toBe('closed');

    const tarde = await enviarUbicacion(id, { lat: 18.9, lng: -99.1 });
    expect(tarde.status).toBe(409);
    expect(tarde.body.error.message).toBe('Tu alerta ya no está activa');
    const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
    expect({ lat: a.lat, lng: a.lng }).toEqual(CENTRO_ALERTA);
  });
});
