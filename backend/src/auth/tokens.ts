// Refresh tokens opacos (D8, D25): CSPRNG de 256 bits, solo se guarda su SHA-256, rotación en cada
// uso, detección de reutilización y ventana de gracia. Ninguna función registra tokens en logs.
//
// Concurrencia: toda operación que cambia una familia (rotar, revocar) toma primero el mismo
// advisory lock transaccional por familia. Así ningún sucesor puede nacer después de una revocación.
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import type { Prisma } from '../generated/prisma/client.js';

type Db = Prisma.TransactionClient;

export interface TransactionRunner {
  $transaction: <T>(fn: (tx: Db) => Promise<T>) => Promise<T>;
}

export interface RefreshOptions {
  /** Vigencia de cada refresh token, en segundos (JWT_REFRESH_EXPIRES_IN). */
  ttlSeconds: number;
  /** Vida máxima absoluta de la sesión, en segundos (JWT_SESSION_MAX_AGE). */
  maxAgeSeconds: number;
  /** Ventana de gracia, en segundos (REFRESH_GRACE_SECONDS); 0 la desactiva. */
  graceSeconds: number;
}

export interface IssuedToken {
  /** Token en claro: solo se entrega al cliente, nunca se guarda ni se registra. */
  token: string;
  /** Id de la familia; viaja como claim `sid` del access token. */
  familyId: string;
  userId: string;
}

export type RotationResult = ({ ok: true } & IssuedToken) | { ok: false };

/** Forma de un refresh token válido: 32 bytes en base64url (43 caracteres). */
export const REFRESH_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export function generateRefreshToken(): string {
  return randomBytes(32).toString('base64url');
}

/** SHA-256 en hexadecimal (64 caracteres, cumple el CHECK token_hash_format). */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** min(now + ttl, inicio de la sesión + vida máxima). */
function expiry(now: Date, startedAt: Date, options: RefreshOptions): Date {
  return new Date(
    Math.min(
      now.getTime() + options.ttlSeconds * 1000,
      startedAt.getTime() + options.maxAgeSeconds * 1000,
    ),
  );
}

/** Advisory lock transaccional por familia; varias familias siempre en el mismo orden. */
async function lockFamilies(tx: Db, familyIds: readonly string[]): Promise<void> {
  const sorted = [...new Set(familyIds)].sort();
  for (const id of sorted) {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${id}, 0))`;
  }
}

async function revokeFamilyLocked(tx: Db, familyId: string, now: Date): Promise<void> {
  await tx.refreshToken.updateMany({
    where: { familyId, revokedAt: null },
    data: { revokedAt: now },
  });
}

/** Abre una sesión nueva: primer token de una familia nueva (family_id = sid). */
export async function createTokenFamily(
  db: Db,
  userId: string,
  options: RefreshOptions,
  now: Date = new Date(),
): Promise<IssuedToken> {
  const token = generateRefreshToken();
  const familyId = randomUUID();
  await db.refreshToken.create({
    data: {
      familyId,
      userId,
      tokenHash: hashRefreshToken(token),
      familyStartedAt: now,
      expiresAt: expiry(now, now, options),
    },
  });
  return { token, familyId, userId };
}

export async function revokeFamily(
  runner: TransactionRunner,
  familyId: string,
  now: Date = new Date(),
): Promise<void> {
  await runner.$transaction(async (tx) => {
    await lockFamilies(tx, [familyId]);
    await revokeFamilyLocked(tx, familyId, now);
  });
}

/**
 * Para dar de baja a alguien: primero poner isActive=false y después llamar a esta función
 * (authenticate y rotateRefreshToken ya rechazan inactivos). Entre el findMany y los locks hay una
 * ventana (TOCTOU) en la que podría nacer una familia nueva; con el usuario ya inactivo no sirve.
 */
export async function revokeAllUserFamilies(
  runner: TransactionRunner,
  userId: string,
  now: Date = new Date(),
): Promise<void> {
  await runner.$transaction(async (tx) => {
    const families = await tx.refreshToken.findMany({
      where: { userId, revokedAt: null },
      select: { familyId: true },
      distinct: ['familyId'],
    });
    const ids = families.map((f) => f.familyId);
    await lockFamilies(tx, ids);
    for (const id of ids) await revokeFamilyLocked(tx, id, now);
  });
}

/**
 * Rota el token presentado. Resultado `{ ok: false }` = el llamador responde 401.
 *
 * - Desconocido, vencido o con la sesión sobre su vida máxima: rechazo (sin revocar).
 * - Revocado: rechazo; si su familia aún tiene tokens vivos, es reutilización y se revoca la familia.
 * - Usuario inactivo: se revoca la familia y se rechaza.
 * - Sin usar: se marca usado (used_at, replaced_by_id) y se emite el sucesor (parent_id). Si el
 *   token tenía un hermano (gracia previa) sin usar, el hermano se revoca.
 * - Ya usado dentro de la ventana de gracia, sin gracia previa y con el sucesor original aún sin
 *   usar ni revocar: se acepta una vez más con un
 *   sucesor nuevo de la misma familia (no se puede reenviar el anterior: solo se guarda el hash).
 * - Ya usado fuera de la ventana (o con la gracia ya consumida): reutilización, se revoca la familia.
 */
export async function rotateRefreshToken(
  runner: TransactionRunner,
  presented: string,
  options: RefreshOptions,
  now: Date = new Date(),
): Promise<RotationResult> {
  const hash = hashRefreshToken(presented);
  return runner.$transaction(async (tx): Promise<RotationResult> => {
    // 1) Familia del token, sin bloquear. 2) Lock de la familia. 3) Fila bloqueada y lógica.
    const found = await tx.$queryRaw<{ family_id: string }[]>`
      SELECT family_id::text AS family_id FROM refresh_tokens WHERE token_hash = ${hash}`;
    const familyId = found[0]?.family_id;
    if (familyId === undefined) return { ok: false };
    await lockFamilies(tx, [familyId]);

    const locked = await tx.$queryRaw<{ id: string }[]>`
      SELECT id::text AS id FROM refresh_tokens WHERE token_hash = ${hash} FOR UPDATE`;
    const id = locked[0]?.id;
    if (id === undefined) return { ok: false };

    const row = await tx.refreshToken.findUnique({
      where: { id },
      include: { user: { select: { isActive: true } } },
    });
    if (!row) return { ok: false };
    const sessionLimit = row.familyStartedAt.getTime() + options.maxAgeSeconds * 1000;
    if (row.revokedAt !== null) {
      // Token revocado con la familia aún viva (p. ej. el hermano descartado): reutilización.
      const live = await tx.refreshToken.count({
        where: { familyId: row.familyId, revokedAt: null, expiresAt: { gt: now } },
      });
      if (live > 0) await revokeFamilyLocked(tx, row.familyId, now);
      return { ok: false };
    }
    if (row.expiresAt.getTime() <= now.getTime() || sessionLimit <= now.getTime()) {
      return { ok: false };
    }
    if (!row.user.isActive) {
      await revokeFamilyLocked(tx, row.familyId, now);
      return { ok: false };
    }

    let isGraceUse = false;
    if (row.usedAt !== null) {
      const withinGrace =
        options.graceSeconds > 0 &&
        now.getTime() - row.usedAt.getTime() <= options.graceSeconds * 1000;
      // La gracia solo sirve si el sucesor original sigue sin usar ni revocar (el cliente nunca lo
      // recibió o no lo ha usado) y no hubo otra gracia (hijos del token = solo ese sucesor).
      let graceAvailable = false;
      if (withinGrace && row.replacedById !== null) {
        const successor = await tx.refreshToken.findUnique({ where: { id: row.replacedById } });
        graceAvailable =
          successor !== null &&
          successor.usedAt === null &&
          successor.revokedAt === null &&
          (await tx.refreshToken.count({ where: { parentId: row.id } })) <= 1;
      }
      if (!graceAvailable) {
        await revokeFamilyLocked(tx, row.familyId, now);
        return { ok: false };
      }
      isGraceUse = true;
    }

    const token = generateRefreshToken();
    const successor = await tx.refreshToken.create({
      data: {
        familyId: row.familyId,
        userId: row.userId,
        tokenHash: hashRefreshToken(token),
        parentId: row.id,
        familyStartedAt: row.familyStartedAt,
        expiresAt: expiry(now, row.familyStartedAt, options),
      },
    });
    if (!isGraceUse) {
      await tx.refreshToken.update({
        where: { id: row.id },
        data: { usedAt: now, replacedById: successor.id },
      });
      // Este token es uno de dos hermanos (hubo gracia): el otro, si no se usó, se descarta.
      if (row.parentId !== null) {
        await tx.refreshToken.updateMany({
          where: { parentId: row.parentId, id: { not: row.id }, usedAt: null, revokedAt: null },
          data: { revokedAt: now },
        });
      }
    }
    return { ok: true, token, familyId: row.familyId, userId: row.userId };
  });
}
