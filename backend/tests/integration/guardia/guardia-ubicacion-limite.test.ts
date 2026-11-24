// BE-04 paso 2 · PUT /guard/location: límite de frecuencia por guardia (429) y logs sin
// coordenadas (G-06). Archivo aparte: usa otra configuración (límite bajo, logger activo).
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import fs from 'node:fs';
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { PASSWORD, crearEntorno, hasherPrueba, login, type Entorno } from '../auth/helpers.js';
import { correoUnico } from '../db/helpers.js';

const API = '/api/v1';
const MSG_429 = 'Demasiados intentos. Espera un momento e intenta de nuevo.';
let env: Entorno;

beforeAll(async () => {
  // Ventana larga: el reloj real no puede reabrirla durante la prueba (determinista).
  env = await crearEntorno({ NODE_ENV: 'development', RATE_LIMIT_LOCATIONS_PER_WINDOW: '3', LOCATION_UPDATE_SECONDS: '600' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});

/** Un guardia nuevo con perfil y su token, para que cada prueba tenga su propio contador. */
async function guardiaNuevo(): Promise<{ id: string; token: string }> {
  const email = correoUnico('g');
  const u = await env.prisma.user.create({
    data: { name: 'Guardia', email, phone: '7771112233', passwordHash: await hasherPrueba.hash(PASSWORD), role: 'guard' },
  });
  await env.prisma.guardProfile.create({ data: { userId: u.id, shiftStart: '00:00', shiftEnd: '00:00' } });
  const res = await login(env.app, email);
  return { id: u.id, token: res.body.data.accessToken as string };
}
const put = (t: string, cuerpo: unknown) =>
  request(env.app.server).put(`${API}/guard/location`).set('Authorization', `Bearer ${t}`).send(cuerpo as object);
const OK = { location: { lat: 18.84, lng: -99.18 } };

describe('rate limit por guardia', () => {
  it('la petición 4 responde 429 TOO_MANY_REQUESTS con el envoltorio y Retry-After', async () => {
    const g = await guardiaNuevo();
    for (let i = 0; i < 3; i++) expect((await put(g.token, OK)).status).toBe(200);
    const res = await put(g.token, OK);
    expect(res.status).toBe(429);
    expect(res.body).toEqual({ error: { code: 'TOO_MANY_REQUESTS', message: MSG_429 } });
    expect(res.headers['retry-after']).toBeDefined();
  });

  it('el 429 no guarda la ubicación excedida', async () => {
    const g = await guardiaNuevo();
    for (let i = 0; i < 3; i++) await put(g.token, OK);
    expect((await put(g.token, { location: { lat: 10.5, lng: 10.5 } })).status).toBe(429);
    const p = await env.prisma.guardProfile.findUniqueOrThrow({ where: { userId: g.id } });
    expect(p.lastLocationLat).toBeCloseTo(18.84, 9);
  });

  it('otro guardia (misma IP) no se ve afectado', async () => {
    const a = await guardiaNuevo();
    const b = await guardiaNuevo();
    for (let i = 0; i < 4; i++) await put(a.token, OK);
    expect((await put(a.token, OK)).status).toBe(429);
    expect((await put(b.token, OK)).status).toBe(200);
  });

  it('un anónimo (401) no gasta el cupo del guardia; una petición inválida sí cuenta', async () => {
    const g = await guardiaNuevo();
    for (let i = 0; i < 5; i++) {
      expect((await request(env.app.server).put(`${API}/guard/location`).send(OK)).status).toBe(401);
    }
    expect((await put(g.token, { location: { lat: 99, lng: 0 } })).status).toBe(400);
    expect((await put(g.token, OK)).status).toBe(200);
    expect((await put(g.token, OK)).status).toBe(200);
    expect((await put(g.token, OK)).status).toBe(429);
  });
});

describe('logs', () => {
  it('no contienen las coordenadas enviadas ni el token', async () => {
    const g = await guardiaNuevo();
    let capturado = '';
    const aTexto = (d: unknown): string => (typeof d === 'string' ? d : Buffer.from(d as Uint8Array).toString('utf8'));
    const realSync = fs.writeSync.bind(fs) as (...a: unknown[]) => number;
    const realAsync = fs.write.bind(fs) as (...a: unknown[]) => void;
    const espias = [
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
    try {
      expect((await put(g.token, { location: { lat: 17.123456, lng: -98.654321 } })).status).toBe(200);
      expect((await put(g.token, { location: { lat: 77.777777, lng: 55.555555 } })).status).toBe(200);
      expect((await put(g.token, { location: { lat: 88.888888, lng: 11.111111 } })).status).toBe(200);
      expect((await put(g.token, { location: { lat: 66.666666, lng: 22.222222 } })).status).toBe(429);
      expect((await put(g.token, { location: { lat: 99.999999, lng: 0 } })).status).toBe(429);
    } finally {
      espias.forEach((e) => { e.mockRestore(); });
    }
    expect(capturado).toContain('/api/v1/guard/location'); // el logger sí escribió
    for (const dato of ['17.123456', '98.654321', '77.777777', '55.555555', '88.888888', '11.111111', '66.666666', '22.222222', '99.999999', g.token]) {
      expect(capturado).not.toContain(dato);
    }
  });
});
