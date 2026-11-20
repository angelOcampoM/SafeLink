// Despachador del aviso push de una alerta (D44). Cuando una alerta entra a `searching` decide a
// quién avisar y se lo entrega al notificador (D43).
//
// Reglas:
//   - Se llama DESPUÉS del commit y fuera de la petición HTTP: `notifyPublished` no espera al push
//     (un notificador lento no retrasa el 201/200) y nunca lanza.
//   - Se relee la alerta: si ya no está en `searching`, tiene guardia o no tiene ubicación, no se envía.
//   - Destinatarios = los mismos que ven la alerta en el listado (isAlertAvailableToGuard), con un
//     token de sesión viva (D42). Un solo mensaje por alerta con todos los tokens, sin repetidos.
//   - Tope de tokens por alerta (PUSH_MAX_TOKENS_PER_ALERT): si se rebasa, van los guardias más
//     cercanos (distancia desde su última ubicación o, si no hay, el centro de cobertura, como D37).
//   - Los tokens que el proveedor declara inválidos se borran, pero solo los de este envío.
//   - Los logs llevan solo ids y conteos: nunca tokens, coordenadas, teléfonos ni cuerpos.
import { haversineMeters, type GeoPoint } from '../domain/geo.js';
import { isAlertAvailableToGuard, toVisibilityGuard } from '../domain/guard-visibility.js';
import { isUrgent } from '../domain/priority.js';
import type { PrismaClient } from '../db/prisma.js';
import { AlertStatus, Role } from '../generated/prisma/enums.js';
import type { DevicesService } from '../modules/devices/service.js';
import type { PushLogger, PushNotifier } from './push-notifier.js';

export interface AlertDispatcherDeps {
  prisma: PrismaClient;
  push: PushNotifier;
  devices: Pick<DevicesService, 'findLiveDevices' | 'deleteTokensOf'>;
  logger: PushLogger;
  /** Zona horaria IANA de los turnos (config TZ_SHIFTS). */
  timeZone: string;
  /** PUSH_MAX_TOKENS_PER_ALERT. */
  maxTokensPerAlert: number;
  /**
   * Falso si no hay un notificador real (PUSH_PROVIDER=none y sin doble inyectado): se omite todo
   * el cálculo y las consultas, porque el no-op no enviaría nada.
   */
  enabled: boolean;
  /** Reloj inyectable para las pruebas. */
  now?: () => Date;
}

export function createAlertDispatcher(deps: AlertDispatcherDeps) {
  const { prisma, push, devices, logger, timeZone, maxTokensPerAlert, enabled } = deps;
  const now = deps.now ?? (() => new Date());

  /**
   * Calcula destinatarios y envía el aviso de una alerta. Punto de entrada reutilizable: BE-06
   * debe llamarlo cuando una alerta vuelva a `searching` (baja de un guardia con alerta en curso,
   * D44). Puede lanzar (error de base de datos o del notificador); `notifyPublished` lo absorbe.
   */
  async function dispatchAlert(alertId: string): Promise<void> {
    if (!enabled) return;
    const alert = await prisma.alert.findUnique({
      where: { id: alertId },
      select: { status: true, guardId: true, lat: true, lng: true, triggerMethod: true },
    });
    if (!alert || alert.status !== AlertStatus.searching || alert.guardId !== null) return;
    if (alert.lat === null || alert.lng === null) return;
    const location: GeoPoint = { lat: alert.lat, lng: alert.lng };

    const at = now();
    const guards = await prisma.user.findMany({
      where: {
        role: Role.guard,
        isActive: true,
        guardProfile: {
          is: {
            coverageCenterLat: { not: null },
            coverageCenterLng: { not: null },
            coverageRadiusMeters: { not: null },
          },
        },
      },
      // Solo lo que usa la visibilidad y la distancia (minimización: sin hash, correo ni teléfono).
      select: {
        id: true,
        isActive: true,
        guardProfile: {
          select: {
            shiftStart: true,
            shiftEnd: true,
            coverageCenterLat: true,
            coverageCenterLng: true,
            coverageRadiusMeters: true,
            lastLocationLat: true,
            lastLocationLng: true,
          },
        },
      },
    });
    const ignoredBy = new Set(
      (
        await prisma.alertIgnore.findMany({ where: { alertId }, select: { guardId: true } })
      ).map((i) => i.guardId),
    );

    // guardId -> distancia a la alerta, solo de quienes la ven disponible.
    const distanceByGuard = new Map<string, number>();
    for (const user of guards) {
      const profile = user.guardProfile;
      if (!profile) continue;
      const guard = toVisibilityGuard(user, profile);
      const visible = isAlertAvailableToGuard(
        { guardId: alert.guardId, status: alert.status, location },
        guard,
        { now: at, timeZone, ignoredByGuard: ignoredBy.has(user.id) },
      );
      if (!visible || !guard.coverage) continue;
      // D37: sin última ubicación, la distancia parte del centro de cobertura.
      const origin: GeoPoint =
        profile.lastLocationLat !== null && profile.lastLocationLng !== null
          ? { lat: profile.lastLocationLat, lng: profile.lastLocationLng }
          : guard.coverage.center;
      distanceByGuard.set(user.id, haversineMeters(origin, location));
    }
    if (distanceByGuard.size === 0) return;

    const devicesFound = await devices.findLiveDevices([...distanceByGuard.keys()], at);
    // Sin repetidos; más cercanos primero y, a igual distancia, orden estable por guardia y token.
    const byToken = new Map<string, { userId: string; distance: number }>();
    for (const d of devicesFound) {
      if (!byToken.has(d.token)) {
        byToken.set(d.token, { userId: d.userId, distance: distanceByGuard.get(d.userId) ?? Infinity });
      }
    }
    const cmp = (x: string, y: string): number => (x < y ? -1 : x > y ? 1 : 0);
    const ordered = [...byToken.entries()].sort(
      ([tokenA, a], [tokenB, b]) =>
        a.distance - b.distance || cmp(a.userId, b.userId) || cmp(tokenA, tokenB),
    );
    if (ordered.length === 0) return;
    if (ordered.length > maxTokensPerAlert) {
      logger.warn(
        { alertId, total: ordered.length, cap: maxTokensPerAlert },
        'Hay más tokens que el tope por alerta: se avisa a los guardias más cercanos',
      );
    }
    const chosen = ordered.slice(0, maxTokensPerAlert);
    const recipients = new Set(chosen.map(([, v]) => v.userId));

    // Urgencia: la misma regla de prioridad del listado (disparo `shake`, domain/priority.ts).
    const result = await push.sendAlert({
      tokens: chosen.map(([token]) => token),
      alertId,
      urgent: isUrgent(alert.triggerMethod),
    });

    // Solo se borran tokens de este envío y de sus destinatarios (nunca uno que el proveedor
    // devuelva sin haberlo recibido de nosotros).
    const sent = new Set(chosen.map(([token]) => token));
    const invalid = [...new Set(result.invalidTokens)].filter((t) => sent.has(t));
    if (invalid.length > 0) {
      const deleted = await devices.deleteTokensOf(invalid, [...recipients]);
      logger.warn({ alertId, invalid: deleted }, 'Tokens push inválidos borrados');
    }
    logger.info(
      { alertId, recipients: recipients.size, sent: result.sent, failed: result.failed },
      'Aviso push de alerta despachado',
    );
  }

  /**
   * Dispara el aviso sin esperar: la respuesta HTTP no depende del push. Un fallo solo deja
   * `{ alertId }` y el tipo de error (el mensaje podría llevar datos).
   */
  function notifyPublished(alertId: string): void {
    void dispatchAlert(alertId).catch((error: unknown) => {
      logger.warn(
        { alertId, errorType: error instanceof Error ? error.name : typeof error },
        'No se pudo despachar el aviso push de la alerta',
      );
    });
  }

  return { dispatchAlert, notifyPublished };
}

export type AlertDispatcher = ReturnType<typeof createAlertDispatcher>;
