// BE-04 paso 9 (D42): el token del dispositivo no aparece en los logs.
import fs from 'node:fs';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { crearEntorno, login, type Entorno } from '../auth/helpers.js';

describe('logs durante PUT /users/me/device-token', () => {
  let env: Entorno;
  let capturado = '';
  let espias: { mockRestore: () => void }[] = [];

  beforeAll(async () => {
    env = await crearEntorno({ NODE_ENV: 'development' });
  }, 120_000);
  afterAll(async () => {
    espias.forEach((e) => {
      e.mockRestore();
    });
    await env.cerrar();
  });

  it('el token (válido o inválido) no se escribe en los logs', async () => {
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

    const access = (await login(env.app, env.usuarios.guardia.email)).body.data.accessToken as string;
    const put = (cuerpo: object) =>
      request(env.app.server)
        .put('/api/v1/users/me/device-token')
        .set('Authorization', `Bearer ${access}`)
        .send(cuerpo);
    const valido = 'TOKEN-PUSH-SECRETO-valido-0123456789';
    const conEspacio = 'TOKEN-PUSH-SECRETO con espacio';
    const largo = `TOKEN-PUSH-SECRETO-${'z'.repeat(520)}`;
    expect((await put({ token: valido })).status).toBe(200);
    expect((await put({ token: valido })).status).toBe(200);
    expect((await put({ token: conEspacio })).status).toBe(400);
    expect((await put({ token: largo })).status).toBe(400);
    expect((await put({ token: valido, extra: 1 })).status).toBe(400);
    espias.forEach((e) => {
      e.mockRestore();
    });

    // Evita una prueba vacía: el logger sí escribió las peticiones.
    expect(capturado).toContain('/api/v1/users/me/device-token');
    expect(capturado).not.toContain('TOKEN-PUSH-SECRETO');
    expect(capturado).not.toMatch(/"token"/);
  });
});
