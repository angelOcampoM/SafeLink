import { z } from 'zod';
import { userMsg } from '../../http/validate.js';

const EMAIL_MAX = 254;
const PASSWORD_MAX = 128;
const REFRESH_TOKEN_MAX = 512;
const NAME_MIN = 3;
const NAME_MAX = 120;
const PASSWORD_MIN = 8;

// Mismo patrón que ReglaRegistro.correo del front (regla_registro.dart): si el
// cliente lo acepta y el servidor no, el usuario ve un error que no entiende.
const EMAIL_PATTERN = /^[\w.+-]+@[\w-]+(\.[\w-]+)+$/;
const PHONE_PATTERN = /^\d{10}$/;
const PASSWORD_DIGIT = /\d/;

/** Correo, teléfono y contraseña con las mismas reglas que valida el front. */
export const emailField = z
  .string()
  .trim()
  .toLowerCase()
  .min(1, userMsg('Escribe tu correo'))
  .max(EMAIL_MAX, userMsg('El correo es demasiado largo'))
  .regex(EMAIL_PATTERN, userMsg('Correo no válido'));

export const phoneField = z.string().trim().regex(PHONE_PATTERN, userMsg('Debe tener 10 dígitos'));

export const nameField = z
  .string()
  .trim()
  .min(NAME_MIN, userMsg('Escribe tu nombre completo'))
  .max(NAME_MAX, userMsg('El nombre es demasiado largo'));

export const passwordField = z
  .string()
  .min(PASSWORD_MIN, userMsg('Mínimo 8 caracteres'))
  .max(PASSWORD_MAX, userMsg('La contraseña es demasiado larga'))
  .regex(PASSWORD_DIGIT, userMsg('Incluye al menos un número'));

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

// U-01: el registro público crea SIEMPRE un usuario protegido. No hay campo de
// rol: que el rol no se pueda pedir es parte del contrato (D-BE-02).
export const registerBodySchema = z
  .object({ name: nameField, email: emailField, phone: phoneField, password: passwordField })
  .strict();

// U-05: el único ajuste que el usuario protegido cambia de su propia cuenta.
export const settingsBodySchema = z.object({ volumeDoubleClickEnabled: z.boolean() }).strict();
