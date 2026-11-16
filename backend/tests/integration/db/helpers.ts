// Utilidades de las pruebas de integración con PostgreSQL (BE-01 paso 3).
// Opera SOLO sobre la base de pruebas (DATABASE_URL_TEST, nombre terminado en "_test").
import { Client } from 'pg';
import { createPrisma, type PrismaClient } from '../../../src/db/prisma.js';
import type { AlertUncheckedCreateInput } from '../../../src/generated/prisma/models/Alert.js';
import type { UserUncheckedCreateInput } from '../../../src/generated/prisma/models/User.js';

try {
  process.loadEnvFile('.env');
} catch {
  // Sin .env: se usa el entorno ya definido.
}

/** URL de la base de pruebas; falla con un mensaje claro si falta o no termina en "_test". */
export function urlPrueba(): string {
  const url = process.env['DATABASE_URL_TEST'];
  if (!url) {
    throw new Error(
      'Falta DATABASE_URL_TEST: define la URL de la base de pruebas (safelink_test) en backend/.env. ' +
        'Las pruebas de integración con la base de datos no se omiten en silencio.',
    );
  }
  let nombre: string;
  try {
    nombre = decodeURIComponent(new URL(url).pathname.slice(1));
  } catch {
    throw new Error('DATABASE_URL_TEST no es una URL válida (se omite el valor por seguridad).');
  }
  if (!nombre.endsWith('_test')) {
    throw new Error('Guarda de seguridad: el nombre de la base de pruebas debe terminar en "_test". Se aborta.');
  }
  return url;
}

// Los archivos de prueba corren en paralelo y comparten la base: se serializan con un
// bloqueo consultivo de PostgreSQL (sesión dedicada, se libera al cerrar).
const LLAVE_BLOQUEO = 5_150_301;

export interface ContextoDb {
  prisma: PrismaClient;
  limpiar: () => Promise<void>;
  cerrar: () => Promise<void>;
}

export async function abrirDb(): Promise<ContextoDb> {
  const url = urlPrueba();
  const bloqueo = new Client({ connectionString: url });
  await bloqueo.connect();
  await bloqueo.query('SELECT pg_advisory_lock($1)', [LLAVE_BLOQUEO]);
  const prisma = createPrisma(url);
  const limpiar = async (): Promise<void> => {
    await prisma.$executeRawUnsafe(
      'TRUNCATE TABLE "refresh_tokens", "alert_ignores", "alert_status_history", "alerts", "guard_profiles", "users" CASCADE',
    );
  };
  await limpiar();
  return {
    prisma,
    limpiar,
    cerrar: async () => {
      await limpiar();
      await prisma.$disconnect();
      await bloqueo.query('SELECT pg_advisory_unlock($1)', [LLAVE_BLOQUEO]);
      await bloqueo.end();
    },
  };
}

let contador = 0;

export function correoUnico(prefijo = 'u'): string {
  contador += 1;
  return `${prefijo}${String(contador)}@prueba.test`;
}

export function crearUsuario(
  prisma: PrismaClient,
  extra: Partial<UserUncheckedCreateInput> = {},
) {
  return prisma.user.create({
    data: { name: 'Usuario Prueba', email: correoUnico(), phone: '7770000000', passwordHash: 'hash', role: 'protected_user', ...extra },
  });
}

const REQUIEREN_GUARDIA = ['in_progress', 'guard_arrived', 'closed'];
const REQUIEREN_CIERRE = ['closed', 'resolved_by_admin'];

/**
 * Crea una alerta válida para las restricciones: si el estado exige guardia se crea uno
 * (rol guard, distinto del dueño) y si exige cierre se pone closedAt.
 */
export async function crearAlerta(
  prisma: PrismaClient,
  userId: string,
  extra: Partial<Omit<AlertUncheckedCreateInput, 'userId'>> = {},
) {
  const status = extra.status ?? 'searching';
  const data: AlertUncheckedCreateInput = {
    userId,
    status,
    triggerMethod: 'tap',
    triggeredAt: new Date('2026-01-01T00:00:00Z'),
    ...extra,
  };
  if (data.guardId === undefined && REQUIEREN_GUARDIA.includes(status)) {
    data.guardId = (await crearUsuario(prisma, { role: 'guard' })).id;
  }
  if (data.closedAt === undefined && REQUIEREN_CIERRE.includes(status)) {
    data.closedAt = new Date('2026-01-01T01:00:00Z');
  }
  return prisma.alert.create({ data });
}
