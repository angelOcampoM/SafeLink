import { z } from 'zod';
import { AlertStatus } from '../../generated/prisma/enums.js';
import { locationField } from '../../http/location-schema.js';
import { userMsg } from '../../http/validate.js';
import { emailField, nameField, passwordField, phoneField } from '../auth/schemas.js';

const SEARCH_MAX = 100;
const ZONE_MAX = 100;

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

/**
 * A-05 · A-06 · A-07 (BE-07): filtro de historial y periodo de métricas (contrato 4.8).
 *
 * El front manda las fechas con `DateTime.toIso8601String()` sobre una fecha LOCAL
 * (`FiltroHistorialJson.aQuery`, nube_mapeadores.dart:226-227), así que el texto llega sin
 * zona: "2026-11-19T00:00:00.000". Esos se leen en TZ_SHIFTS, no en la zona del servidor
 * (en CI es UTC y el rango se correría seis horas). Si el texto SÍ trae zona ("...Z" o
 * "...-06:00"), se respeta tal cual. La conversión la hace el servicio, que es quien conoce
 * la configuración; el esquema solo valida la forma y deja el texto.
 */
const ISO_SIN_ZONA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?$/;
const ISO_CON_ZONA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$/;

/**
 * La forma la fija el patrón; el día del calendario se revisa aparte porque `Date.parse`
 * acepta un 31 de febrero y lo corre al 3 de marzo en silencio: un filtro con una fecha
 * imposible debe ser 400, no un rango distinto al que pidió el administrador.
 */
function fechaValida(texto: string): boolean {
  if (!ISO_CON_ZONA.test(texto) && !ISO_SIN_ZONA.test(texto)) return false;
  const [anio, mes, dia] = texto.slice(0, 10).split('-').map(Number) as [number, number, number];
  const comoFecha = new Date(Date.UTC(anio, mes - 1, dia));
  if (
    comoFecha.getUTCFullYear() !== anio ||
    comoFecha.getUTCMonth() !== mes - 1 ||
    comoFecha.getUTCDate() !== dia
  ) {
    return false;
  }
  // La hora: el patrón ya limita los dígitos, pero no descarta 25:00 ni 10:61.
  return !Number.isNaN(Date.parse(ISO_CON_ZONA.test(texto) ? texto : `${texto}Z`));
}

const fechaIso = z
  .string(userMsg('La fecha no es válida'))
  .trim()
  .refine(fechaValida, userMsg('La fecha no es válida'));

/**
 * Los códigos de `status` son los del enum de la base, no una lista aparte: así un estado
 * nuevo en el modelo queda filtrable sin tocar este archivo y no se puede desalinear.
 */
const estadoField = z.enum(AlertStatus, userMsg('El estado no es válido'));

/** A-06 · A-07: solo el periodo. */
export const periodQuerySchema = z
  .object({ from: fechaIso.optional(), to: fechaIso.optional() })
  .strict();

/** A-05: periodo más guardia, usuario y estado. Todos opcionales y combinables. */
export const historyQuerySchema = z
  .object({
    from: fechaIso.optional(),
    to: fechaIso.optional(),
    guardId: z.uuid(userMsg('El guardia no es válido')).optional(),
    userId: z.uuid(userMsg('El usuario no es válido')).optional(),
    status: estadoField.optional(),
  })
  .strict();

export type HistoryQuery = z.infer<typeof historyQuerySchema>;
export type PeriodQuery = z.infer<typeof periodQuerySchema>;

/**
 * A-03 · Cobertura de un guardia (turno, centro, radio y zona).
 *
 * El esquema solo exige la FORMA. Las tres reglas de negocio (formato del turno, radio dentro
 * de rango y zona no vacía) se aplican en el servicio y en ese orden, con los mismos mensajes
 * que el front (`regla_turno.dart:31`, `regla_geocerca.dart:43-44,50`): el radio mínimo y el
 * máximo son configuración (COVERAGE_RADIUS_*), así que el esquema no los conoce.
 */
export const coverageBodySchema = z
  .object({
    shiftStart: z.string(userMsg('Usa el formato HH:mm')).trim(),
    shiftEnd: z.string(userMsg('Usa el formato HH:mm')).trim(),
    center: locationField,
    // Entero: el front lo castea con `as int?` (contrato, sección 1).
    radiusMeters: z.int(userMsg('El radio de cobertura no es válido')),
    zone: z.string(userMsg('Escribe la zona de cobertura')).max(
      ZONE_MAX,
      userMsg('La zona es demasiado larga'),
    ),
  })
  .strict();

export type CoverageBody = z.infer<typeof coverageBodySchema>;
