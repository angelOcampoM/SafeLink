// Utilidades de las pruebas de autenticación (BE-01 paso 5).
import { createHmac } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import request from 'supertest';
import { buildApp } from '../../../src/app.js';
import { createPasswordHasher } from '../../../src/auth/password.js';
import { loadConfig, type Config } from '../../../src/config/env.js';
import type { PrismaClient } from '../../../src/db/prisma.js';
import { abrirDb, type ContextoDb } from '../db/helpers.js';

export const JWT_SECRET = 'secreto-solo-para-pruebas-minimo-32-caracteres';
export const PASSWORD = 'SafeLink1';
export const MSG_UNAUTHORIZED = 'Tu sesión terminó. Vuelve a iniciar sesión.';
export const MSG_CREDENCIALES = 'Correo o contraseña incorrectos';

export const USER_KEYS = [
  'blockedUntil',
  'createdAt',
  'email',
  'falseAlarmCount',
  'id',
  'isActive',
  'name',
  'phone',
  'role',
  'volumeDoubleClickEnabled',
] as const;

// argon2 con el mínimo permitido por la config (ARGON2_MEMORY_KIB >= 19456); la misma configuración
// hashea a los usuarios y verifica el login.
export const ARGON2_PRUEBA = { memoryCost: 19456, timeCost: 2, parallelism: 1 } as const;
export const hasherPrueba = createPasswordHasher(ARGON2_PRUEBA);

/** Límites de rate limit altos para que no interfieran; las pruebas de 429 los bajan a propósito. */
const BASE_PRUEBA = {
  NODE_ENV: 'test',
  JWT_SECRET,
  ARGON2_MEMORY_KIB: String(ARGON2_PRUEBA.memoryCost),
  ARGON2_TIME_COST: String(ARGON2_PRUEBA.timeCost),
  ARGON2_PARALLELISM: String(ARGON2_PRUEBA.parallelism),
  RATE_LIMIT_LOGIN_MAX: '100000',
  RATE_LIMIT_REFRESH_MAX: '100000',
};

export function configPrueba(extra: Record<string, string> = {}): Config {
  return loadConfig({ ...BASE_PRUEBA, ...extra });
}

export interface Usuarios {
  protegido: { id: string; email: string };
  guardia: { id: string; email: string };
  admin: { id: string; email: string };
  inactivo: { id: string; email: string };
  bloqueado: { id: string; email: string };
}

export interface Entorno {
  db: ContextoDb;
  prisma: PrismaClient;
  app: FastifyInstance;
  usuarios: Usuarios;
  cerrar: () => Promise<void>;
}

/** Abre la base de pruebas (con bloqueo), crea un usuario por caso con hash argon2 real y arranca la app. */
export async function crearEntorno(extraEnv: Record<string, string> = {}): Promise<Entorno> {
  const db = await abrirDb();
  const { prisma } = db;
  const passwordHash = await hasherPrueba.hash(PASSWORD);
  const mk = async (slug: string, data: Record<string, unknown>) => {
    const u = await prisma.user.create({
      data: {
        name: `Nombre ${slug}`,
        email: `${slug}@prueba.test`,
        phone: '7771234567',
        passwordHash,
        role: 'protected_user',
        ...data,
      },
    });
    return { id: u.id, email: u.email };
  };
  const usuarios: Usuarios = {
    protegido: await mk('protegido', {}),
    guardia: await mk('guardia', { role: 'guard' }),
    admin: await mk('admin', { role: 'admin' }),
    inactivo: await mk('inactivo', { isActive: false }),
    bloqueado: await mk('bloqueado', {
      falseAlarmCount: 3,
      blockedUntil: new Date('2099-01-01T00:00:00Z'),
    }),
  };
  const app = buildApp(configPrueba(extraEnv), { prisma });
  await app.ready();
  return {
    db,
    prisma,
    app,
    usuarios,
    cerrar: async () => {
      await app.close();
      await db.cerrar();
    },
  };
}

export const login = (app: FastifyInstance, email: string, password = PASSWORD) =>
  request(app.server).post('/api/v1/auth/login').send({ email, password });

export const me = (app: FastifyInstance, token?: string) => {
  const r = request(app.server).get('/api/v1/auth/me');
  return token === undefined ? r : r.set('Authorization', `Bearer ${token}`);
};

export const refresh = (app: FastifyInstance, refreshToken: string) =>
  request(app.server).post('/api/v1/auth/refresh').send({ refreshToken });

export const logout = (app: FastifyInstance, token: string) =>
  request(app.server).post('/api/v1/auth/logout').set('Authorization', `Bearer ${token}`);

export const session = (app: FastifyInstance, token: string | undefined, body: unknown) => {
  const r = request(app.server).post('/api/v1/auth/session');
  return (token === undefined ? r : r.set('Authorization', `Bearer ${token}`)).send(
    body as object,
  );
};

// --- JWT forjados a mano (independientes de @fastify/jwt) ---------------------

const b64 = (o: unknown): string => Buffer.from(JSON.stringify(o)).toString('base64url');

export function forjarJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  firma: string | Buffer = '',
): string {
  const cuerpo = `${b64(header)}.${b64(payload)}`;
  return `${cuerpo}.${typeof firma === 'string' ? firma : firma.toString('base64url')}`;
}

/** HS256/HS384/HS512 firmado con el secreto de prueba. */
export function firmarHmac(
  payload: Record<string, unknown>,
  alg: 'HS256' | 'HS384' | 'HS512' = 'HS256',
  secreto: string = JWT_SECRET,
): string {
  const cuerpo = `${b64({ alg, typ: 'JWT' })}.${b64(payload)}`;
  const hash = { HS256: 'sha256', HS384: 'sha384', HS512: 'sha512' }[alg];
  return `${cuerpo}.${createHmac(hash, secreto).update(cuerpo).digest('base64url')}`;
}

export function decodificar(token: string): { header: Record<string, unknown>; payload: Record<string, unknown> } {
  const [h, p] = token.split('.');
  return {
    header: JSON.parse(Buffer.from(h ?? '', 'base64url').toString('utf8')) as Record<string, unknown>,
    payload: JSON.parse(Buffer.from(p ?? '', 'base64url').toString('utf8')) as Record<string, unknown>,
  };
}
