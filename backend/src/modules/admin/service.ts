// A-01 Alta · A-02 Edición y baja de guardias (BE-02).
// La cobertura (turno, centro, radio y zona) es A-03 y vive en BE-06.
import type { PasswordHasher } from '../../auth/password.js';
import { esCorreoDuplicado, esRegistroInexistente } from '../../db/errores-prisma.js';
import type { PrismaClient } from '../../db/prisma.js';
import { emailTaken, notFound } from '../../errors/app-error.js';
import { Role } from '../../generated/prisma/enums.js';
import { serializeGuard, type GuardJson } from './serializers.js';

/** Turno por defecto de un guardia recién dado de alta (memoria_admin_repository.dart:53-59). */
const TURNO_INICIAL = { shiftStart: '08:00', shiftEnd: '16:00' } as const;

const NO_ENCONTRADO = 'No encontramos a ese guardia';

export interface AdminServiceDeps {
  prisma: PrismaClient;
  hasher: PasswordHasher;
}

export function createAdminService({ prisma, hasher }: AdminServiceDeps) {
  /** Trae al guardia con su perfil, o lanza NOT_FOUND si no existe o no es guardia. */
  async function guardiaConPerfil(guardId: string): Promise<GuardJson> {
    const user = await prisma.user.findFirst({
      where: { id: guardId, role: Role.guard },
      include: { guardProfile: true },
    });
    if (!user?.guardProfile) throw notFound(NO_ENCONTRADO);
    return serializeGuard(user, user.guardProfile);
  }

  return {
    /**
     * A-02 · Listado. La búsqueda es solo por nombre, sin importar mayúsculas
     * ni acentos, y los dados de baja van al final.
     */
    async listGuards(search: string): Promise<GuardJson[]> {
      const guardias = await prisma.user.findMany({
        where: {
          role: Role.guard,
          ...(search ? { name: { contains: search, mode: 'insensitive' } } : {}),
        },
        include: { guardProfile: true },
        orderBy: [{ isActive: 'desc' }, { name: 'asc' }],
      });
      return guardias
        .filter((g) => g.guardProfile !== null)
        .map((g) => serializeGuard(g, g.guardProfile!));
    },

    getGuard: guardiaConPerfil,

    /**
     * A-01 · Alta. Usuario y perfil nacen juntos: un guardia sin perfil no
     * existe para el despacho, así que se crean en una sola transacción.
     */
    async createGuard(input: {
      name: string;
      email: string;
      phone: string;
      password: string;
    }): Promise<GuardJson> {
      const passwordHash = await hasher.hash(input.password);
      try {
        const creado = await prisma.user.create({
          data: {
            name: input.name,
            email: input.email,
            phone: input.phone,
            passwordHash,
            role: Role.guard,
            guardProfile: { create: { ...TURNO_INICIAL } },
          },
          include: { guardProfile: true },
        });
        return serializeGuard(creado, creado.guardProfile!);
      } catch (error) {
        if (esCorreoDuplicado(error)) throw emailTaken();
        throw error;
      }
    },

    /** A-02 · Edición. No toca contraseña ni turno. */
    async updateGuard(
      guardId: string,
      cambios: { name?: string; email?: string; phone?: string },
    ): Promise<GuardJson> {
      await guardiaConPerfil(guardId); // NOT_FOUND antes de intentar escribir
      try {
        await prisma.user.update({ where: { id: guardId }, data: cambios });
      } catch (error) {
        if (esCorreoDuplicado(error)) throw emailTaken();
        if (esRegistroInexistente(error)) throw notFound(NO_ENCONTRADO);
        throw error;
      }
      return guardiaConPerfil(guardId);
    },

    /**
     * A-02 · Baja lógica: el guardia no se borra. Deja de poder iniciar sesión
     * y de recibir alertas, pero sigue en el listado y conserva su historial.
     */
    async deactivateGuard(guardId: string): Promise<null> {
      await guardiaConPerfil(guardId);
      await prisma.user.update({ where: { id: guardId }, data: { isActive: false } });
      return null;
    },
  };
}
