// BE-04 paso 3 · SseHub con varios temas, refreshOnPing y límite por (usuario, canal) (D26, D34).
// Sin base de datos: Fastify mínimo + SseHub real + bus en memoria + snapshots simulados.
import Fastify, { type FastifyInstance } from 'fastify';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { AppError } from '../../src/errors/app-error.js';
import { createMemoryEventBus, type EventBus } from '../../src/realtime/event-bus.js';
import { createSseHub, type SseHub } from '../../src/realtime/sse.js';
import { abrirSse } from '../integration/sse-helpers.js';

let app: FastifyInstance;
let bus: EventBus;
let hub: SseHub;
let consultas: Record<string, number>;
let siguienteSnapshot: () => Promise<unknown>;
let logsInfo: Array<{ obj: unknown; msg: unknown }>;
let logsError: Array<{ obj: unknown; msg: unknown }>;

const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));
/** Espera, con tope, a que se cumpla la condición (sin dormir de más). */
async function hasta(cond: () => boolean, ms = 2000): Promise<void> {
  const limite = Date.now() + ms;
  while (!cond() && Date.now() < limite) await esperar(10);
}

beforeEach(async () => {
  bus = createMemoryEventBus();
  hub = createSseHub(bus, { pingSeconds: 1, maxConnectionsPerUser: 3 });
  consultas = {};
  logsInfo = [];
  logsError = [];
  siguienteSnapshot = async () => ({ n: 0 });

  app = Fastify({ logger: false });
  app.addHook('preClose', async () => hub.closeAll());
  app.addHook('onRequest', async (request) => {
    request.user = { id: String(request.headers['x-user'] ?? 'u1'), role: 'guard', sid: 's' };
    // Espía de logs del request: el SSE usa request.log.info/error.
    const log = request.log as unknown as Record<string, unknown>;
    log['info'] = (obj: unknown, msg: unknown) => logsInfo.push({ obj, msg });
    log['error'] = (obj: unknown, msg: unknown) => logsError.push({ obj, msg });
  });

  const canal = (nombre: string, extra: Record<string, unknown>) =>
    app.get(`/${nombre}`, async (request, reply) => {
      hub.open(request, reply, {
        name: nombre,
        snapshot: async () => {
          consultas[nombre] = (consultas[nombre] ?? 0) + 1;
          return siguienteSnapshot();
        },
        sessionAlive: async () => true,
        tokenExpiresAtMs: Date.now() + 60_000,
        ...extra,
      });
      return reply;
    });
  // Varios temas + refreshOnPing (como guard/alerts).
  canal('multi', { topics: ['t:a', 't:b'], refreshOnPing: true });
  // Un solo tema, sin refreshOnPing (como alerts/active).
  canal('simple', { topic: 't:a' });
  // Otro canal con nombre distinto, para el límite por (usuario, canal).
  canal('otro', { topic: 't:otro' });
  // Tema único y temas combinados.
  canal('combinado', { topic: 't:a', topics: ['t:b', 't:a'] });
  await app.ready();
});

afterEach(async () => {
  await app.close();
});

describe('SseHub: varios temas', () => {
  it('cada tema de la lista despierta el mismo stream con un snapshot nuevo', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente(); // snapshot inicial
    let n = 0;
    siguienteSnapshot = async () => ({ n: ++n });

    bus.publish('t:a');
    expect(await c.siguiente()).toEqual({ data: { n: 1 } });
    bus.publish('t:b');
    expect(await c.siguiente()).toEqual({ data: { n: 2 } });
    c.cerrar();
  });

  it('un tema que no está en la lista no despierta el stream', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente();
    bus.publish('t:ajeno');
    await expect(c.siguiente(400)).rejects.toThrow();
    c.cerrar();
  });

  it('topic y topics se combinan; un tema repetido solo suscribe una vez (un aviso = un snapshot)', async () => {
    const c = await abrirSse(app, '/combinado');
    await c.siguiente();
    const antes = consultas['combinado'] ?? 0;
    bus.publish('t:a');
    await c.siguiente();
    await esperar(150);
    expect((consultas['combinado'] ?? 0) - antes).toBe(1);
    bus.publish('t:b');
    await c.siguiente();
    c.cerrar();
  });

  it('al cerrar el stream se da de baja de TODOS los temas (no sigue consultando)', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente();
    c.cerrar();
    await hasta(() => hub.countFor('u1') === 0);
    const antes = consultas['multi'] ?? 0;
    bus.publish('t:a');
    bus.publish('t:b');
    await esperar(150);
    expect(consultas['multi'] ?? 0).toBe(antes);
  });
});

describe('SseHub: refreshOnPing', () => {
  it('con refreshOnPing, cada ping manda un snapshot nuevo sin que nadie publique en el bus', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente();
    let n = 0;
    siguienteSnapshot = async () => ({ n: ++n });
    expect(await c.siguiente(3000)).toEqual({ data: { n: 1 } });
    expect(await c.siguiente(3000)).toEqual({ data: { n: 2 } });
    c.cerrar();
  });

  it('sin refreshOnPing, el ping NO manda snapshot nuevo', async () => {
    const c = await abrirSse(app, '/simple');
    await c.siguiente();
    const antes = consultas['simple'] ?? 0;
    // Más de dos pings (cada 1 s) sin avisos del bus.
    await expect(c.siguiente(2500)).rejects.toThrow();
    expect(consultas['simple'] ?? 0).toBe(antes);
    c.cerrar();
  });
});

describe('SseHub: límite por (usuario, canal) (D26, D34)', () => {
  it('3 streams de un canal y 3 de otro del mismo usuario conviven (el máximo es por canal)', async () => {
    const a = [await abrirSse(app, '/simple'), await abrirSse(app, '/simple'), await abrirSse(app, '/simple')];
    const b = [await abrirSse(app, '/multi'), await abrirSse(app, '/multi'), await abrirSse(app, '/multi')];
    for (const c of [...a, ...b]) await c.siguiente();
    await esperar(100);
    expect(hub.countFor('u1')).toBe(6);
    expect([...a, ...b].map((c) => c.cerrado())).toEqual([false, false, false, false, false, false]);
    for (const c of [...a, ...b]) c.cerrar();
  });

  it('el 4.º del mismo canal cierra el más antiguo de ESE canal y no toca el otro canal', async () => {
    const s1 = await abrirSse(app, '/simple');
    const m1 = await abrirSse(app, '/multi');
    const s2 = await abrirSse(app, '/simple');
    const m2 = await abrirSse(app, '/multi');
    const s3 = await abrirSse(app, '/simple');
    const m3 = await abrirSse(app, '/multi');
    for (const c of [s1, m1, s2, m2, s3, m3]) await c.siguiente();

    const s4 = await abrirSse(app, '/simple');
    expect(await s4.siguiente()).toEqual({ data: { n: 0 } });
    await hasta(() => s1.cerrado());

    expect(s1.cerrado()).toBe(true);
    expect([s2, s3, s4, m1, m2, m3].map((c) => c.cerrado())).toEqual([false, false, false, false, false, false]);
    expect(hub.countFor('u1')).toBe(6);
    for (const c of [s2, s3, s4, m1, m2, m3]) c.cerrar();
  });

  it('el límite es por usuario: otro usuario no cuenta ni es desalojado', async () => {
    const mios = [await abrirSse(app, '/simple'), await abrirSse(app, '/simple'), await abrirSse(app, '/simple')];
    for (const c of mios) await c.siguiente();
    // Un usuario distinto, mismo canal: no afecta a los anteriores.
    const puerto = (app.server.address() as { port: number }).port;
    const otro = await new Promise<number>((resolve, reject) => {
      import('node:http').then(({ request }) => {
        const req = request({ host: '127.0.0.1', port: puerto, path: '/simple', headers: { 'x-user': 'u2' } }, (res) => {
          res.once('data', () => {
            res.destroy();
            resolve(res.statusCode ?? 0);
          });
        });
        req.on('error', (e) => ((e as NodeJS.ErrnoException).code === 'ECONNRESET' ? undefined : reject(e)));
        req.end();
      }, reject);
    });
    expect(otro).toBe(200);
    expect(mios.map((c) => c.cerrado())).toEqual([false, false, false]);
    for (const c of mios) c.cerrar();
  });
});

describe('SseHub: AppError del snapshot', () => {
  it('un AppError al refrescar manda su evento de error tal cual y cierra el stream', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente();
    siguienteSnapshot = async () => {
      throw new AppError('NOT_FOUND', 'La alerta ya no existe', 404);
    };
    bus.publish('t:b');
    expect(await c.siguiente()).toEqual({ error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } });
    await hasta(() => c.cerrado());
    expect(c.cerrado()).toBe(true);
    expect(hub.countFor('u1')).toBe(0);
  });

  it('un AppError se registra a nivel info (esperado), no como error', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente();
    siguienteSnapshot = async () => {
      throw new AppError('NOT_FOUND', 'La alerta ya no existe', 404);
    };
    bus.publish('t:a');
    await c.siguiente();
    await hasta(() => logsInfo.length > 0);
    expect(logsInfo.map((l) => l.obj)).toEqual([{ code: 'NOT_FOUND' }]);
    expect(logsError).toEqual([]);
  });

  it('un error que no es AppError sí se registra como error y viaja como SERVICE_UNAVAILABLE genérico', async () => {
    const c = await abrirSse(app, '/multi');
    await c.siguiente();
    siguienteSnapshot = async () => {
      throw new Error('detalle interno secreto');
    };
    bus.publish('t:a');
    const e = (await c.siguiente()) as { error: { code: string; message: string } };
    expect(e.error.code).toBe('SERVICE_UNAVAILABLE');
    expect(JSON.stringify(e)).not.toContain('secreto');
    await hasta(() => logsError.length > 0);
    expect(logsError).toHaveLength(1);
    expect(logsInfo).toEqual([]);
  });

  it('un AppError en el snapshot inicial también cierra el stream tras el evento de error', async () => {
    siguienteSnapshot = async () => {
      throw new AppError('NOT_FOUND', 'La alerta ya no existe', 404);
    };
    const c = await abrirSse(app, '/multi');
    expect(await c.siguiente()).toEqual({ error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } });
    await hasta(() => c.cerrado());
    expect(c.cerrado()).toBe(true);
  });
});
