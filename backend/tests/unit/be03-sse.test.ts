// BE-03 · Transporte SSE (D3, D26) sin base de datos: un Fastify mínimo con el SseHub real,
// el bus en memoria y snapshots simulados. Valida snapshot inicial, avisos del bus, ping que
// revisa la sesión, cierre al vencer el token y máximo de conexiones por usuario.
import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createMemoryEventBus, type EventBus } from '../../src/realtime/event-bus.js';
import { createSseHub, type SseHub } from '../../src/realtime/sse.js';
import { abrirSse } from '../integration/sse-helpers.js';

const MSG_SESION = { error: { code: 'UNAUTHORIZED', message: 'Tu sesión terminó. Vuelve a iniciar sesión.' } };

let app: FastifyInstance;
let bus: EventBus;
let hub: SseHub;
let snapshot: unknown;
let consultas: number;
let sesionViva: boolean;
let venceEnMs: number;

beforeEach(async () => {
  bus = createMemoryEventBus();
  hub = createSseHub(bus, { pingSeconds: 1, maxConnectionsPerUser: 2 });
  snapshot = null;
  consultas = 0;
  sesionViva = true;
  venceEnMs = 60_000;

  app = Fastify({ logger: false });
  app.addHook('preClose', async () => hub.closeAll());
  // Sustituto de `authenticate`: el usuario sale del header X-User.
  app.addHook('onRequest', async (request) => {
    request.user = { id: String(request.headers['x-user'] ?? 'u1'), role: 'protected_user', sid: 's' };
  });
  app.get('/canal', async (request, reply) => {
    hub.open(request, reply, {
      name: 'canal',
      topic: `t:${request.user.id}`,
      snapshot: async () => {
        consultas += 1;
        return snapshot;
      },
      sessionAlive: async () => sesionViva,
      tokenExpiresAtMs: Date.now() + venceEnMs,
    });
    return reply;
  });
  await app.ready();
});

afterEach(async () => {
  await app.close();
});

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe('SseHub', () => {
  it('manda el snapshot al conectar con las cabeceras de un stream sin caché', async () => {
    snapshot = { id: 'a1', status: 'searching' };
    const c = await abrirSse(app, '/canal');
    expect(c.status).toBe(200);
    expect(c.headers['content-type']).toMatch(/^text\/event-stream/);
    expect(c.headers['cache-control']).toBe('no-store');
    expect(await c.siguiente()).toEqual({ data: { id: 'a1', status: 'searching' } });
    c.cerrar();
  });

  it('cada aviso del bus manda un snapshot completo nuevo, solo a ese usuario', async () => {
    const mio = await abrirSse(app, '/canal');
    await mio.siguiente();
    snapshot = { id: 'a1', status: 'in_progress' };
    bus.publish('t:u1');
    expect(await mio.siguiente()).toEqual({ data: { id: 'a1', status: 'in_progress' } });

    bus.publish('t:otro');
    await expect(mio.siguiente(500)).rejects.toThrow();
    mio.cerrar();
  });

  it('una ráfaga de avisos no encola una consulta por aviso', async () => {
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    const antes = consultas;
    for (let i = 0; i < 20; i++) bus.publish('t:u1');
    await esperar(200);
    expect(consultas - antes).toBeLessThanOrEqual(2);
    c.cerrar();
  });

  it('D25: si la sesión ya no está viva, el ping avisa UNAUTHORIZED y cierra', async () => {
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    sesionViva = false;
    expect(await c.siguiente(3000)).toEqual(MSG_SESION);
    await esperar(100);
    expect(c.cerrado()).toBe(true);
    expect(hub.countFor('u1')).toBe(0);
  });

  it('D26: al vencer el access token avisa UNAUTHORIZED y cierra', async () => {
    venceEnMs = 300;
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    expect(await c.siguiente(2000)).toEqual(MSG_SESION);
    await esperar(100);
    expect(c.cerrado()).toBe(true);
  });

  it('D26: al pasar del máximo por usuario se cierra la conexión más antigua', async () => {
    const a = await abrirSse(app, '/canal');
    await a.siguiente();
    const b = await abrirSse(app, '/canal');
    await b.siguiente();
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    await esperar(100);

    expect(a.cerrado()).toBe(true);
    expect(b.cerrado()).toBe(false);
    expect(c.cerrado()).toBe(false);
    expect(hub.countFor('u1')).toBe(2);
    b.cerrar();
    c.cerrar();
  });

  it('cuando el cliente se va, el stream se limpia del hub', async () => {
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    expect(hub.countFor('u1')).toBe(1);
    c.cerrar();
    await esperar(100);
    expect(hub.countFor('u1')).toBe(0);
  });

  it('si el snapshot falla, avisa con un error genérico y cierra', async () => {
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    // Un snapshot que revienta al serializarse simula un fallo inesperado.
    snapshot = {
      toJSON: () => {
        throw new Error('boom');
      },
    };
    bus.publish('t:u1');
    expect(await c.siguiente()).toEqual({
      error: { code: 'SERVICE_UNAVAILABLE', message: 'No pudimos conectar con el servidor. Intenta de nuevo.' },
    });
    await esperar(100);
    expect(c.cerrado()).toBe(true);
  });

  it('closeAll cierra todo al apagar la API', async () => {
    const c = await abrirSse(app, '/canal');
    await c.siguiente();
    hub.closeAll();
    await esperar(100);
    expect(c.cerrado()).toBe(true);
  });
});
