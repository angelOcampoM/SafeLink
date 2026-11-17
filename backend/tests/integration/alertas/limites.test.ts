// BE-03 · Rate limit POR USUARIO de POST /alerts y POST /alerts/:id/locations (sección 9 del contrato).
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { crearEntorno, login, type Entorno } from '../auth/helpers.js';

const API = '/api/v1';
let env: Entorno;

beforeAll(async () => {
  env = await crearEntorno({ RATE_LIMIT_ALERTS_PER_MINUTE: '2', RATE_LIMIT_LOCATIONS_PER_WINDOW: '2' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});

const tokenDe = async (email: string): Promise<string> =>
  (await login(env.app, email)).body.data.accessToken as string;

const cuerpo = { triggerMethod: 'tap', triggeredAt: new Date().toISOString(), location: null, heading: null, photoPath: null };

describe('rate limit por usuario', () => {
  it('POST /alerts: al pasarse responde 429 TOO_MANY_REQUESTS, sin afectar a otro usuario', async () => {
    const t = await tokenDe(env.usuarios.protegido.email);
    const enviar = (tok: string) =>
      request(env.app.server).post(`${API}/alerts`).set('Authorization', `Bearer ${tok}`).send(cuerpo);

    expect((await enviar(t)).status).toBe(201);
    expect((await enviar(t)).status).toBe(409); // ya tiene una activa: cuenta igual
    const tercera = await enviar(t);
    expect(tercera.status).toBe(429);
    expect(tercera.body.error.code).toBe('TOO_MANY_REQUESTS');
    expect(tercera.headers['retry-after']).toBeDefined();

    // El límite es por usuario, no por IP: el bloqueado comparte IP y aún no lo agota.
    const otro = await enviar(await tokenDe(env.usuarios.bloqueado.email));
    expect(otro.status).toBe(403);
  });

  it('POST /alerts/:id/locations: al pasarse responde 429', async () => {
    const t = await tokenDe(env.usuarios.protegido.email);
    const alerta = await env.prisma.alert.findFirstOrThrow({ where: { userId: env.usuarios.protegido.id } });
    const enviar = () =>
      request(env.app.server)
        .post(`${API}/alerts/${alerta.id}/locations`)
        .set('Authorization', `Bearer ${t}`)
        .send({ location: { lat: 18.84, lng: -99.18 } });

    expect((await enviar()).status).toBe(200);
    expect((await enviar()).status).toBe(200);
    expect((await enviar()).status).toBe(429);
  });
});
