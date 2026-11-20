// A-01 Alta · A-02 Edición y baja de guardias (BE-02).
// A-05 Historial · A-06 Métricas generales · A-07 Métricas por guardia · A-08 Desbloqueo (BE-07).
// La cobertura (turno, centro, radio y zona) es A-03 y vive en BE-06.
import type { PasswordHasher } from '../../auth/password.js';
import {
  generalMetrics,
  guardMetrics as calcularMetricasGuardia,
  type GeneralMetrics,
  type GuardMetrics,
} from '../../domain/metrics.js';
import { wallClockToUtc } from '../../domain/timezone.js';
import { esCorreoDuplicado, esRegistroInexistente } from '../../db/errores-prisma.js';
import type { PrismaClient } from '../../db/prisma.js';
import { emailTaken, notFound } from '../../errors/app-error.js';
import type { Prisma } from '../../generated/prisma/client.js';
import { Role } from '../../generated/prisma/enums.js';
import { serializeUser, type UserJson } from '../auth/serializers.js';
import {
  ALERT_INCLUDE,
  serializeAdminAlert,
  type AlertJson,
  type SerializeOptions,
} from '../alerts/serializers.js';
import type { HistoryQuery, PeriodQuery } from './schemas.js';
import { serializeGuard, type GuardJson } from './serializers.js';

/** Turno por defecto de un guardia recién dado de alta (memoria_admin_repository.dart:53-59). */
const TURNO_INICIAL = { shiftStart: '08:00', shiftEnd: '16:00' } as const;

const NO_ENCONTRADO = 'No encontramos a ese guardia';
const USUARIO_NO_ENCONTRADO = 'No encontramos a ese usuario';

export interface AdminServiceDeps {
  prisma: PrismaClient;
  hasher: PasswordHasher;
  /** Opciones de serialización de alertas (foto, ETA); las mismas que los demás módulos. */
  serialize: SerializeOptions;
  /** Zona horaria IANA de los turnos (config TZ_SHIFTS): hora de `alertsByHour` y de las fechas sin zona. */
  timeZone: string;
  now?: () => Date;
}

export function createAdminService(deps: AdminServiceDeps) {
  const { prisma, hasher, serialize, timeZone } = deps;
  const now = deps.now ?? (() => new Date());

  /**
   * Convierte una fecha del filtro en instante. Sin zona en el texto es hora de pared de
   * TZ_SHIFTS (así la manda el front, contrato 4.8); con zona se respeta la que trae.
   */
  function instante(texto: string): Date {
    return /(Z|[+-]\d{2}:\d{2})$/.test(texto) ? new Date(texto) : wallClockToUtc(texto, timeZone);
  }

  /**
   * `where` del filtro de historial (contrato 4.8) sobre `receivedAt` (D24, no `triggeredAt`):
   * `from` inclusivo, `to` exclusivo. Lo comparten el historial y las dos métricas.
   */
  function filtro(query: HistoryQuery | PeriodQuery): Prisma.AlertWhereInput {
    const q = query as HistoryQuery;
    const rango: Prisma.DateTimeFilter = {};
    if (q.from !== undefined) rango.gte = instante(q.from);
    if (q.to !== undefined) rango.lt = instante(q.to);
    return {
      ...(q.from !== undefined || q.to !== undefined ? { receivedAt: rango } : {}),
      ...(q.guardId !== undefined ? { guardId: q.guardId } : {}),
      ...(q.userId !== undefined ? { userId: q.userId } : {}),
      ...(q.status !== undefined ? { status: q.status } : {}),
    };
  }

  /** Lo que necesitan las métricas de cada alerta del periodo, con la zona del guardia asignado. */
  async function alertasParaMetricas(query: PeriodQuery & { guardId?: string }) {
    const alertas = await prisma.alert.findMany({
      where: filtro(query),
      select: {
        guardId: true,
        status: true,
        receivedAt: true,
        acceptedAt: true,
        arrivedAt: true,
        escalationReason: true,
        guard: { select: { guardProfile: { select: { zone: true } } } },
      },
    });
    return alertas.map((a) => ({
      guardId: a.guardId,
      status: a.status,
      receivedAt: a.receivedAt,
      acceptedAt: a.acceptedAt,
      arrivedAt: a.arrivedAt,
      escalationReason: a.escalationReason,
      zone: a.guard?.guardProfile?.zone ?? null,
    }));
  }

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

    /**
     * A-05 · Historial con filtros. Devuelve TODAS las alertas que cumplen el filtro,
     * también las activas (contrato 5), de la más reciente a la más antigua por `receivedAt`
     * (D24). El admin las ve completas (D23).
     */
    async listAlerts(query: HistoryQuery): Promise<AlertJson[]> {
      const alertas = await prisma.alert.findMany({
        where: filtro(query),
        include: ALERT_INCLUDE,
        orderBy: [{ receivedAt: 'desc' }, { id: 'desc' }],
      });
      return alertas.map((a) => serializeAdminAlert(a, serialize));
    },

    /** A-06 · Métricas generales del periodo. El cálculo es puro y vive en el dominio. */
    async generalMetrics(query: PeriodQuery): Promise<GeneralMetrics> {
      return generalMetrics(await alertasParaMetricas(query), timeZone);
    },

    /**
     * A-07 · Métricas de un guardia. NOT_FOUND si el id no es de un guardia: sin esto, un id
     * cualquiera devolvería ceros y parecería un guardia sin actividad.
     */
    async guardMetrics(guardId: string, query: PeriodQuery): Promise<GuardMetrics> {
      // Basta con que el id sea de un guardia: exigir además el perfil haría que un guardia
      // al que le falte esa fila (dato inconsistente) pareciera no existir en las métricas.
      const guardia = await prisma.user.findFirst({
        where: { id: guardId, role: Role.guard },
        select: { id: true },
      });
      if (!guardia) throw notFound(NO_ENCONTRADO);
      // El filtro ya limita por guardia: el cálculo del dominio vuelve a filtrar y sale igual.
      const alertas = await alertasParaMetricas({ ...query, guardId });
      return calcularMetricasGuardia(guardId, alertas);
    },

    /** A-08 · Usuarios protegidos, por nombre. Nunca incluye guardias ni administradores. */
    async listProtectedUsers(): Promise<UserJson[]> {
      const usuarios = await prisma.user.findMany({
        where: { role: Role.protected_user },
        orderBy: [{ name: 'asc' }, { id: 'asc' }],
      });
      return usuarios.map(serializeUser);
    },

    /**
     * A-08 · Bloqueados ahora mismo: `blockedUntil` en el futuro. Un bloqueo que ya venció
     * no se borra de la base (es historial), simplemente deja de salir en esta lista.
     */
    async listBlockedUsers(): Promise<UserJson[]> {
      const usuarios = await prisma.user.findMany({
        where: { role: Role.protected_user, blockedUntil: { gt: now() } },
        orderBy: [{ blockedUntil: 'asc' }, { name: 'asc' }, { id: 'asc' }],
      });
      return usuarios.map(serializeUser);
    },

    /**
     * A-08 · Desbloqueo a mano. Quita el bloqueo y pone el contador de falsas alarmas en 0
     * (memoria_admin_repository.dart:177): si no se reiniciara, la siguiente falsa alarma
     * volvería a pasar el límite y el desbloqueo duraría un solo incidente.
     * Desbloquear a quien no está bloqueado no es error: deja el mismo estado final.
     */
    async unblockUser(userId: string): Promise<null> {
      const usuario = await prisma.user.findFirst({
        where: { id: userId, role: Role.protected_user },
        select: { id: true },
      });
      if (!usuario) throw notFound(USUARIO_NO_ENCONTRADO);
      await prisma.user.update({
        where: { id: userId },
        data: { blockedUntil: null, falseAlarmCount: 0 },
      });
      return null;
    },
  };
}
