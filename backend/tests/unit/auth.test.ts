// BE-01 paso 5: reglas puras de autenticación y configuración (D7, D8, D25).
import { describe, expect, it } from 'vitest';
import { createPasswordHasher } from '../../src/auth/password.js';
import { generateRefreshToken, hashRefreshToken } from '../../src/auth/tokens.js';
import { DURATION_PATTERN, durationToSeconds } from '../../src/config/duration.js';
import { ConfigError, loadConfig } from '../../src/config/env.js';
import { MESSAGES, tooManyRequests } from '../../src/errors/app-error.js';
import { toAppError } from '../../src/http/error-handler.js';

const base = (extra: Record<string, string> = {}): NodeJS.ProcessEnv => ({
  JWT_SECRET: 'x'.repeat(32),
  ...extra,
});

describe('toAppError - fallos de @fastify/jwt', () => {
  it.each([
    'FST_JWT_NO_AUTHORIZATION_IN_HEADER',
    'FST_JWT_NO_AUTHORIZATION_IN_COOKIE',
    'FST_JWT_BAD_REQUEST',
    'FST_JWT_BAD_COOKIE_REQUEST',
    'FST_JWT_AUTHORIZATION_TOKEN_EXPIRED',
    'FST_JWT_AUTHORIZATION_TOKEN_INVALID',
    'FST_JWT_AUTHORIZATION_TOKEN_UNTRUSTED',
    'FST_JWT_BAD_RESPONSE',
    'FAST_JWT_MALFORMED',
    'FAST_JWT_INVALID_SIGNATURE',
    'FAST_JWT_EXPIRED',
    'FAST_JWT_INVALID_ALGORITHM',
  ])('%s -> UNAUTHORIZED 401 con mensaje fijo', (code) => {
    const err = Object.assign(new Error('detalle interno con token eyJ...'), { code, statusCode: 400 });
    const r = toAppError(err);
    expect(r?.code).toBe('UNAUTHORIZED');
    expect(r?.httpStatus).toBe(401);
    expect(r?.message).toBe(MESSAGES.UNAUTHORIZED);
    expect(r?.message).not.toContain('eyJ');
  });
});

describe('password.ts - createPasswordHasher', () => {
  const params = { memoryCost: 1024, timeCost: 2, parallelism: 1 };
  const hasher = createPasswordHasher(params);

  it('hash argon2id con sal y los parámetros configurados', async () => {
    const a = await hasher.hash('SafeLink1');
    const b = await hasher.hash('SafeLink1');
    expect(a).toMatch(/^[$]argon2id[$]v=19[$]m=1024,t=2,p=1[$]/);
    expect(a).not.toBe(b);
    expect(a).not.toContain('SafeLink1');
    expect(await hasher.verify(a, 'SafeLink1')).toBe(true);
    expect(await hasher.verify(b, 'SafeLink1')).toBe(true);
  });

  it('verify rechaza contraseña distinta, vacía y con diferencias de mayúsculas o espacios', async () => {
    const h = await hasher.hash('SafeLink1');
    expect(await hasher.verify(h, 'safelink1')).toBe(false);
    expect(await hasher.verify(h, '')).toBe(false);
    expect(await hasher.verify(h, 'SafeLink1 ')).toBe(false);
  });

  it('un hash ilegible o vacío cuenta como no coincidencia (no lanza)', async () => {
    expect(await hasher.verify('hash', 'x')).toBe(false);
    expect(await hasher.verify('', 'x')).toBe(false);
    expect(await hasher.verify('$argon2id$basura', 'x')).toBe(false);
  });

  it('needsRehash: false con los mismos parámetros, true con otros, false si es ilegible', async () => {
    const h = await hasher.hash('SafeLink1');
    expect(hasher.needsRehash(h)).toBe(false);
    expect(createPasswordHasher({ ...params, memoryCost: 2048 }).needsRehash(h)).toBe(true);
    expect(createPasswordHasher({ ...params, timeCost: 3 }).needsRehash(h)).toBe(true);
    expect(hasher.needsRehash('basura')).toBe(false);
  });

  it('hash ficticio: se calcula una sola vez, mismos parámetros y no coincide con nada razonable', async () => {
    const p1 = hasher.dummyHash();
    expect(hasher.dummyHash()).toBe(p1);
    const h = await p1;
    expect(h).toMatch(/^[$]argon2id[$]v=19[$]m=1024,t=2,p=1[$]/);
    expect(hasher.needsRehash(h)).toBe(false);
    expect(await hasher.verify(h, 'SafeLink1')).toBe(false);
    expect(await hasher.verify(h, '')).toBe(false);
    // Cada fábrica tiene su propio hash ficticio.
    expect(await createPasswordHasher(params).dummyHash()).not.toBe(h);
  });
});

describe('toAppError - 429 de cualquier origen', () => {
  it('statusCode 429 -> TOO_MANY_REQUESTS con mensaje fijo (no 500)', () => {
    const r = toAppError(Object.assign(new Error('Rate limit exceeded, retry in 1 minute'), { statusCode: 429 }));
    expect(r?.code).toBe('TOO_MANY_REQUESTS');
    expect(r?.httpStatus).toBe(429);
    expect(r?.message).toBe('Demasiados intentos. Espera un momento e intenta de nuevo.');
    expect(r?.message).toBe(tooManyRequests().message);
  });
});

describe('tokens.ts - utilidades puras', () => {
  it('generateRefreshToken: 256 bits en base64url, sin repetirse', () => {
    const a = generateRefreshToken();
    const b = generateRefreshToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a).not.toBe(b);
  });

  it('hashRefreshToken: SHA-256 hexadecimal de 64, determinista y sin el token', () => {
    const h = hashRefreshToken('abc');
    expect(h).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(hashRefreshToken('abc')).toBe(h);
    expect(hashRefreshToken('abd')).not.toBe(h);
  });
});

describe('duration.ts', () => {
  it.each([
    ['1s', 1],
    ['15m', 900],
    ['2h', 7200],
    ['30d', 2_592_000],
    ['999999s', 999_999],
  ])('acepta %s', (v, seg) => {
    expect(DURATION_PATTERN.test(v)).toBe(true);
    expect(durationToSeconds(v)).toBe(seg);
  });

  it.each(['', '15', 'm', '0m', '015m', '15M', '15 m', ' 15m', '15m ', '1.5h', '-5m', '15x', '15ms', '1000000s', '15m\n', 'abc'])(
    'rechaza %j',
    (v) => {
      expect(DURATION_PATTERN.test(v)).toBe(false);
      expect(() => durationToSeconds(v)).toThrow();
    },
  );
});

describe('env.ts - autenticación', () => {
  it('REFRESH_GRACE_SECONDS: default 5; acepta los bordes 0 y 60', () => {
    expect(loadConfig(base()).REFRESH_GRACE_SECONDS).toBe(5);
    expect(loadConfig(base({ REFRESH_GRACE_SECONDS: '0' })).REFRESH_GRACE_SECONDS).toBe(0);
    expect(loadConfig(base({ REFRESH_GRACE_SECONDS: '60' })).REFRESH_GRACE_SECONDS).toBe(60);
  });

  it.each(['-1', '61', '1000', '1.5', 'abc'])('REFRESH_GRACE_SECONDS=%s -> ConfigError', (v) => {
    expect(() => loadConfig(base({ REFRESH_GRACE_SECONDS: v }))).toThrow(ConfigError);
  });

  it('NODE_ENV ausente -> production; valor desconocido -> ConfigError', () => {
    expect(loadConfig(base()).NODE_ENV).toBe('production');
    expect(() => loadConfig(base({ NODE_ENV: 'staging' }))).toThrow(ConfigError);
  });

  it('duraciones: defaults 15m/30d y formatos inválidos -> ConfigError', () => {
    const c = loadConfig(base());
    expect(c.JWT_ACCESS_EXPIRES_IN).toBe('15m');
    expect(c.JWT_REFRESH_EXPIRES_IN).toBe('30d');
    expect(c.JWT_SESSION_MAX_AGE).toBe('90d');
    for (const nombre of ['JWT_ACCESS_EXPIRES_IN', 'JWT_REFRESH_EXPIRES_IN', 'JWT_SESSION_MAX_AGE']) {
      for (const v of ['15', '0m', '1.5h', 'abc', '']) {
        expect(() => loadConfig(base({ [nombre]: v }))).toThrow(ConfigError);
      }
    }
  });

  it('JWT_SECRET de menos de 32 caracteres o ausente -> ConfigError sin revelar el valor', () => {
    expect(() => loadConfig({ JWT_SECRET: 'corto' })).toThrow(ConfigError);
    expect(() => loadConfig({})).toThrow(ConfigError);
    try {
      loadConfig({ JWT_SECRET: 'secreto-corto-visible' });
    } catch (e) {
      expect((e as Error).message).not.toContain('secreto-corto-visible');
    }
  });
});
