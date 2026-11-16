import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '../generated/prisma/client.js';

export type { PrismaClient };

/**
 * Crea un cliente de Prisma contra la base indicada (Prisma 7 usa el adaptador
 * `pg`). Quien lo crea es responsable de cerrarlo con `$disconnect()`
 * (por ejemplo en el `onClose` de Fastify cuando se integre).
 *
 * `passwordHash` se omite por defecto en todas las lecturas de `user`; solo el
 * login debe pedirlo con `omit: { passwordHash: false }`.
 */
export function createPrisma(databaseUrl: string): PrismaClient {
  const adapter = new PrismaPg({ connectionString: databaseUrl });
  return new PrismaClient({ adapter, omit: { user: { passwordHash: true } } });
}
