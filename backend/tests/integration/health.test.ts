import type { FastifyInstance } from 'fastify';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config/env.js';

describe('GET /health (BE-01 paso 1)', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    app = buildApp(loadConfig({ NODE_ENV: 'test', JWT_SECRET: 'x'.repeat(32) }));
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('responde 200 con JSON y cuerpo exacto {"data":{"status":"ok"}}', async () => {
    const res = await request(app.server).get('/health');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/application\/json/);
    expect(res.body).toEqual({ data: { status: 'ok' } });
    expect(Object.keys(res.body)).toEqual(['data']);
  });

  it('no requiere autenticación', async () => {
    const res = await request(app.server).get('/health');
    expect(res.status).not.toBe(401);
  });

  it('una ruta inexistente responde 404', async () => {
    const res = await request(app.server).get('/ruta-que-no-existe');
    expect(res.status).toBe(404);
  });
});
