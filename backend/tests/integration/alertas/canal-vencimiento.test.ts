// BE-03 · D26: el stream alerts/active se cierra al vencer el access token, avisando antes
// con UNAUTHORIZED para que la app renueve el token y reconecte.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { crearEntorno, login, type Entorno } from '../auth/helpers.js';
import { abrirSse } from '../sse-helpers.js';

let env: Entorno;

beforeAll(async () => {
  // Token de 2 s y ping lejano: lo que cierra el stream es el vencimiento, no el ping.
  env = await crearEntorno({ JWT_ACCESS_EXPIRES_IN: '2s', SSE_PING_SECONDS: '60' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});

describe('GET /events/alerts/active · vencimiento del token', () => {
  it('al llegar el exp manda UNAUTHORIZED y cierra', async () => {
    const res = await login(env.app, env.usuarios.protegido.email);
    const c = await abrirSse(env.app, '/api/v1/events/alerts/active', res.body.data.accessToken as string);
    expect(await c.siguiente()).toEqual({ data: null });

    expect(await c.siguiente(4000)).toEqual({
      error: { code: 'UNAUTHORIZED', message: 'Tu sesión terminó. Vuelve a iniciar sesión.' },
    });
    await new Promise((r) => setTimeout(r, 200));
    expect(c.cerrado()).toBe(true);
    c.cerrar();
  });
});
