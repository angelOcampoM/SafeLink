// Plugin de autenticación: registra @fastify/jwt (HS256 fijo) y decora `authenticate`.
// El control por roles y las políticas por ruta viven en src/security/ (policies.ts y guards.ts),
// que invoca `authenticate`: tras él existe request.user = { id, role, sid }.
import fastifyJwt from '@fastify/jwt';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { findLiveSessionUser } from '../auth/session.js';
import { durationToSeconds } from '../config/duration.js';
import type { PrismaClient } from '../db/prisma.js';
import { unauthorized } from '../errors/app-error.js';
import { Role } from '../generated/prisma/enums.js';

export const JWT_ALGORITHM = 'HS256';

export interface AuthUser {
  id: string;
  role: Role;
  sid: string;
}

export interface AccessClaims {
  sub: string;
  role: Role;
  sid: string;
}

declare module '@fastify/jwt' {
  interface FastifyJWT {
    payload: AccessClaims;
    user: AuthUser;
  }
}

declare module 'fastify' {
  interface FastifyInstance {
    /** Hook onRequest (lo aplica security/guards.ts): verifica el JWT, que el usuario siga activo y que su sesión no esté revocada. */
    authenticate: (request: FastifyRequest) => Promise<void>;
    /** Verifica solo firma, algoritmo y vigencia del Bearer; devuelve los claims. Lanza 401. */
    verifyAccessToken: (request: FastifyRequest) => AccessClaims;
    /** Firma un access token con los claims dados (HS256). */
    signAccessToken: (claims: AccessClaims) => string;
  }
  // Metadatos opcionales de ruta; si se declaran, src/security/guards.ts exige que coincidan
  // con la política central (la fuente de verdad es policies.ts).
  interface FastifyContextConfig {
    /** Ruta sin autenticación. */
    public?: boolean;
    /** Roles permitidos (la ruta usa `authenticate`). */
    roles?: readonly Role[];
    /** La ruta hace su propia verificación del token (POST /auth/session). */
    auth?: 'custom';
  }
}

const BEARER = /^Bearer ([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*)$/;
const claimsSchema = z.object({
  sub: z.uuid(),
  role: z.enum(Role),
  sid: z.uuid(),
  iat: z.number().int(),
  exp: z.number().int(),
});

export interface AuthPluginOptions {
  prisma: PrismaClient;
}

async function authPlugin(app: FastifyInstance, options: AuthPluginOptions): Promise<void> {
  const { config } = app;
  const { prisma } = options;
  const accessSeconds = durationToSeconds(config.JWT_ACCESS_EXPIRES_IN);

  await app.register(fastifyJwt, {
    secret: config.JWT_SECRET,
    sign: { algorithm: JWT_ALGORITHM, expiresIn: config.JWT_ACCESS_EXPIRES_IN },
    verify: {
      algorithms: [JWT_ALGORITHM],
      requiredClaims: ['exp', 'iat', 'sub', 'sid'],
      // @fastify/jwt interpreta un número como segundos.
      maxAge: accessSeconds,
    },
  });

  app.decorate('signAccessToken', (claims: AccessClaims): string => app.jwt.sign(claims));

  // Se verifica a mano (no con request.jwtVerify) para que request.user solo lo asigne
  // `authenticate`, nunca el payload crudo del token.
  app.decorate('verifyAccessToken', (request: FastifyRequest): AccessClaims => {
    const match = BEARER.exec(request.headers.authorization ?? '');
    if (!match?.[1]) throw unauthorized();
    let payload: unknown;
    try {
      payload = app.jwt.verify<Record<string, unknown>>(match[1]);
    } catch {
      throw unauthorized();
    }
    const parsed = claimsSchema.safeParse(payload);
    if (!parsed.success) throw unauthorized();
    // maxAge solo mira iat: también se rechaza un exp más lejano que la vigencia de acceso.
    if (parsed.data.exp - parsed.data.iat > accessSeconds) throw unauthorized();
    return { sub: parsed.data.sub, role: parsed.data.role, sid: parsed.data.sid };
  });

  app.decorate('authenticate', async (request: FastifyRequest): Promise<void> => {
    const claims = app.verifyAccessToken(request);
    const user = await findLiveSessionUser(prisma, claims.sub, claims.sid);
    if (!user) throw unauthorized();
    // El rol sale de la base (fuente de verdad), no del token.
    request.user = { id: user.id, role: user.role, sid: claims.sid };
  });
}

// Equivale a fastify-plugin: sin encapsulación, las decoraciones quedan en la instancia raíz.
export const authPluginRoot = Object.assign(authPlugin, {
  [Symbol.for('skip-override')]: true,
});
