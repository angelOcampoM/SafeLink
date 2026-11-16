import type { Role } from '../../generated/prisma/enums.js';

/** Campos de User que necesita el serializador (el registro puede traer más; se ignoran). */
export interface UserRecord {
  id: string;
  name: string;
  email: string;
  phone: string;
  role: Role;
  isActive: boolean;
  volumeDoubleClickEnabled: boolean;
  falseAlarmCount: number;
  blockedUntil: Date | null;
  createdAt: Date;
}

/** Forma `UsuarioJson` del front (nube_mapeadores.dart). Campo por campo: jamás spread del registro. */
export interface UserJson {
  id: string;
  name: string;
  email: string;
  phone: string;
  role: Role;
  isActive: boolean;
  volumeDoubleClickEnabled: boolean;
  falseAlarmCount: number;
  blockedUntil: string | null;
  createdAt: string;
}

export function serializeUser(user: UserRecord): UserJson {
  return {
    id: user.id,
    name: user.name,
    email: user.email,
    phone: user.phone,
    role: user.role,
    isActive: user.isActive,
    volumeDoubleClickEnabled: user.volumeDoubleClickEnabled,
    falseAlarmCount: user.falseAlarmCount,
    blockedUntil: user.blockedUntil ? user.blockedUntil.toISOString() : null,
    createdAt: user.createdAt.toISOString(),
  };
}

export type UserWithTokensJson = UserJson & { accessToken: string; refreshToken: string };

export function serializeUserWithTokens(
  user: UserRecord,
  tokens: { accessToken: string; refreshToken: string },
): UserWithTokensJson {
  return {
    ...serializeUser(user),
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken,
  };
}
