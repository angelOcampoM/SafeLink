import { z } from 'zod';
import { userMsg } from '../../http/validate.js';

const EMAIL_MAX = 254;
const PASSWORD_MAX = 128;
const REFRESH_TOKEN_MAX = 512;

export const loginBodySchema = z
  .object({
    email: z
      .string()
      .trim()
      .toLowerCase()
      .min(1, userMsg('El correo es obligatorio'))
      .max(EMAIL_MAX, userMsg('El correo es demasiado largo')),
    password: z
      .string()
      .min(1, userMsg('La contraseña es obligatoria'))
      .max(PASSWORD_MAX, userMsg('La contraseña es demasiado larga')),
  })
  .strict();

// El formato del token (43 caracteres base64url) se exige en el servicio: si no cumple, 401 y
// no 400, y sin abrir transacción (ver REFRESH_TOKEN_PATTERN).
export const refreshBodySchema = z
  .object({ refreshToken: z.string().max(REFRESH_TOKEN_MAX, userMsg('El token no es válido')) })
  .strict();

// userId se valida como UUID en el servicio: si no lo es, la respuesta es data: null (no 400).
export const sessionBodySchema = z
  .object({ userId: z.string().max(100, userMsg('El identificador no es válido')) })
  .strict();
