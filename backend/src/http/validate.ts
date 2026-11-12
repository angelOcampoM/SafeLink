import { z } from 'zod';
import { invalidInput, notFound } from '../errors/app-error.js';

const MSG_GENERIC = 'Los datos enviados no son válidos';
const MSG_UNKNOWN_FIELDS = 'Hay campos no permitidos';

const KEY_PATTERN = /^[A-Za-z0-9_]{1,40}$/;
const PATH_PATTERN = /^[A-Za-z0-9_.[\]]{1,60}$/;
const MAX_KEYS_SHOWN = 3;

/*
 * Convención de mensajes: un mensaje de zod solo llega al cliente si el esquema lo marcó
 * con userMsg('...') (texto en español definido por nosotros, p. ej. "Mínimo 8 caracteres").
 * Cualquier otro mensaje (los de zod en inglés, valores recibidos) se sustituye por uno
 * genérico en español. Uso: z.string().min(8, userMsg('Mínimo 8 caracteres')).
 * userMsg() recibe solo literales: nunca interpolar el valor recibido (iss.input) ni datos
 * del cliente, porque el texto llega tal cual a la app.
 */
const USER_MSG_MARK = '\u0001userMsg:';

export function userMsg(message: string): { message: string } {
  return { message: `${USER_MSG_MARK}${message}` };
}

function markedMessage(message: string): string | null {
  return message.startsWith(USER_MSG_MARK) ? message.slice(USER_MSG_MARK.length) : null;
}

function fieldName(path: ReadonlyArray<PropertyKey>): string {
  return path.map((p) => String(p)).join('.');
}

function valueAt(input: unknown, path: ReadonlyArray<PropertyKey>): unknown {
  let cur: unknown = input;
  for (const key of path) {
    if (typeof cur !== 'object' || cur === null) return undefined;
    cur = (cur as Record<PropertyKey, unknown>)[key];
  }
  return cur;
}

/** Mensaje en español a partir de los problemas de zod; sin reflejar datos del cliente sin límite. */
export function describeZodError(error: z.ZodError, input?: unknown): string {
  const issue = error.issues[0];
  if (!issue) return MSG_GENERIC;

  const propio = markedMessage(issue.message);
  if (propio !== null) return propio;

  const campo = fieldName(issue.path);
  const campoSeguro = PATH_PATTERN.test(campo) ? campo : null;

  if (issue.code === 'unrecognized_keys') {
    const claves = issue.keys.map(String);
    if (claves.length <= MAX_KEYS_SHOWN && claves.every((k) => KEY_PATTERN.test(k))) {
      return `Campos no permitidos: ${claves.join(', ')}`;
    }
    return MSG_UNKNOWN_FIELDS;
  }
  if (campoSeguro === null) return MSG_GENERIC;
  // Campo faltante: estructural (el valor en esa ruta del input es undefined).
  if (
    issue.code === 'invalid_type' &&
    input !== undefined &&
    valueAt(input, issue.path) === undefined
  ) {
    return `El campo ${campoSeguro} es obligatorio`;
  }
  return `El campo ${campoSeguro} no es válido`;
}

/** Valida con zod; ante error lanza INVALID_STATE 400 con mensaje en español. */
export function parse<S extends z.ZodType>(schema: S, input: unknown): z.output<S> {
  const result = schema.safeParse(input);
  if (!result.success) throw invalidInput(describeZodError(result.error, input));
  return result.data;
}

const uuidSchema = z.uuid();

/** Valida un :id de ruta. Si no es UUID responde NOT_FOUND (no distingue "mal formado" de "no existe"). */
export function parseIdParam(value: unknown): string {
  const result = uuidSchema.safeParse(value);
  if (!result.success) throw notFound();
  return result.data;
}
