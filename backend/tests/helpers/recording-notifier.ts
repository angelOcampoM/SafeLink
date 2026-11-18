// Doble de PushNotifier para pruebas (D43): guarda cada llamada y responde lo que se le configure.
import type { PushAlertInput, PushNotifier, PushResult } from '../../src/notifications/push-notifier.js';

export interface RecordingNotifier extends PushNotifier {
  readonly calls: PushAlertInput[];
}

export function createRecordingNotifier(
  respond: (input: PushAlertInput) => PushResult = (input) => ({
    sent: input.tokens.length,
    failed: 0,
    invalidTokens: [],
  }),
): RecordingNotifier {
  const calls: PushAlertInput[] = [];
  return {
    calls,
    async sendAlert(input): Promise<PushResult> {
      calls.push({ ...input, tokens: [...input.tokens] });
      return respond(input);
    },
  };
}
