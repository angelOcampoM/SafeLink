import { z } from 'zod';
import { userMsg } from '../../http/validate.js';
import { emailField, nameField, passwordField, phoneField } from '../auth/schemas.js';

const SEARCH_MAX = 100;

/** El front manda `search` siempre, aunque vaya vacío (nube_admin_repository.dart:23). */
export const guardsQuerySchema = z
  .object({
    search: z
      .string()
      .trim()
      .max(SEARCH_MAX, userMsg('La búsqueda es demasiado larga'))
      .optional()
      .default(''),
  })
  .strict();

/**
 * A-01 · Alta. La contraseña inicial la elige el administrador: nunca se fija
 * en el código. Mismas reglas que el registro público.
 */
export const createGuardBodySchema = z
  .object({ name: nameField, email: emailField, phone: phoneField, password: passwordField })
  .strict();

/**
 * A-02 · Edición. El front manda solo los campos que cambian; no se puede
 * cambiar la contraseña ni el turno por aquí (eso es A-03).
 */
export const updateGuardBodySchema = z
  .object({ name: nameField.optional(), email: emailField.optional(), phone: phoneField.optional() })
  .strict()
  .refine((body) => Object.keys(body).length > 0, userMsg('No hay nada que actualizar'));
