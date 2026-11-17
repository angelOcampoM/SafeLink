// Cuerpos de las rutas del usuario protegido (BE-03). Forma exacta de
// lib/datos/nube_alerta_usuario_repository.dart:22-28 y :39.
import { z } from 'zod';
import { userMsg } from '../../http/validate.js';

/** Largo máximo de photoPath: es solo informativo (ver sección 8 del contrato); nunca se usa como ruta. */
const PHOTO_PATH_MAX = 500;

const LOCATION_MSG = userMsg('La ubicación no es válida');
const HEADING_MSG = userMsg('El rumbo no es válido');

/** Coordenadas dentro de rango (sección 9 del contrato). zod 4 ya rechaza NaN e Infinity. */
export const locationField = z
  .object({
    lat: z.number(LOCATION_MSG).min(-90, LOCATION_MSG).max(90, LOCATION_MSG),
    lng: z.number(LOCATION_MSG).min(-180, LOCATION_MSG).max(180, LOCATION_MSG),
  })
  .strict();

/**
 * U-03 · U-04 · U-05 · U-06. El front manda siempre las cinco claves; las opcionales
 * se aceptan ausentes como `null` para tolerar clientes viejos.
 * `shake` es el código de la API para "doble clic de volumen" (contrato, sección 3).
 */
export const createAlertBodySchema = z
  .object({
    triggerMethod: z.enum(['tap', 'hold', 'shake'], userMsg('El método de disparo no es válido')),
    // El front manda UTC con `Z` (toUtc().toIso8601String()); se admite también un offset.
    triggeredAt: z.iso.datetime({ offset: true, ...userMsg('La hora del disparo no es válida') }),
    location: locationField.nullable().optional().default(null),
    heading: z
      .number(HEADING_MSG)
      .int(HEADING_MSG)
      .min(0, HEADING_MSG)
      .max(359, HEADING_MSG)
      .nullable()
      .optional()
      .default(null),
    photoPath: z
      .string()
      .max(PHOTO_PATH_MAX, userMsg('La ruta de la foto es demasiado larga'))
      .nullable()
      .optional()
      .default(null),
  })
  .strict();

export type CreateAlertBody = z.output<typeof createAlertBodySchema>;

/** U-07: una posición nueva del usuario mientras la alerta sigue activa. */
export const locationBodySchema = z.object({ location: locationField }).strict();
