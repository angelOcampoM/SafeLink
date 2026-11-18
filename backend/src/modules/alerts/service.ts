// U-03 · U-04 · U-05 · U-06 · U-07 · U-09 (BE-03): alertas del usuario protegido.
// Equivale a lib/datos/memoria_alerta_usuario_repository.dart, con la hora del servidor (D24),
// una alerta activa por usuario (D15) y cada cambio de estado en alert_status_history.
import {
  ACTIVE_STATUSES,
  ALERT_NOT_ACTIVE,
  ALREADY_HAS_ACTIVE_ALERT,
  CONFIRM_ONLY_AFTER_ARRIVAL,
  canUserConfirm,
  clampTriggeredAt,
  initialStatus,
  isActiveStatus,
  isBlocked,
  statusAfterLocation,
} from '../../domain/alert-rules.js';
import type { GeoPoint } from '../../domain/geo.js';
import type { PrismaClient } from '../../db/prisma.js';
import { invalidState, notFound, unauthorized, userBlocked } from '../../errors/app-error.js';
import { Prisma } from '../../generated/prisma/client.js';
import { AlertStatus } from '../../generated/prisma/enums.js';
import type { CreateAlertBody } from './schemas.js';
import {
  ALERT_INCLUDE,
  serializeOwnAlert,
  type AlertJson,
  type SerializeOptions,
} from './serializers.js';

export const ALERT_NOT_FOUND = 'La alerta ya no existe';

/** Nombre del índice parcial de D15 (migración init). */
const ONE_ACTIVE_INDEX = 'alerts_one_active_per_user_idx';

/**
 * Aviso de cambio de una alerta. `dispatch` es verdadero si la alerta entró a `searching` o se
 * movió estando en `searching` (cambia el listado de los guardias, D34); salir de `searching`
 * lo publican accept/ignore (guardia) o la escalada (BE-05).
 */
export interface AlertChange {
  userId: string;
  alertId: string;
  dispatch: boolean;
}

export interface AlertsServiceDeps {
  prisma: PrismaClient;
  serialize: SerializeOptions;
  triggeredAtToleranceSeconds: number;
  /** Avisa que cambió una alerta (canales alerts/active, guard/alerts y guard/alerts/:id). */
  onAlertChanged?: (change: AlertChange) => void;
  /** Reloj inyectable para las pruebas. */
  now?: () => Date;
}

function esAlertaActivaDuplicada(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') return false;
  const destino = error.meta?.['target'];
  const texto = Array.isArray(destino) ? destino.join(',') : String(destino ?? '');
  // Con el adaptador pg el destino puede venir como el nombre del índice o como la columna.
  return texto.includes(ONE_ACTIVE_INDEX) || texto.includes('user_id');
}

export function createAlertsService(deps: AlertsServiceDeps) {
  const { prisma, serialize, triggeredAtToleranceSeconds } = deps;
  const now = deps.now ?? (() => new Date());
  const avisar = (change: AlertChange): void => deps.onAlertChanged?.(change);

  /** Alerta del usuario o NOT_FOUND (una ajena no revela que existe, D9). */
  async function alertaPropia(userId: string, alertId: string) {
    const alert = await prisma.alert.findUnique({ where: { id: alertId }, include: ALERT_INCLUDE });
    if (!alert || alert.userId !== userId) throw notFound(ALERT_NOT_FOUND);
    return alert;
  }

  return {
    /**
     * U-03 · U-04 · U-05 · U-06. Sin ubicación la alerta queda en `pending_location` y no se
     * publica; sin foto se guarda igual y queda marcada como evidencia incompleta.
     * `photoKey` lo pone la subida de la foto (D2); `photoPath` del cliente nunca se usa como ruta.
     */
    async create(userId: string, body: CreateAlertBody, photoKey: string | null = null): Promise<AlertJson> {
      const receivedAt = now();
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { blockedUntil: true, isActive: true },
      });
      if (!user?.isActive) throw unauthorized();
      if (isBlocked(user.blockedUntil, receivedAt)) throw userBlocked();

      const location: GeoPoint | null = body.location;
      const status = initialStatus(location);
      const triggeredAt = clampTriggeredAt(new Date(body.triggeredAt), receivedAt, triggeredAtToleranceSeconds);

      try {
        const creada = await prisma.$transaction(async (tx) => {
          // D15: el índice parcial es la garantía; esta consulta da el mensaje claro antes.
          const activa = await tx.alert.findFirst({
            where: { userId, status: { in: [...ACTIVE_STATUSES] } },
            select: { id: true },
          });
          if (activa) throw invalidState(ALREADY_HAS_ACTIVE_ALERT);

          const alert = await tx.alert.create({
            data: {
              userId,
              status,
              triggerMethod: body.triggerMethod,
              photoKey,
              evidenceIncomplete: photoKey === null,
              lat: location?.lat ?? null,
              lng: location?.lng ?? null,
              heading: body.heading,
              triggeredAt,
              receivedAt,
              statusChangedAt: receivedAt,
            },
            include: ALERT_INCLUDE,
          });
          await tx.alertStatusHistory.create({
            data: { alertId: alert.id, fromStatus: null, toStatus: status, actorId: userId, at: receivedAt },
          });
          return alert;
        });
        avisar({ userId, alertId: creada.id, dispatch: creada.status === AlertStatus.searching });
        return serializeOwnAlert(creada, serialize);
      } catch (error) {
        if (esAlertaActivaDuplicada(error)) throw invalidState(ALREADY_HAS_ACTIVE_ALERT);
        throw error;
      }
    },

    /** Historial del usuario: todas sus alertas, también la activa, la más reciente primero. */
    async mine(userId: string): Promise<AlertJson[]> {
      const alerts = await prisma.alert.findMany({
        where: { userId },
        include: ALERT_INCLUDE,
        orderBy: [{ triggeredAt: 'desc' }, { receivedAt: 'desc' }],
      });
      return alerts.map((a) => serializeOwnAlert(a, serialize));
    },

    /** La alerta activa del usuario (a lo más una, D15) o null. Snapshot del canal alerts/active. */
    async active(userId: string): Promise<AlertJson | null> {
      const alert = await prisma.alert.findFirst({
        where: { userId, status: { in: [...ACTIVE_STATUSES] } },
        include: ALERT_INCLUDE,
      });
      return alert ? serializeOwnAlert(alert, serialize) : null;
    },

    /**
     * U-07 · U-06: una posición nueva. En `pending_location` publica la alerta (`searching`);
     * en los demás estados activos solo la mueve. Fuera de un estado activo, 409.
     */
    async addLocation(userId: string, alertId: string, location: GeoPoint): Promise<null> {
      const alert = await alertaPropia(userId, alertId);
      if (!isActiveStatus(alert.status)) throw invalidState(ALERT_NOT_ACTIVE);

      const at = now();
      const next = statusAfterLocation(alert.status);
      const cambiaEstado = next !== alert.status;
      await prisma.$transaction(async (tx) => {
        // Condicionado al estado leído: si otro proceso lo cambió, no se pisa.
        const { count } = await tx.alert.updateMany({
          where: { id: alertId, status: alert.status },
          data: {
            lat: location.lat,
            lng: location.lng,
            ...(cambiaEstado ? { status: next, statusChangedAt: at } : {}),
          },
        });
        if (count === 0) throw invalidState(ALERT_NOT_ACTIVE);
        if (cambiaEstado) {
          await tx.alertStatusHistory.create({
            data: { alertId, fromStatus: alert.status, toStatus: next, actorId: userId, at },
          });
        }
      });
      // Entra a la lista de los guardias al pasar a searching, o se mueve estando en ella.
      avisar({ userId, alertId, dispatch: next === AlertStatus.searching });
      return null;
    },

    /** U-09: el usuario cierra la alerta, solo con el guardia ya en el lugar. */
    async confirm(userId: string, alertId: string): Promise<AlertJson> {
      const alert = await alertaPropia(userId, alertId);
      if (!canUserConfirm(alert)) throw invalidState(CONFIRM_ONLY_AFTER_ARRIVAL);

      const at = now();
      const cerrada = await prisma.$transaction(async (tx) => {
        const { count } = await tx.alert.updateMany({
          where: { id: alertId, status: AlertStatus.guard_arrived },
          data: { status: AlertStatus.closed, closedAt: at, statusChangedAt: at },
        });
        if (count === 0) throw invalidState(CONFIRM_ONLY_AFTER_ARRIVAL);
        await tx.alertStatusHistory.create({
          data: {
            alertId,
            fromStatus: AlertStatus.guard_arrived,
            toStatus: AlertStatus.closed,
            actorId: userId,
            at,
          },
        });
        return tx.alert.findUniqueOrThrow({ where: { id: alertId }, include: ALERT_INCLUDE });
      });
      // Se confirma desde guard_arrived: ya no estaba en searching, no toca el listado.
      avisar({ userId, alertId, dispatch: false });
      return serializeOwnAlert(cerrada, serialize);
    },
  };
}

export type AlertsService = ReturnType<typeof createAlertsService>;
