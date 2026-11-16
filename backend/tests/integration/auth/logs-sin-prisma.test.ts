// BE-01 paso 5: logs sin secretos y app sin prisma (solo /health).
import fs from 'node:fs';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { PASSWORD, configPrueba, crearEntorno, login, me, refresh, type Entorno } from './helpers.js';

describe('buildApp sin prisma', () => {
  it('solo expone /health; las rutas de auth responden 404 con envoltorio', async () => {
    const app = buildApp(configPrueba());
    await app.ready();
    try {
      expect((await request(app.server).get('/health')).status).toBe(200);
      const rutas: [string, string][] = [
        ['post', '/api/v1/auth/login'],
        ['get', '/api/v1/auth/me'],
        ['post', '/api/v1/auth/refresh'],
        ['post', '/api/v1/auth/logout'],
        ['post', '/api/v1/auth/session'],
      ];
      for (const [metodo, ruta] of rutas) {
        const res = await (request(app.server) as unknown as Record<string, (u: string) => request.Test>)[
          metodo
        ]!(ruta);
        expect(res.status).toBe(404);
        expect(res.body.error.code).toBe('NOT_FOUND');
        expect(typeof res.body.error.message).toBe('string');
        expect(Object.keys(res.body)).toEqual(['error']);
      }
    } finally {
      await app.close();
    }
  });
});

describe('logs de la API durante el flujo de auth', () => {
  let env: Entorno;
  let capturado = '';
  let espias: { mockRestore: () => void }[] = [];

  beforeAll(async () => {
    env = await crearEntorno({ NODE_ENV: 'development' });
  }, 120_000);
  afterAll(async () => {
    espias.forEach((e) => { e.mockRestore(); });
    await env.cerrar();
  });

  it('no contienen password, accessToken ni refreshToken', async () => {
    // pino escribe a fd 1 con sonic-boom (fs.write / fs.writeSync); se captura sin cambiar la salida.
    const aTexto = (d: unknown): string =>
      typeof d === 'string' ? d : Buffer.from(d as Uint8Array).toString('utf8');
    const realSync = fs.writeSync.bind(fs) as (...a: unknown[]) => number;
    const realAsync = fs.write.bind(fs) as (...a: unknown[]) => void;
    espias = [
      vi.spyOn(fs, 'writeSync').mockImplementation(((fd: number, d: unknown, ...r: unknown[]) => {
        if (fd !== 1) return realSync(fd, d, ...r);
        capturado += aTexto(d);
        return Buffer.byteLength(aTexto(d));
      }) as typeof fs.writeSync),
      vi.spyOn(fs, 'write').mockImplementation(((fd: number, d: unknown, ...r: unknown[]) => {
        if (fd !== 1) {
          realAsync(fd, d, ...r);
          return;
        }
        capturado += aTexto(d);
        const cb = r.find((x): x is (e: null, n: number) => void => typeof x === 'function');
        cb?.(null, Buffer.byteLength(aTexto(d)));
      }) as typeof fs.write),
    ];

    const ok = await login(env.app, env.usuarios.protegido.email);
    const access = ok.body.data.accessToken as string;
    const refreshTok = ok.body.data.refreshToken as string;
    await login(env.app, env.usuarios.protegido.email, 'ClaveMala-Secreta-77');
    await me(env.app, access);
    await me(env.app, 'basura.token.invalido');
    const rot = await refresh(env.app, refreshTok);
    await refresh(env.app, refreshTok);
    await refresh(env.app, refreshTok);
    await request(env.app.server).post('/api/v1/auth/login').set('Content-Type', 'application/json').send('{"password": ');
    espias.forEach((e) => { e.mockRestore(); });

    // Evita una prueba vacía: el logger sí escribió las peticiones.
    expect(capturado).toContain('/api/v1/auth/login');
    for (const secreto of [
      PASSWORD,
      'ClaveMala-Secreta-77',
      access,
      refreshTok,
      rot.body.data.accessToken as string,
      rot.body.data.refreshToken as string,
      'basura.token.invalido',
    ]) {
      expect(capturado).not.toContain(secreto);
    }
    expect(capturado).not.toMatch(/"password"|"accessToken"|"refreshToken"/);
  });
});
