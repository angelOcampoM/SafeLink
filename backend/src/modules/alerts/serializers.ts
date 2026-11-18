// Forma `AlertaJson` del front (nube_mapeadores.dart:117-165, contrato 4.4). Se envían
// SIEMPRE todas las claves (con null si no aplican). Campo por campo: jamás spread del
// registro, para que un campo interno (receivedAt, photoKey, statusChangedAt) no se filtre.
import { etaSeconds, isActiveStatus } from '../../domain/alert-rules.js';
import { isAssignedTo } from '../../domain/guard-visibility.js';
import type {
  AlertStatus,
  EscalationReason,
  Resolution,
  TriggerMethod,
} from '../../generated/prisma/enums.js';
import type { PointJson } from '../admin/serializers.js';

/** Lo que el serializador necesita de la alerta y sus relaciones. */
export interface AlertRecord {
  id: string;
  userId: string;
  guardId: string | null;
  status: AlertStatus;
  triggerMethod: TriggerMethod;
  photoKey: string | null;
  evidenceIncomplete: boolean;
  lat: number | null;
  lng: number | null;
  heading: number | null;
  triggeredAt: Date;
  acceptedAt: Date | null;
  arrivedAt: Date | null;
  closedAt: Date | null;
  escalationReason: EscalationReason | null;
  resolution: Resolution | null;
  adminNote: string | null;
  user: { name: string; phone: string };
  guard: {
    name: string;
    guardProfile: { lastLocationLat: number | null; lastLocationLng: number | null } | null;
  } | null;
}

export interface AlertJson {
  id: string;
  userId: string;
  userName: string | null;
  userPhone: string | null;
  guardId: string | null;
  guardName: string | null;
  status: AlertStatus;
  triggerMethod: TriggerMethod;
  photoUrl: string | null;
  evidenceIncomplete: boolean;
  location: PointJson | null;
  heading: number | null;
  triggeredAt: string;
  acceptedAt: string | null;
  arrivedAt: string | null;
  closedAt: string | null;
  escalationReason: EscalationReason | null;
  resolution: Resolution | null;
  adminNote: string | null;
  etaSeconds: number | null;
}

/** Relaciones que hay que incluir en la consulta para poder serializar. */
export const ALERT_INCLUDE = {
  user: { select: { name: true, phone: true } },
  guard: {
    select: {
      name: true,
      guardProfile: { select: { lastLocationLat: true, lastLocationLng: true } },
    },
  },
} as const;

export interface SerializeOptions {
  /** URL de la foto a partir de su llave (D2); null si no hay foto. */
  photoUrl: (alertId: string, photoKey: string | null) => string | null;
  /** GUARD_METERS_PER_MINUTE para el ETA (D27). */
  guardMetersPerMinute: number;
}

const iso = (d: Date | null): string | null => (d ? d.toISOString() : null);

function point(lat: number | null, lng: number | null): PointJson | null {
  return lat === null || lng === null ? null : { lat, lng };
}

/**
 * Vista del DUEÑO de la alerta: la ve completa (D23). El admin tendrá su propia vista
 * en BE-05 (minimización de datos); la del guardia es `serializeGuardAlert`.
 */
export function serializeOwnAlert(alert: AlertRecord, options: SerializeOptions): AlertJson {
  const location = point(alert.lat, alert.lng);
  const guardLocation = alert.guard?.guardProfile
    ? point(alert.guard.guardProfile.lastLocationLat, alert.guard.guardProfile.lastLocationLng)
    : null;
  return {
    id: alert.id,
    userId: alert.userId,
    userName: alert.user.name,
    userPhone: alert.user.phone,
    guardId: alert.guardId,
    guardName: alert.guard?.name ?? null,
    status: alert.status,
    triggerMethod: alert.triggerMethod,
    photoUrl: options.photoUrl(alert.id, alert.photoKey),
    evidenceIncomplete: alert.evidenceIncomplete,
    location,
    heading: alert.heading,
    triggeredAt: alert.triggeredAt.toISOString(),
    acceptedAt: iso(alert.acceptedAt),
    arrivedAt: iso(alert.arrivedAt),
    closedAt: iso(alert.closedAt),
    escalationReason: alert.escalationReason,
    resolution: alert.resolution,
    adminNote: alert.adminNote,
    etaSeconds: etaSeconds(alert.status, guardLocation, location, options.guardMetersPerMinute),
  };
}

/**
 * Vista del GUARDIA (D23, minimización de datos). `userPhone` solo lo recibe el guardia
 * asignado mientras la alerta sigue activa; `location` solo existe con la alerta activa
 * (después es dato personal sin función operativa); `photoUrl` se conserva como evidencia.
 * El ETA se calcula con la ubicación real, antes de ocultarla.
 */
export function serializeGuardAlert(
  alert: AlertRecord,
  viewerGuardId: string,
  options: SerializeOptions,
): AlertJson {
  const active = isActiveStatus(alert.status);
  const location = point(alert.lat, alert.lng);
  const guardLocation = alert.guard?.guardProfile
    ? point(alert.guard.guardProfile.lastLocationLat, alert.guard.guardProfile.lastLocationLng)
    : null;
  return {
    id: alert.id,
    userId: alert.userId,
    userName: alert.user.name,
    userPhone: active && isAssignedTo(alert, viewerGuardId) ? alert.user.phone : null,
    guardId: alert.guardId,
    guardName: alert.guard?.name ?? null,
    status: alert.status,
    triggerMethod: alert.triggerMethod,
    photoUrl: options.photoUrl(alert.id, alert.photoKey),
    evidenceIncomplete: alert.evidenceIncomplete,
    location: active ? location : null,
    heading: alert.heading,
    triggeredAt: alert.triggeredAt.toISOString(),
    acceptedAt: iso(alert.acceptedAt),
    arrivedAt: iso(alert.arrivedAt),
    closedAt: iso(alert.closedAt),
    escalationReason: alert.escalationReason,
    resolution: alert.resolution,
    adminNote: alert.adminNote,
    etaSeconds: etaSeconds(alert.status, guardLocation, location, options.guardMetersPerMinute),
  };
}
