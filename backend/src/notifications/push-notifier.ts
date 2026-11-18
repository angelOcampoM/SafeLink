// Notificaciones push de alertas (D43). Interfaz PushNotifier con implementaciones intercambiables:
// no-op (por defecto), FCM HTTP v1 y un doble para pruebas.
//
// Reglas de seguridad (D23, D43):
//   - el payload no lleva nombre, teléfono ni ubicación: solo el tipo, el id de la alerta y la urgencia;
//   - ninguna implementación escribe en logs tokens de dispositivo, access tokens ni la llave privada.

export interface PushAlertInput {
  /** Tokens de dispositivo de los guardias destinatarios (ya filtrados por sesión viva, D42). */
  tokens: string[];
  alertId: string;
  /** Prioridad alta de la alerta; viaja como dato para que la app elija el canal. */
  urgent: boolean;
}

export interface PushResult {
  /** Mensajes que el proveedor aceptó. */
  sent: number;
  /** Tokens que no se pudieron entregar (incluye los inválidos). */
  failed: number;
  /** Tokens que el proveedor declaró inexistentes: quien llama debe borrarlos. */
  invalidTokens: string[];
}

export interface PushNotifier {
  /** Nunca lanza por un token: devuelve el resultado agregado. La entrega es de mejor esfuerzo. */
  sendAlert(input: PushAlertInput): Promise<PushResult>;
}

/** Subconjunto del logger de Fastify/pino que usan los notificadores (siempre sin datos sensibles). */
export interface PushLogger {
  info(obj: Record<string, unknown>, msg: string): void;
  warn(obj: Record<string, unknown>, msg: string): void;
}

/** Datos del mensaje; FCM exige que todos los valores sean texto. */
export function buildPushData(alertId: string, urgent: boolean): Record<string, string> {
  return { type: 'alert', alertId, urgent: urgent ? 'true' : 'false' };
}
