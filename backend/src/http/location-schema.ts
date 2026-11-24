// Piezas de esquema zod compartidas entre módulos (alertas del usuario y ubicación del guardia).
import { z } from 'zod';
import { userMsg } from './validate.js';

const LOCATION_MSG = userMsg('La ubicación no es válida');

/** Coordenadas dentro de rango (sección 9 del contrato). zod 4 ya rechaza NaN e Infinity. */
export const locationField = z
  .object({
    lat: z.number(LOCATION_MSG).min(-90, LOCATION_MSG).max(90, LOCATION_MSG),
    lng: z.number(LOCATION_MSG).min(-180, LOCATION_MSG).max(180, LOCATION_MSG),
  })
  .strict();

/** Cuerpo `{ location: {lat,lng} }` de POST /alerts/:id/locations (U-07) y PUT /guard/location (G-06). */
export const locationBodySchema = z.object({ location: locationField }).strict();
