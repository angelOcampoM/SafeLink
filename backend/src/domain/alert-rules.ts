// Reglas puras de la alerta del usuario protegido (BE-03). Equivalen a
// lib/dominio/regla_alerta.dart y a la parte de lib/datos/memoria_alerta_usuario_repository.dart
// que decide estados. Sin consultas: los servicios les pasan los datos ya cargados.
import { AlertStatus } from '../generated/prisma/enums.js';
import { haversineMeters, type GeoPoint } from './geo.js';

/** Estados en los que la alerta sigue "activa" para su dueño (enums.dart:32, D15). */
export const ACTIVE_STATUSES: readonly AlertStatus[] = [
  AlertStatus.pending_location,
  AlertStatus.searching,
  AlertStatus.in_progress,
  AlertStatus.guard_arrived,
];

export function isActiveStatus(status: AlertStatus): boolean {
  return ACTIVE_STATUSES.includes(status);
}

/** U-06: sin coordenadas la alerta no se publica a los guardias (memoria_alerta_usuario_repository.dart:31). */
export function initialStatus(location: GeoPoint | null): AlertStatus {
  return location === null ? AlertStatus.pending_location : AlertStatus.searching;
}

/** A-08: un usuario con bloqueo vigente no puede crear alertas. */
export function isBlocked(blockedUntil: Date | null, now: Date): boolean {
  return blockedUntil !== null && blockedUntil.getTime() > now.getTime();
}

/**
 * D24: `triggeredAt` viene del reloj del teléfono. Dentro de ±tolerancia se guarda tal cual;
 * fuera de la ventana se recorta a la hora del servidor (no se rechaza: se perdería una alerta real).
 */
export function clampTriggeredAt(triggeredAt: Date, receivedAt: Date, toleranceSeconds: number): Date {
  const diffMs = Math.abs(triggeredAt.getTime() - receivedAt.getTime());
  return diffMs <= toleranceSeconds * 1000 ? triggeredAt : receivedAt;
}

export const CONFIRM_ONLY_AFTER_ARRIVAL = 'Solo puedes confirmar cuando el guardia ya llegó';
export const ALERT_NOT_ACTIVE = 'Tu alerta ya no está activa';
export const ALREADY_HAS_ACTIVE_ALERT = 'Ya tienes una alerta activa';
/** D36: un guardia con una alerta in_progress o guard_arrived no acepta otra. */
export const GUARD_ALREADY_ATTENDING = 'Ya estás atendiendo otra alerta';
/** G-07: la llegada solo se registra con la alerta en `in_progress` y asignada al guardia (D40). */
export const ALERT_NOT_IN_ATTENDANCE = 'Esta alerta ya no está en atención';

/** Estados en los que la alerta está asignada y en atención por su guardia (D36). */
export const ATTENDED_STATUSES: readonly AlertStatus[] = [
  AlertStatus.in_progress,
  AlertStatus.guard_arrived,
];

/** U-09: solo se confirma con el guardia en el lugar (regla_alerta.dart:34-37). */
export function canUserConfirm(alert: { status: AlertStatus; guardId: string | null }): boolean {
  return alert.status === AlertStatus.guard_arrived && alert.guardId !== null;
}

/**
 * U-07: qué hace una ubicación nueva sobre la alerta. En `pending_location` la publica
 * (pasa a `searching`); en otro estado activo solo actualiza la posición
 * (memoria_alerta_usuario_repository.dart:52-60).
 */
export function statusAfterLocation(status: AlertStatus): AlertStatus {
  return status === AlertStatus.pending_location ? AlertStatus.searching : status;
}

/**
 * U-08 · D27: segundos estimados de llegada, solo con la alerta `in_progress` y ambas
 * ubicaciones conocidas (regla_eta.dart:10-13). Entero y nunca negativo.
 */
export function etaSeconds(
  status: AlertStatus,
  guardLocation: GeoPoint | null,
  alertLocation: GeoPoint | null,
  guardMetersPerMinute: number,
): number | null {
  if (status !== AlertStatus.in_progress || !guardLocation || !alertLocation) return null;
  const meters = haversineMeters(guardLocation, alertLocation);
  // Igual que ReglaEta.segundos: distancia o velocidad no positivas dan 0.
  if (meters <= 0 || guardMetersPerMinute <= 0) return 0;
  return Math.round((meters / guardMetersPerMinute) * 60);
}

/**
 * D47: redondea el ETA hacia arriba al siguiente múltiplo de `stepSeconds` (solo para el dueño).
 * Un ETA exacto cambia ~4 m por segundo y permitiría triangular al guardia. Redondear solo la
 * salida no basta (una búsqueda binaria encontraría el borde del escalón): se combina con
 * `snapToGrid` sobre la entrada, y así lo más que se revela es la celda. 0 se queda en 0 (ya llegó o está encima) y `null` pasa igual; un paso <= 1 no redondea.
 */
export function roundEtaUp(eta: number | null, stepSeconds: number): number | null {
  if (eta === null || stepSeconds <= 1) return eta;
  return Math.ceil(eta / stepSeconds) * stepSeconds;
}
