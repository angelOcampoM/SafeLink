import { z } from 'zod';
import type { PasswordHasher } from '../../auth/password.js';
import { findLiveSessionUser } from '../../auth/session.js';
import {
  REFRESH_TOKEN_PATTERN,
  createTokenFamily,
  revokeFamily,
  rotateRefreshToken,
  type RefreshOptions,
} from '../../auth/tokens.js';
import { durationToSeconds } from '../../config/duration.js';
import type { Config } from '../../config/env.js';
import { esCorreoDuplicado } from '../../db/errores-prisma.js';
import type { PrismaClient } from '../../db/prisma.js';
import { emailTaken, invalidCredentials, unauthorized } from '../../errors/app-error.js';
import { Role } from '../../generated/prisma/enums.js';
import type { AccessClaims } from '../../plugins/auth.js';
import {
  serializeUser,
  serializeUserWithTokens,
  type UserJson,
  type UserWithTokensJson,
} from './serializers.js';

export interface AuthServiceDeps {
  prisma: PrismaClient;
  config: Config;
  hasher: PasswordHasher;
  signAccessToken: (claims: AccessClaims) => string;
}

const uuidSchema = z.uuid();

export function createAuthService({ prisma, config, hasher, signAccessToken }: AuthServiceDeps) {
  const refreshOptions: RefreshOptions = {
    ttlSeconds: durationToSeconds(config.JWT_REFRESH_EXPIRES_IN),
    maxAgeSeconds: durationToSeconds(config.JWT_SESSION_MAX_AGE),
    graceSeconds: config.REFRESH_GRACE_SECONDS,
  };

  return {
    async login(email: string, password: string): Promise<UserWithTokensJson> {
      // Único lugar que lee passwordHash (regla de ESLint: solo en modules/auth).
      const user = await prisma.user.findUnique({
        where: { email },
        omit: { passwordHash: false },
      });
      // Con correo inexistente se verifica contra un hash ficticio para igualar tiempos.
      const hash = user ? user.passwordHash : await hasher.dummyHash();
      const passwordOk = await hasher.verify(hash, password);
      // Mismo error para correo inexistente, contraseña incorrecta o usuario inactivo.
      // Un usuario bloqueado (blocked_until) SÍ puede iniciar sesión.
      if (!user || !passwordOk || !user.isActive) throw invalidCredentials();

      // Si los parámetros de argon2 cambiaron, se actualiza el hash (sin bloquear el login si falla).
      if (hasher.needsRehash(user.passwordHash)) {
        try {
          const passwordHash = await hasher.hash(password);
          // Solo si el hash no cambió entre la lectura y ahora (no pisa un cambio concurrente).
          await prisma.user.updateMany({
            where: { id: user.id, passwordHash: user.passwordHash },
            data: { passwordHash },
          });
        } catch {
          // El hash anterior sigue siendo válido.
        }
      }

      const family = await createTokenFamily(prisma, user.id, refreshOptions);
      const accessToken = signAccessToken({ sub: user.id, role: user.role, sid: family.familyId });
      return serializeUserWithTokens(user, { accessToken, refreshToken: family.token });
    },

    /**
     * U-01 · Registro público. El rol NO se recibe: siempre es usuario
     * protegido. Queda con la sesión abierta, igual que el login.
     */
    async register(input: {
      name: string;
      email: string;
      phone: string;
      password: string;
    }): Promise<UserWithTokensJson> {
      const passwordHash = await hasher.hash(input.password);
      let user;
      try {
        user = await prisma.user.create({
          data: {
            name: input.name,
            email: input.email,
            phone: input.phone,
            passwordHash,
            role: Role.protected_user,
          },
        });
      } catch (error) {
        // La unicidad la decide la base, no una consulta previa: entre el
        // SELECT y el INSERT cabe otro registro con el mismo correo.
        if (esCorreoDuplicado(error)) throw emailTaken();
        throw error;
      }

      const family = await createTokenFamily(prisma, user.id, refreshOptions);
      const accessToken = signAccessToken({ sub: user.id, role: user.role, sid: family.familyId });
      return serializeUserWithTokens(user, { accessToken, refreshToken: family.token });
    },

    /** U-05 · El usuario protegido enciende o apaga su disparo por doble clic. */
    async updateSettings(userId: string, volumeDoubleClickEnabled: boolean): Promise<UserJson> {
      const user = await prisma.user.update({
        where: { id: userId },
        data: { volumeDoubleClickEnabled },
      });
      return serializeUser(user);
    },

    async me(userId: string): Promise<UserJson> {
      const user = await prisma.user.findUnique({ where: { id: userId } });
      if (!user) throw unauthorized();
      return serializeUser(user);
    },

    async refresh(presentedToken: string): Promise<UserWithTokensJson> {
      // Un token con forma inválida nunca existió: 401 sin tocar la base.
      if (!REFRESH_TOKEN_PATTERN.test(presentedToken)) throw unauthorized();
      const rotated = await rotateRefreshToken(prisma, presentedToken, refreshOptions);
      if (!rotated.ok) throw unauthorized();
      const user = await prisma.user.findUnique({ where: { id: rotated.userId } });
      if (!user || !user.isActive) {
        await revokeFamily(prisma, rotated.familyId);
        throw unauthorized();
      }
      const accessToken = signAccessToken({
        sub: user.id,
        role: user.role,
        sid: rotated.familyId,
      });
      return serializeUserWithTokens(user, { accessToken, refreshToken: rotated.token });
    },

    async logout(sid: string): Promise<null> {
      await revokeFamily(prisma, sid);
      return null;
    },

    /** Restaura la sesión: User, o null si la sesión no es válida (nunca lanza por eso). */
    async session(claims: AccessClaims, userId: string): Promise<UserJson | null> {
      if (!uuidSchema.safeParse(userId).success) return null;
      if (userId.toLowerCase() !== claims.sub) return null;
      const user = await findLiveSessionUser(prisma, claims.sub, claims.sid);
      return user ? serializeUser(user) : null;
    },
  };
}
