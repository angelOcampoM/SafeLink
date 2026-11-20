// Reglas puras de la alerta del usuario protegido (BE-03). Equivalen a
// lib/dominio/regla_alerta.dart y a la parte de lib/datos/memoria_alerta_usuario_repository.dart
// que decide estados. Sin consultas: los servicios les pasan los datos ya cargados.
import { AlertStatus, EscalationReason } from '../generated/prisma/enums.js';
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

/** Límites de escalamiento en segundos (ACCEPT_TIMEOUT_SECONDS y CONFIRM_TIMEOUT_SECONDS). */
export interface EscalationLimits {
  acceptTimeoutSeconds: number;
  confirmTimeoutSeconds: number;
}

/**
 * U-09 · A-04 · D14 (BE-05): motivo por el que la alerta debe escalarse ya, o `null`.
 * Equivale a `ReglaAlerta.razonParaEscalar` (regla_alerta.dart:42-54), con un límite propio
 * para cada caso (el front usa el mismo de demostración para los dos):
 *   - `searching` sin que nadie acepte en `acceptTimeoutSeconds` -> "sin respuesta";
 *   - `no_response` (solo existe en datos viejos o de la semilla) -> "sin respuesta";
 *   - `guard_arrived` sin que el usuario confirme en `confirmTimeoutSeconds` -> "sin confirmación".
 * Nunca escalan `pending_location` (aún no se publica) ni `in_progress` (D14, D36).
 * El tiempo se cuenta desde `statusChangedAt`, con la hora del servidor (D24). El límite exacto escala.
 */
export function escalationReasonFor(
  alert: { status: AlertStatus; statusChangedAt: Date },
  now: Date,
  limits: EscalationLimits,
): EscalationReason | null {
  const elapsedMs = now.getTime() - alert.statusChangedAt.getTime();
  switch (alert.status) {
    case AlertStatus.searching:
    case AlertStatus.no_response:
      return elapsedMs >= limits.acceptTimeoutSeconds * 1000 ? EscalationReason.no_response : null;
    case AlertStatus.guard_arrived:
      return elapsedMs >= limits.confirmTimeoutSeconds * 1000 ? EscalationReason.no_confirmation : null;
    default:
      return null;
  }
}

export const ALERT_NOT_ESCALATED = 'Esta alerta ya no está escalada';

/**
 * A-04 (BE-05): mensaje de error de la nota administrativa, o `null` si es válida
 * (regla_alerta.dart:62-67). Se valida recortada; el máximo es ADMIN_NOTE_MAX_LENGTH.
 */
export function adminNoteError(note: string, maxLength: number): string | null {
  const texto = note.trim();
  if (texto.length === 0) return 'Escribe una nota administrativa para resolver la alerta';
  if (texto.length > maxLength) return `La nota no puede pasar de ${String(maxLength)} caracteres`;
  return null;
}

/**
 * A-08 (BE-05): efecto de una falsa alarma sobre el usuario (regla_alerta.dart:71-82 y contrato
 * 5.4). Suma 1; si el total llega al límite, bloquea `blockDays` días desde ahora (y renueva el
 * bloqueo en cada falsa alarma posterior). Por debajo del límite NO toca un bloqueo existente:
 * `blockedUntil` sale `undefined` (en eso el contrato se aparta del mock, que lo borraba).
 */
export function applyFalseAlarm(
  falseAlarmCount: number,
  now: Date,
  limit: number,
  blockDays: number,
): { falseAlarmCount: number; blockedUntil?: Date } {
  const total = falseAlarmCount + 1;
  if (total < limit) return { falseAlarmCount: total };
  return { falseAlarmCount: total, blockedUntil: new Date(now.getTime() + blockDays * 86_400_000) };
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
