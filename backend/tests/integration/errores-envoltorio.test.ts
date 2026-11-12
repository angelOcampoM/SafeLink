import { Writable } from 'node:stream';
import Fastify, { type FastifyInstance } from 'fastify';
import request from 'supertest';
import { z } from 'zod';
import { afterEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';
import {
  MESSAGES,
  alertTaken,
  emailTaken,
  forbidden,
  invalidCredentials,
  invalidInput,
  invalidState,
  notFound,
  outsideGeofence,
  serviceUnavailable,
  unauthorized,
  userBlocked,
} from '../../src/errors/app-error.js';
import { registerErrorHandling } from '../../src/http/error-handler.js';
import { parse, parseIdParam } from '../../src/http/validate.js';

const baseEnv = { NODE_ENV: 'test', JWT_SECRET: 'x'.repeat(32) };

function dbError(code: string): Error {
  return Object.assign(new Error('SELECT secret FROM users WHERE constraint "users_email_key"'), {
    code,
    meta: { target: ['users_email_key'] },
  });
}

function registrarRutas(app: FastifyInstance): void {
  void app.register(async (a) => {
    a.get('/t/app-error/:n', async (req) => {
      const n = Number((req.params as { n: string }).n);
      const fabricas = [
        invalidCredentials,
        unauthorized,
        forbidden,
        userBlocked,
        () => notFound(),
        emailTaken,
        alertTaken,
        () => invalidState('Transición no válida'),
        () => invalidInput('Mala entrada'),
        () => outsideGeofence(12.34),
        serviceUnavailable,
      ];
      throw fabricas[n]!();
    });
    a.get('/t/generico', async () => {
      throw new Error('SELECT secret FROM users');
    });
    a.get('/t/db/:code', async (req) => {
      throw dbError((req.params as { code: string }).code);
    });
    a.get('/t/prisma-init', async () => {
      const e = new Error('no se pudo conectar postgres://u:p@host/db');
      e.name = 'PrismaClientInitializationError';
      throw e;
    });
    a.post('/t/validar', async (req) =>
      parse(z.object({ nombre: z.string(), edad: z.number() }).strict(), req.body),
    );
    a.get('/t/id/:id', async (req) => ({ data: parseIdParam((req.params as { id: string }).id) }));
    a.post('/t/eco', async (req) => ({ data: req.body }));
  });
}

let app: FastifyInstance | undefined;
afterEach(async () => {
  await app?.close();
  app = undefined;
});

async function crear(extraEnv: Record<string, string> = {}): Promise<FastifyInstance> {
  app = buildApp(loadConfig({ ...baseEnv, ...extraEnv }));
  registrarRutas(app);
  await app.ready();
  return app;
}

function unaClave(body: unknown): void {
  expect(Object.keys(body as object)).toHaveLength(1);
}

describe('AppError lanzado en handler', () => {
  const tabla: Array<[number, string, number]> = [
    [0, 'INVALID_CREDENTIALS', 401],
    [1, 'UNAUTHORIZED', 401],
    [2, 'FORBIDDEN', 403],
    [3, 'USER_BLOCKED', 403],
    [4, 'NOT_FOUND', 404],
    [5, 'EMAIL_TAKEN', 409],
    [6, 'ALERT_TAKEN', 409],
    [7, 'INVALID_STATE', 409],
    [8, 'INVALID_STATE', 400],
    [9, 'OUTSIDE_GEOFENCE', 422],
    [10, 'SERVICE_UNAVAILABLE', 503],
  ];
  it.each(tabla)('fábrica %i -> %s %i', async (n, code, status) => {
    const a = await crear();
    const res = await request(a.server).get(`/t/app-error/${n}`);
    expect(res.status).toBe(status);
    unaClave(res.body);
    expect(res.body.error.code).toBe(code);
    expect(typeof res.body.error.message).toBe('string');
    if (code === 'OUTSIDE_GEOFENCE') expect(res.body.error.remainingMeters).toBe(12.3);
    else expect(res.body.error).not.toHaveProperty('remainingMeters');
  });
});

describe('Error genérico (no se filtra nada)', () => {
  it('responde 500 SERVICE_UNAVAILABLE sin SQL ni stack', async () => {
    const a = await crear();
    const res = await request(a.server).get('/t/generico');
    expect(res.status).toBe(500);
    expect(res.body).toEqual({
      error: { code: 'SERVICE_UNAVAILABLE', message: MESSAGES.SERVICE_UNAVAILABLE },
    });
    const txt = JSON.stringify(res.body);
    for (const prohibido of ['SELECT', 'secret', 'stack', ' at ']) {
      expect(txt).not.toContain(prohibido);
    }
  });

  it('el log no incluye el mensaje original ni el cuerpo de la petición', async () => {
    const lineas: string[] = [];
    const stream = new Writable({
      write(chunk, _enc, cb) {
        lineas.push(String(chunk));
        cb();
      },
    });
    const propia = Fastify({ logger: { level: 'info', stream } });
    registerErrorHandling(propia);
    propia.post('/boom', async () => {
      throw new Error('SELECT secret FROM users');
    });
    await propia.ready();
    const res = await request(propia.server)
      .post('/boom')
      .send({ password: 'ContrasenaSuperSecreta123' });
    await propia.close();
    expect(res.status).toBe(500);
    const log = lineas.join('\n');
    expect(log).toContain('Error inesperado');
    expect(log).not.toContain('SELECT');
    expect(log).not.toContain('secret FROM');
    expect(log).not.toContain('ContrasenaSuperSecreta123');
  });
});

describe('Errores de Prisma/Postgres', () => {
  const casos: Array<[string, number, string]> = [
    ['P2002', 409, 'INVALID_STATE'],
    ['23505', 409, 'INVALID_STATE'],
    ['P2004', 400, 'INVALID_STATE'],
    ['23514', 400, 'INVALID_STATE'],
    ['P2003', 400, 'INVALID_STATE'],
    ['22P02', 400, 'INVALID_STATE'],
    ['P2025', 404, 'NOT_FOUND'],
    ['P1001', 503, 'SERVICE_UNAVAILABLE'],
  ];
  it.each(casos)('%s -> %i %s sin filtrar restricciones ni SQL', async (codigo, status, code) => {
    const a = await crear();
    const res = await request(a.server).get(`/t/db/${codigo}`);
    expect(res.status).toBe(status);
    unaClave(res.body);
    expect(res.body.error.code).toBe(code);
    const txt = JSON.stringify(res.body);
    for (const p of ['SELECT', 'users_email_key', 'constraint', 'secret', 'meta']) {
      expect(txt).not.toContain(p);
    }
  });

  it('PrismaClientInitializationError -> 503 sin cadena de conexión', async () => {
    const a = await crear();
    const res = await request(a.server).get('/t/prisma-init');
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('SERVICE_UNAVAILABLE');
    expect(JSON.stringify(res.body)).not.toContain('postgres://');
  });
});

describe('Cuerpo inválido', () => {
  it('JSON malformado -> 400 INVALID_STATE', async () => {
    const a = await crear();
    const res = await request(a.server)
      .post('/t/eco')
      .set('content-type', 'application/json')
      .send('{"a": ');
    expect(res.status).toBe(400);
    unaClave(res.body);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('El cuerpo de la petición no es válido');
  });

  it('cuerpo mayor a BODY_LIMIT_BYTES -> 400 INVALID_STATE demasiado grande', async () => {
    const a = await crear({ BODY_LIMIT_BYTES: '100' });
    const res = await request(a.server)
      .post('/t/eco')
      .set('content-type', 'application/json')
      .send(JSON.stringify({ relleno: 'a'.repeat(500) }));
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toContain('demasiado grande');
  });

  it('cuerpo dentro del límite pasa', async () => {
    const a = await crear({ BODY_LIMIT_BYTES: '100' });
    const res = await request(a.server).post('/t/eco').send({ x: 1 });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: { x: 1 } });
  });
});

describe('Validación zod con parse', () => {
  const enviar = async (cuerpo: object) => {
    const a = await crear();
    return request(a.server).post('/t/validar').send(cuerpo);
  };

  it('cuerpo válido pasa', async () => {
    const res = await enviar({ nombre: 'Ana', edad: 30 });
    expect(res.status).toBe(200);
  });

  it('campo faltante', async () => {
    const res = await enviar({ nombre: 'Ana' });
    expect(res.status).toBe(400);
    unaClave(res.body);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('El campo edad es obligatorio');
  });

  it('campo extra (role)', async () => {
    const res = await enviar({ nombre: 'Ana', edad: 30, role: 'admin' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('Campos no permitidos: role');
  });

  it('tipo inválido', async () => {
    const res = await enviar({ nombre: 'Ana', edad: 'treinta' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('El campo edad no es válido');
  });

  it('el mensaje no expone detalles internos de zod', async () => {
    const res = await enviar({ nombre: 'Ana', edad: 'treinta' });
    expect(res.body.error.message).not.toMatch(/expected|received|invalid_type|Zod/i);
  });
});

describe('parseIdParam', () => {
  const uuid = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';

  it('UUID válido pasa', async () => {
    const a = await crear();
    const res = await request(a.server).get(`/t/id/${uuid}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: uuid });
  });

  it.each(['abc', '..%2Fx', '123', '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e1', `${uuid}x`])(
    '"%s" -> 404 NOT_FOUND',
    async (valor) => {
      const a = await crear();
      const res = await request(a.server).get(`/t/id/${valor}`);
      expect(res.status).toBe(404);
      unaClave(res.body);
      expect(res.body.error.code).toBe('NOT_FOUND');
    },
  );

  it('UUID con mayúsculas es aceptado (z.uuid no distingue mayúsculas)', async () => {
    const a = await crear();
    const res = await request(a.server).get(`/t/id/${uuid.toUpperCase()}`);
    expect(res.status).toBe(200);
  });
});

describe('Ruta inexistente', () => {
  it('GET /nada -> 404 con mensaje del front', async () => {
    const a = await crear();
    const res = await request(a.server).get('/nada');
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: { code: 'NOT_FOUND', message: 'GET /nada no existe' } });
  });

  it('el query no aparece en el mensaje', async () => {
    const a = await crear();
    const res = await request(a.server).get('/nada?token=abc');
    expect(res.body.error.message).toBe('GET /nada no existe');
    expect(JSON.stringify(res.body)).not.toContain('abc');
  });

  it('el método POST se refleja', async () => {
    const a = await crear();
    const res = await request(a.server).post('/nada').send({});
    expect(res.status).toBe(404);
    expect(res.body.error.message).toBe('POST /nada no existe');
  });
});

describe('/health y forma de las respuestas', () => {
  it('/health sigue en {"data":{"status":"ok"}}', async () => {
    const a = await crear();
    const res = await request(a.server).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: { status: 'ok' } });
  });

  it('toda respuesta tiene exactamente una clave de primer nivel (data o error)', async () => {
    const a = await crear();
    const rutas = [
      '/health',
      '/nada',
      '/t/generico',
      '/t/db/P2002',
      '/t/db/P2025',
      '/t/db/P1001',
      '/t/id/abc',
      '/t/app-error/9',
      '/t/app-error/1',
    ];
    for (const r of rutas) {
      const res = await request(a.server).get(r);
      const claves = Object.keys(res.body);
      expect(claves, r).toHaveLength(1);
      expect(['data', 'error']).toContain(claves[0]);
    }
    const post = await request(a.server).post('/t/validar').send({});
    expect(Object.keys(post.body)).toEqual(['error']);
  });
});
