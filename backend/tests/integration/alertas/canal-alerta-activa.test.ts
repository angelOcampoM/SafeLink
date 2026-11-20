// BE-03 · Canal en tiempo real alerts/active (SSE, D3, D26) contra la base de pruebas.
// U-07 indicador · U-08 estados de la pantalla de espera · U-09 vuelve al botón al cerrar.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { crearEntorno, login, logout, type Entorno } from '../auth/helpers.js';
import { asignarGuardia, prepararPerfilGuardia, tokenDe } from '../flujo/guardia-flujo.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

const API = '/api/v1';
const CANAL = `${API}/events/alerts/active`;

let env: Entorno;
let tokenUsuario: string;
const abiertas: ConexionSse[] = [];

beforeAll(async () => {
  env = await crearEntorno({ SSE_PING_SECONDS: '1', SSE_MAX_CONNECTIONS_PER_USER: '2' });
}, 120_000);
afterAll(async () => {
  for (const c of abiertas) c.cerrar();
  await env.cerrar();
});

beforeEach(async () => {
  for (const c of abiertas.splice(0)) c.cerrar();
  await env.prisma.alert.deleteMany();
  tokenUsuario = await token(env.usuarios.protegido.email);
});

async function token(email: string): Promise<string> {
  const res = await login(env.app, email);
  return res.body.data.accessToken as string;
}

/** Abre el canal con el token del usuario, con otro token, o `null` para ir sin token. */
async function abrir(t: string | null = tokenUsuario): Promise<ConexionSse> {
  const c = await abrirSse(env.app, CANAL, t ?? undefined);
  abiertas.push(c);
  return c;
}

const crear = (body: Record<string, unknown> = {}) =>
  request(env.app.server)
    .post(`${API}/alerts`)
    .set('Authorization', `Bearer ${tokenUsuario}`)
    .send({ triggerMethod: 'tap', triggeredAt: new Date().toISOString(), location: { lat: 18.84, lng: -99.18 }, heading: 35, photoPath: null, ...body });

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe('GET /events/alerts/active', () => {
  it('abre un stream sin caché y manda el estado actual al conectar (sin alerta: null)', async () => {
    const c = await abrir();
    expect(c.status).toBe(200);
    expect(c.headers['content-type']).toMatch(/^text\/event-stream/);
    expect(c.headers['cache-control']).toBe('no-store');
    expect(await c.siguiente()).toEqual({ data: null });
  });

  it('U-08: al crear la alerta llega un snapshot nuevo con "buscando guardia"', async () => {
    const c = await abrir();
    await c.siguiente();
    await crear();
    const e = (await c.siguiente()) as { data: { status: string; userId: string } };
    expect(e.data.status).toBe('searching');
    expect(e.data.userId).toBe(env.usuarios.protegido.id);
  });

  it('U-06 · U-07: la primera ubicación publica una alerta pendiente y el canal lo refleja', async () => {
    const creada = await crear({ location: null });
    const id = creada.body.data.id as string;
    const c = await abrir();
    expect(((await c.siguiente()) as { data: { status: string } }).data.status).toBe('pending_location');

    await request(env.app.server)
      .post(`${API}/alerts/${id}/locations`)
      .set('Authorization', `Bearer ${tokenUsuario}`)
      .send({ location: { lat: 18.84, lng: -99.18 } });

    const e = (await c.siguiente()) as { data: { status: string; location: unknown } };
    expect(e.data.status).toBe('searching');
    expect(e.data.location).toEqual({ lat: 18.84, lng: -99.18 });
  });

  it('U-09: al confirmar la atención el canal manda null (vuelve el botón de alerta)', async () => {
    const creada = await crear();
    const id = creada.body.data.id as string;
    // D46: el guardia llega por las rutas reales (PUT /guard/location, accept y arrive).
    await prepararPerfilGuardia(env, env.usuarios.guardia.id);
    await asignarGuardia(env, await tokenDe(env, env.usuarios.guardia.email), id, 'guard_arrived');
    const c = await abrir();
    expect(((await c.siguiente()) as { data: { status: string } }).data.status).toBe('guard_arrived');

    await request(env.app.server).post(`${API}/alerts/${id}/confirm`).set('Authorization', `Bearer ${tokenUsuario}`);

    expect(await c.siguiente()).toEqual({ data: null });
  });

  it('solo ve su propia alerta: la de otro usuario no le llega', async () => {
    const c = await abrir();
    await c.siguiente();
    await env.prisma.alert.create({
      data: { userId: env.usuarios.bloqueado.id, status: 'searching', triggerMethod: 'tap', triggeredAt: new Date(), lat: 1, lng: 1 },
    });
    await expect(c.siguiente(1500)).rejects.toThrow();
  });

  it('sin token responde 401 y con rol de guardia 403, antes de abrir el stream', async () => {
    const anonimo = await abrir(null);
    expect(anonimo.status).toBe(401);
    expect(anonimo.json).toEqual({ error: { code: 'UNAUTHORIZED', message: 'Tu sesión terminó. Vuelve a iniciar sesión.' } });

    const guardia = await abrir(await token(env.usuarios.guardia.email));
    expect(guardia.status).toBe(403);
    expect((guardia.json as { error: { code: string } }).error.code).toBe('FORBIDDEN');
  });

  it('D26: con más conexiones que el máximo se cierra la más antigua, no la nueva', async () => {
    const primera = await abrir();
    await primera.siguiente();
    const segunda = await abrir();
    await segunda.siguiente();
    const tercera = await abrir();
    expect(await tercera.siguiente()).toEqual({ data: null });

    await esperar(200);
    expect(primera.cerrado()).toBe(true);
    expect(segunda.cerrado()).toBe(false);
    expect(tercera.cerrado()).toBe(false);
  });

  it('D25: tras cerrar sesión el stream avisa UNAUTHORIZED y se cierra en el siguiente ping', async () => {
    const t = await token(env.usuarios.protegido.email);
    const c = await abrir(t);
    await c.siguiente();

    await logout(env.app, t);

    expect(await c.siguiente(3000)).toEqual({
      error: { code: 'UNAUTHORIZED', message: 'Tu sesión terminó. Vuelve a iniciar sesión.' },
    });
    await esperar(200);
    expect(c.cerrado()).toBe(true);
  });
});
