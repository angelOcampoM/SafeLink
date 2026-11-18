// Token push del dispositivo del guardia (D42). El token es un dato sensible: este módulo nunca
// lo registra en logs ni lo devuelve; solo lo guarda y lo entrega al notificador (paso 11).
import { lockFamilies } from '../../auth/tokens.js';
import type { PrismaClient } from '../../db/prisma.js';
import { unauthorized } from '../../errors/app-error.js';

export interface DevicesServiceDeps {
  prisma: PrismaClient;
}

export function createDevicesService({ prisma }: DevicesServiceDeps) {
  return {
    /**
     * Upsert idempotente por token. Si ya existía (aunque fuera de otro usuario: el teléfono
     * cambió de cuenta) se reasigna al usuario y a la sesión actuales.
     *
     * Toma el mismo lock por familia que logout/rotación y comprueba que la sesión siga viva:
     * así un registro que llega después de revocar la familia no deja un token huérfano.
     */
    async register(userId: string, familyId: string, token: string, now: Date = new Date()): Promise<null> {
      await prisma.$transaction(async (tx) => {
        await lockFamilies(tx, [familyId]);
        const live = await tx.refreshToken.findFirst({
          where: { familyId, userId, revokedAt: null, user: { isActive: true } },
          select: { id: true },
        });
        if (!live) throw unauthorized();
        await tx.deviceToken.upsert({
          where: { token },
          create: { userId, familyId, token, lastSeenAt: now },
          update: { userId, familyId, lastSeenAt: now },
        });
      });
      return null;
    },

    /**
     * Tokens de los guardias dados cuya sesión (familia) sigue viva, para el notificador.
     * «Viva» = como en findLiveSessionUser (familia sin revocar, usuario activo) y además con un
     * refresh token vigente (sin vencer); así no se envía a un dispositivo con la sesión caducada.
     */
    async findLiveTokens(guardIds: readonly string[], now: Date = new Date()): Promise<string[]> {
      if (guardIds.length === 0) return [];
      const rows = await prisma.deviceToken.findMany({
        where: {
          userId: { in: [...guardIds] },
          user: { isActive: true },
        },
        select: { token: true, userId: true, familyId: true },
      });
      if (rows.length === 0) return [];
      const live = await prisma.refreshToken.findMany({
        where: {
          familyId: { in: [...new Set(rows.map((r) => r.familyId))] },
          revokedAt: null,
          expiresAt: { gt: now },
        },
        select: { familyId: true, userId: true },
      });
      const alive = new Set(live.map((l) => `${l.userId}:${l.familyId}`));
      return rows.filter((r) => alive.has(`${r.userId}:${r.familyId}`)).map((r) => r.token);
    },
  };
}

export type DevicesService = ReturnType<typeof createDevicesService>;
