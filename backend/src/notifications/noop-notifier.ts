// Notificador por defecto (PUSH_PROVIDER=none, D43): no envía nada. Solo deja en el log el id
// de la alerta y conteos; jamás los tokens.
import type { PushLogger, PushNotifier, PushResult } from './push-notifier.js';

export function createNoopNotifier(logger?: PushLogger): PushNotifier {
  return {
    async sendAlert({ tokens, alertId, urgent }): Promise<PushResult> {
      logger?.info(
        { alertId, urgent, recipients: tokens.length },
        'Push desactivado (PUSH_PROVIDER=none): no se envió ninguna notificación',
      );
      return { sent: 0, failed: 0, invalidTokens: [] };
    },
  };
}
