import type { PrismaClient } from '../db/prisma.js';

/** Campos públicos del usuario (sin passwordHash). Se enumeran uno a uno a propósito. */
export const USER_PUBLIC_SELECT = {
  id: true,
  name: true,
  email: true,
  phone: true,
  role: true,
  isActive: true,
  volumeDoubleClickEnabled: true,
  falseAlarmCount: true,
  blockedUntil: true,
  createdAt: true,
} as const;

/**
 * Una sola consulta: el usuario del token si está activo y su sesión (familia `sid`) no fue
 * revocada. Devuelve null en cualquier otro caso.
 */
export async function findLiveSessionUser(prisma: PrismaClient, userId: string, sid: string) {
  const row = await prisma.refreshToken.findFirst({
    where: { familyId: sid, userId, revokedAt: null, user: { isActive: true } },
    select: { user: { select: USER_PUBLIC_SELECT } },
  });
  return row?.user ?? null;
}
