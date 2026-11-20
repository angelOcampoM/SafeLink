import { z } from 'zod';
import { userMsg } from '../../http/validate.js';

const TOKEN_MSG = userMsg('El token del dispositivo no es válido');

/** Máximo del token push; coincide con el CHECK de device_tokens (D42). */
export const DEVICE_TOKEN_MAX_LENGTH = 512;

/**
 * Cuerpo `{ token }` de PUT /users/me/device-token. No se recorta: solo se aceptan los caracteres
 * de los tokens de FCM/APNs, para no guardar algo distinto de lo que el cliente mandó y para que
 * un control como `\u0000` (que Postgres rechaza en TEXT) sea un 400 y no un 500.
 */
export const deviceTokenBodySchema = z
  .object({
    token: z
      .string(TOKEN_MSG)
      .min(1, TOKEN_MSG)
      .max(DEVICE_TOKEN_MAX_LENGTH, TOKEN_MSG)
      .regex(/^[A-Za-z0-9_:.-]+$/, TOKEN_MSG),
  })
  .strict();
