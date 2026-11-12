import net from 'node:net';
import { Writable } from 'node:stream';
import Fastify, { type FastifyInstance } from 'fastify';
import request from 'supertest';
import { z } from 'zod';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { ConfigError, loadConfig } from '../../src/config/env.js';
import { MESSAGES } from '../../src/errors/app-error.js';
import { registerErrorHandling } from '../../src/http/error-handler.js';
import { parse, parseIdParam, userMsg } from '../../src/http/validate.js';

const baseEnv = { NODE_ENV: 'test', JWT_SECRET: 'x'.repeat(32) };
const GENERICO = 'Los datos enviados no son válidos';

function conPrisma(code: string | undefined, name: string): Error {
  const e = new Error('SELECT secret FROM users');
  e.name = name;
  if (code !== undefined) Object.assign(e, { code });
  return e;
}

function registrar(app: FastifyInstance): void {
  void app.register(async (a) => {
    a.get('/t/id/:id', async (req) => ({ data: parseIdParam((req.params as { id: string }).id) }));
    a.post('/t/eco', async (req) => ({ data: req.body }));
    a.post('/t/estricto', async (req) =>
      parse(z.object({ nombre: z.string() }).strict(), req.body),
    );
    a.post('/t/pass', async (req) =>
      parse(z.object({ password: z.string().min(8, userMsg('Mínimo 8 caracteres')) }), req.body),
    );
    a.post('/t/refine', async (req) =>
      parse(
        z.object({ a: z.string() }).refine((v) => v.a === 'ok', { message: `valor ${'recibido'}` }),
        req.body,
      ),
    );
    a.post('/t/refine-valor', async (req) =>
      parse(
        z.object({ a: z.string() }).refine(() => false, { message: 'recibí TOP-SECRETO-777' }),
        req.body,
      ),
    );
    a.post('/t/refine-sin', async (req) =>
      parse(z.object({ a: z.string() }).refine(() => false), req.body),
    );
    a.post('/t/anidado', async (req) =>
      parse(z.object({ u: z.object({ n: z.string() }) }), req.body),
    );
    a.get('/t/lanzar/:k', async (req) => {
      const k = (req.params as { k: string }).k;
      if (k === 'texto') throw 'texto';
      if (k === 'null') throw null;
      if (k === 'code') throw { code: 'UNAUTHORIZED' };
      if (k === 'forbidden') throw { code: 'FORBIDDEN', statusCode: 403 };
      if (k === 'status') throw { statusCode: 401, message: 'secreto' };
      if (k === 'econn') throw Object.assign(new Error('secreto'), { code: 'ECONNREFUSED' });
      if (k === 'econn-prisma') throw conPrisma('ECONNREFUSED', 'PrismaClientKnownRequestError');
      if (k === 'econn-p1001') throw conPrisma('P1001', 'Error');
      if (k === 'econn-driver') throw conPrisma('ECONNRESET', 'DriverAdapterError');
      throw new Error('x');
    });
  });
}

let app: FastifyInstance | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function crear(env: Record<string, string> = {}): Promise<FastifyInstance> {
  app = buildApp(loadConfig({ ...baseEnv, ...env }));
  registrar(app);
  await app.ready();
  return app;
}

function sinPista(body: unknown, ...prohibidas: string[]): void {
  const txt = JSON.stringify(body);
  for (const p of prohibidas) expect(txt).not.toContain(p);
}

describe('ECONNREFUSED y errores de red', () => {
  it('con forma de Prisma (nombre PrismaClient*) -> 503', async () => {
    const a = await crear();
    const res = await request(a.server).get('/t/lanzar/econn-prisma');
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('SERVICE_UNAVAILABLE');
  });

  it('P1001 -> 503', async () => {
    const a = await crear();
    expect((await request(a.server).get('/t/lanzar/econn-p1001')).status).toBe(503);
  });

  it('ECONNRESET de DriverAdapterError -> 503', async () => {
    const a = await crear();
    expect((await request(a.server).get('/t/lanzar/econn-driver')).status).toBe(503);
  });

  it('ECONNREFUSED genérico sin forma de Prisma -> 500 SERVICE_UNAVAILABLE', async () => {
    const a = await crear();
    const res = await request(a.server).get('/t/lanzar/econn');
    expect(res.status).toBe(500);
    expect(res.body).toEqual({
      error: { code: 'SERVICE_UNAVAILABLE', message: MESSAGES.SERVICE_UNAVAILABLE },
    });
    sinPista(res.body, 'secreto');
  });
});

describe('Cualquier cosa lanzada se vuelve 500 sin filtrar', () => {
  it.each(['texto', 'null', 'code', 'forbidden', 'status'])('lanzar %s', async (k) => {
    const a = await crear();
    const res = await request(a.server).get(`/t/lanzar/${k}`);
    expect(res.status).toBe(500);
    expect(res.body).toEqual({
      error: { code: 'SERVICE_UNAVAILABLE', message: MESSAGES.SERVICE_UNAVAILABLE },
    });
    sinPista(res.body, 'secreto', 'texto');
  });
});

describe('frameworkErrors (URL inválida, parámetro largo)', () => {
  it.each(['/t/id/%E0%A4%A', '/%zz', '/t/id/%E0%A4%A?x=1'])('%s -> 404 NOT_FOUND', async (ruta) => {
    const a = await crear();
    const res = await request(a.server).get(ruta);
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: { code: 'NOT_FOUND', message: MESSAGES.NOT_FOUND } });
    sinPista(res.body, '%zz', '%E0');
  });

  it(':id de 101+ caracteres -> 404 (no 414)', async () => {
    const a = await crear();
    for (const largo of [101, 500, 5000]) {
      const res = await request(a.server).get(`/t/id/${'a'.repeat(largo)}`);
      expect(res.status, String(largo)).toBe(404);
      expect(res.body.error.code).toBe('NOT_FOUND');
      expect(Object.keys(res.body)).toEqual(['error']);
    }
  });
});

describe('404 con ruta inexistente muy larga', () => {
  it('trunca el path a 100 caracteres con elipsis', async () => {
    const a = await crear();
    const path = `/${'z'.repeat(10 * 1024)}`;
    const res = await request(a.server).get(path);
    expect(res.status).toBe(404);
    const msg: string = res.body.error.message;
    expect(msg).toBe(`GET ${path.slice(0, 100)}… no existe`);
    expect(msg.length).toBeLessThan(130);
  });
});

describe('validate: claves no permitidas', () => {
  const enviar = async (cuerpo: object | string) => {
    const a = await crear();
    const r = request(a.server).post('/t/estricto');
    return typeof cuerpo === 'string'
      ? r.set('content-type', 'application/json').send(cuerpo)
      : r.send(cuerpo);
  };

  it('1000 claves extra -> mensaje acotado', async () => {
    const extra: Record<string, number> = { nombre: 1 };
    const cuerpo: Record<string, unknown> = { nombre: 'a' };
    for (let i = 0; i < 1000; i++) extra[`k${i}`] = i;
    Object.assign(cuerpo, extra, { nombre: 'a' });
    const res = await enviar(cuerpo);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('Hay campos no permitidos');
  });

  it('una clave de 10 KB -> mensaje acotado, sin reflejarla', async () => {
    const res = await enviar({ nombre: 'a', ['q'.repeat(10 * 1024)]: 1 });
    expect(res.status).toBe(400);
    expect(res.body.error.message.length).toBeLessThan(100);
    sinPista(res.body, 'qqqq');
  });

  it.each([
    ['<script>', '<script>'],
    ['salto de línea', 'a\nb'],
    ['bidi', 'ab‮cd'],
  ])('clave con %s no se refleja', async (_n, clave) => {
    const res = await enviar({ nombre: 'a', [clave]: 1 });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    const msg: string = res.body.error.message;
    expect(msg).not.toContain('<script>');
    expect(msg).not.toContain('\n');
    expect(msg).not.toContain('‮');
  });

  it('1 a 3 claves válidas se listan', async () => {
    expect((await enviar({ nombre: 'a', a: 1 })).body.error.message).toBe('Campos no permitidos: a');
    expect((await enviar({ nombre: 'a', a: 1, b: 2 })).body.error.message).toBe(
      'Campos no permitidos: a, b',
    );
    expect((await enviar({ nombre: 'a', a: 1, b: 2, c: 3 })).body.error.message).toBe(
      'Campos no permitidos: a, b, c',
    );
  });

  it('4 claves válidas ya no se listan', async () => {
    const res = await enviar({ nombre: 'a', a: 1, b: 2, c: 3, d: 4 });
    expect(res.body.error.message).toBe('Hay campos no permitidos');
  });
});

describe('validate: userMsg y mensajes genéricos', () => {
  it('userMsg marcado llega exacto', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/pass').send({ password: 'corto' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('Mínimo 8 caracteres');
  });

  it('el mensaje marcado no deja la marca interna', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/pass').send({ password: 'corto' });
    expect(res.body.error.message).not.toContain('\u0001');
    expect(res.body.error.message).not.toContain('userMsg');
  });

  it('refine con mensaje no marcado -> genérico', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/refine').send({ a: 'otro' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).not.toContain('recibido');
    expect(res.body.error.message).not.toMatch(/Invalid input/i);
  });

  it('refine con mensaje que contiene el valor recibido -> genérico, sin el valor', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/refine-valor').send({ a: 'TOP-SECRETO-777' });
    expect(res.status).toBe(400);
    sinPista(res.body, 'TOP-SECRETO-777');
    expect(res.body.error.message).not.toMatch(/Invalid input/i);
  });

  it('refine sin mensaje -> genérico en español, nunca "Invalid input"', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/refine-sin').send({ a: 'x' });
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe(GENERICO);
  });

  it('campo ausente -> obligatorio; presente con tipo inválido -> no es válido', async () => {
    const a = await crear();
    const ausente = await request(a.server).post('/t/estricto').send({});
    expect(ausente.body.error.message).toBe('El campo nombre es obligatorio');
    const nulo = await request(a.server).post('/t/estricto').send({ nombre: null });
    expect(nulo.body.error.message).toBe('El campo nombre no es válido');
    const numero = await request(a.server).post('/t/estricto').send({ nombre: 5 });
    expect(numero.body.error.message).toBe('El campo nombre no es válido');
  });

  it('campo anidado ausente usa la ruta con punto', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/anidado').send({ u: {} });
    expect(res.body.error.message).toBe('El campo u.n es obligatorio');
    const res2 = await request(a.server).post('/t/anidado').send({});
    expect(res2.body.error.message).toBe('El campo u es obligatorio');
  });
});

describe('Cuerpos hostiles', () => {
  it.each(['{"__proto__":{"x":1}}', '{"constructor":{"prototype":{}}}'])(
    '%s -> 400 INVALID_STATE genérico',
    async (cuerpo) => {
      const a = await crear();
      const res = await request(a.server)
        .post('/t/eco')
        .set('content-type', 'application/json')
        .send(cuerpo);
      expect(res.status).toBe(400);
      expect(Object.keys(res.body)).toEqual(['error']);
      expect(res.body.error.code).toBe('INVALID_STATE');
      sinPista(res.body, '__proto__', 'constructor', 'prototype');
    },
  );

  it('content-type json con cuerpo vacío -> 400 con envoltorio', async () => {
    const a = await crear();
    const res = await request(a.server).post('/t/eco').set('content-type', 'application/json');
    expect(res.status).toBe(400);
    expect(Object.keys(res.body)).toEqual(['error']);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });

  it('content-type no soportado -> 400 con envoltorio', async () => {
    const a = await crear();
    const res = await request(a.server)
      .post('/t/eco')
      .set('content-type', 'application/x-evil')
      .send('abc');
    expect(res.status).toBe(400);
    expect(Object.keys(res.body)).toEqual(['error']);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });
});

describe('Configuración: BODY_LIMIT_BYTES', () => {
  it('más de 10 MiB lanza ConfigError', () => {
    expect(() => loadConfig({ ...baseEnv, BODY_LIMIT_BYTES: String(10 * 1024 * 1024 + 1) })).toThrow(
      ConfigError,
    );
  });
  it('exactamente 10 MiB es válido', () => {
    expect(loadConfig({ ...baseEnv, BODY_LIMIT_BYTES: String(10 * 1024 * 1024) }).BODY_LIMIT_BYTES).toBe(
      10 * 1024 * 1024,
    );
  });
});

function appConLog(isProduction: boolean): { app: FastifyInstance; lineas: string[] } {
  const lineas: string[] = [];
  const stream = new Writable({
    write(chunk, _e, cb) {
      lineas.push(String(chunk));
      cb();
    },
  });
  const propia = Fastify({ logger: { level: 'info', stream } });
  registerErrorHandling(propia, { isProduction });
  propia.get('/boom', async () => {
    throw new Error('MENSAJE-ORIGINAL-SENSIBLE');
  });
  return { app: propia, lineas };
}

describe('Log de errores inesperados', () => {
  it('fuera de production incluye la pila sin su primera línea', async () => {
    const { app: propia, lineas } = appConLog(false);
    await propia.ready();
    const res = await request(propia.server).get('/boom');
    await propia.close();
    expect(res.status).toBe(500);
    const log = lineas.join('\n');
    expect(log).toContain('Error inesperado');
    expect(log).toContain('"stack"');
    expect(log).toMatch(/at /);
    expect(log).not.toContain('MENSAJE-ORIGINAL-SENSIBLE');
  });

  it('en production no incluye pila', async () => {
    const { app: propia, lineas } = appConLog(true);
    await propia.ready();
    await request(propia.server).get('/boom');
    await propia.close();
    const log = lineas.join('\n');
    expect(log).toContain('Error inesperado');
    expect(log).not.toContain('"stack"');
    expect(log).not.toMatch(/\bat /);
    expect(log).not.toContain('MENSAJE-ORIGINAL-SENSIBLE');
  });

  it('petición abortada se registra como aviso, no como error', async () => {
    const lineas: string[] = [];
    const stream = new Writable({
      write(chunk, _e, cb) {
        lineas.push(String(chunk));
        cb();
      },
    });
    const propia = Fastify({ logger: { level: 'info', stream } });
    registerErrorHandling(propia, { isProduction: false });
    let liberar!: () => void;
    const iniciada = new Promise<void>((r) => {
      liberar = r;
    });
    let terminar!: () => void;
    const cerrada = new Promise<void>((r) => {
      terminar = r;
    });
    propia.get('/lento', async (req) => {
      liberar();
      await new Promise<void>((r) => req.raw.once('close', () => r()));
      // Deja que Node marque la petición como abortada antes de fallar.
      await new Promise<void>((r) => setImmediate(r));
      try {
        throw conPrisma('P1001', 'Error');
      } finally {
        terminar();
      }
    });
    await propia.listen({ port: 0, host: '127.0.0.1' });
    const puerto = (propia.server.address() as net.AddressInfo).port;
    const socket = net.connect(puerto, '127.0.0.1');
    socket.write('GET /lento HTTP/1.1\r\nHost: x\r\n\r\n');
    await iniciada;
    socket.destroy();
    await cerrada;
    await propia.close();
    const log = lineas.join('\n');
    // Si el cliente se fue, nunca debe quedar como error de BD / inesperado.
    expect(log).not.toMatch(/"level":50/);
    expect(log).toContain('Petición abortada por el cliente');
  });
});
