// Errores de dominio de la API. Espejo de lib/dominio/errores.dart (mensajes idénticos)
// y de la tabla de códigos de docs/API_CONTRATO.md.

export const ERROR_CODES = [
  'INVALID_CREDENTIALS',
  'UNAUTHORIZED',
  'FORBIDDEN',
  'USER_BLOCKED',
  'NOT_FOUND',
  'EMAIL_TAKEN',
  'ALERT_TAKEN',
  'INVALID_STATE',
  'OUTSIDE_GEOFENCE',
  'SERVICE_UNAVAILABLE',
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

export const MESSAGES = {
  INVALID_CREDENTIALS: 'Correo o contraseña incorrectos',
  UNAUTHORIZED: 'Tu sesión terminó. Vuelve a iniciar sesión.',
  FORBIDDEN: 'No tienes permiso para realizar esta acción.',
  USER_BLOCKED: 'Tu cuenta está bloqueada temporalmente',
  NOT_FOUND: 'No encontramos lo que buscabas',
  EMAIL_TAKEN: 'Ese correo ya está registrado',
  ALERT_TAKEN: 'Otro guardia ya aceptó esta alerta',
  OUTSIDE_GEOFENCE: 'Aún no estás en el punto de la alerta',
  SERVICE_UNAVAILABLE: 'No pudimos conectar con el servidor. Intenta de nuevo.',
} as const;

export interface AppErrorExtra {
  /** Solo para OUTSIDE_GEOFENCE; null cuando no se puede calcular. */
  remainingMeters?: number | null;
}

export class AppError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly httpStatus: number,
    public readonly extra: AppErrorExtra = {},
  ) {
    super(message);
    this.name = 'AppError';
  }
}

/** Redondea a 1 decimal (ej. 132.4), mínimo 0; null si no es finito (el front lo lee como infinito). */
export function normalizeRemainingMeters(value: number): number | null {
  if (!Number.isFinite(value)) return null;
  return Math.max(0, Math.round(value * 10) / 10);
}

export const invalidCredentials = (): AppError =>
  new AppError('INVALID_CREDENTIALS', MESSAGES.INVALID_CREDENTIALS, 401);

export const unauthorized = (): AppError =>
  new AppError('UNAUTHORIZED', MESSAGES.UNAUTHORIZED, 401);

export const forbidden = (): AppError => new AppError('FORBIDDEN', MESSAGES.FORBIDDEN, 403);

export const userBlocked = (): AppError => new AppError('USER_BLOCKED', MESSAGES.USER_BLOCKED, 403);

export const notFound = (message: string = MESSAGES.NOT_FOUND): AppError =>
  new AppError('NOT_FOUND', message, 404);

export const emailTaken = (): AppError => new AppError('EMAIL_TAKEN', MESSAGES.EMAIL_TAKEN, 409);

export const alertTaken = (): AppError => new AppError('ALERT_TAKEN', MESSAGES.ALERT_TAKEN, 409);

/** Transición no válida para el estado actual (409). */
export const invalidState = (message: string): AppError =>
  new AppError('INVALID_STATE', message, 409);

/** Entrada inválida: cuerpo, query o regla de validación (400). */
export const invalidInput = (message: string): AppError =>
  new AppError('INVALID_STATE', message, 400);

export const outsideGeofence = (remainingMeters: number): AppError =>
  new AppError('OUTSIDE_GEOFENCE', MESSAGES.OUTSIDE_GEOFENCE, 422, {
    remainingMeters: normalizeRemainingMeters(remainingMeters),
  });

/** Servicio no disponible (base de datos caída, etc.): 503. */
export const serviceUnavailable = (): AppError =>
  new AppError('SERVICE_UNAVAILABLE', MESSAGES.SERVICE_UNAVAILABLE, 503);

/** Error inesperado del servidor, sin detalles: 500. */
export const internalError = (): AppError =>
  new AppError('SERVICE_UNAVAILABLE', MESSAGES.SERVICE_UNAVAILABLE, 500);
