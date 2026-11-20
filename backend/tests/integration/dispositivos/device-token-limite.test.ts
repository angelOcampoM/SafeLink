// BE-04 paso 9 (D42): rate limit por usuario de PUT /users/me/device-token (RATE_LIMIT_REFRESH_MAX).
import request from 'supertest';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PASSWORD, crearEntorno, hasherPrueba, login, type Entorno } from '../auth/helpers.js';

const RUTA = '/api/v1/users/me/device-token';
let env: Entorno;

beforeAll(async () => {
  env = await crearEntorno({ RATE_LIMIT_REFRESH_MAX: '3' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});

describe('PUT /users/me/device-token con RATE_LIMIT_REFRESH_MAX=3', () => {
  it('la petición 4 -> 429 con envoltorio; otro guardia no se ve afectado', async () => {
    const b = await env.prisma.user.create({
      data: {
        name: 'Guardia B',
        email: 'guardia-b@prueba.test',
        phone: '7771234567',
        passwordHash: await hasherPrueba.hash(PASSWORD),
        role: 'guard',
      },
    });
    const sa = (await login(env.app, env.usuarios.guardia.email)).body.data.accessToken as string;
    const sb = (await login(env.app, b.email)).body.data.accessToken as string;
    const put = (access: string, i: number) =>
      request(env.app.server)
        .put(RUTA)
        .set('Authorization', `Bearer ${access}`)
        .send({ token: `tok-${String(i)}` });

    for (let i = 1; i <= 3; i += 1) expect((await put(sa, i)).status, `petición ${String(i)}`).toBe(200);
    const res = await put(sa, 4);
    expect(res.status).toBe(429);
    expect(Object.keys(res.body)).toEqual(['error']);
    expect(res.body.error.code).toBe('TOO_MANY_REQUESTS');
    expect(typeof res.body.error.message).toBe('string');
    // La petición rechazada no guardó nada.
    expect(await env.prisma.deviceToken.count({ where: { token: 'tok-4' } })).toBe(0);

    expect((await put(sb, 100)).status).toBe(200);
  });
});
