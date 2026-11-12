import type { FastifyError, FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import {
  AppError,
  internalError,
  invalidInput,
  invalidState,
  notFound,
  serviceUnavailable,
  tooManyRequests,
  unauthorized,
} from '../errors/app-error.js';
import { errorBody } from './envelope.js';
import { describeZodError } from './validate.js';

const MSG_BODY_INVALID = 'El cuerpo de la petición no es válido';
const MSG_BODY_TOO_LARGE = 'El cuerpo de la petición es demasiado grande';
const MSG_DATA_INVALID = 'Los datos enviados no son válidos';
const MSG_CONFLICT = 'La operación entra en conflicto con el estado actual';
const MAX_PATH_IN_MESSAGE = 100;

// Códigos de Prisma (P....) y SQLSTATE de Postgres.
const DB_DOWN_CODES = new Set([
  'P1001',
  'P1002',
  'P1008',
  'P1017',
  'P2024',
  '57P01',
  '57P03',
  '08006',
  '08001',
]);
// Códigos de red de Node: solo cuentan como BD caída si el error viene de Prisma/pg.
const NET_CODES = new Set(['ECONNREFUSED', 'ECONNRESET', 'ETIMEDOUT']);
const DB_INVALID_CODES = new Set([
  'P2000',
  'P2003',
  'P2004',
  'P2005',
  'P2006',
  'P2007',
  'P2011',
  'P2012',
  'P2013',
  'P2014',
  'P2019',
  'P2020',
  '22001',
  '22003',
  '22P02',
  '23502',
  '23503',
  '23514',
]);
const DB_CONFLICT_CODES = new Set(['P2002', '23505']);
const DB_NOT_FOUND_CODES = new Set(['P2001', 'P2015', 'P2018', 'P2025']);

function errCode(err: unknown): string | undefined {
  if (typeof err === 'object' && err !== null && 'code' in err) {
    const c = (err as { code: unknown }).code;
    return typeof c === 'string' ? c : undefined;
  }
  return undefined;
}

function errName(err: unknown): string {
  return err instanceof Error ? err.name : typeof err;
}

function statusOf(err: unknown): number | undefined {
  if (typeof err === 'object' && err !== null && 'statusCode' in err) {
    const s = (err as { statusCode: unknown }).statusCode;
    return typeof s === 'number' ? s : undefined;
  }
  return undefined;
}

function isDbError(err: unknown): boolean {
  const name = errName(err);
  const code = errCode(err);
  return (
    name.startsWith('PrismaClient') ||
    name === 'DriverAdapterError' ||
    (code !== undefined && /^P\d{4}$/.test(code))
  );
}

/** Traduce un error conocido a un AppError seguro para el cliente; null si es inesperado. */
export function toAppError(err: unknown): AppError | null {
  if (err instanceof AppError) return err;
  if (err instanceof ZodError) return invalidInput(describeZodError(err));

  const code = errCode(err);
  const status = statusOf(err);

  if (code !== undefined) {
    // Cualquier fallo de @fastify/jwt (ausente, malformado, firma inválida, vencido): mensaje fijo.
    if (code.startsWith('FST_JWT_') || code.startsWith('FAST_JWT_')) return unauthorized();
    if (code === 'FST_ERR_CTP_BODY_TOO_LARGE') return invalidInput(MSG_BODY_TOO_LARGE);
    if (code.startsWith('FST_ERR_CTP_') || code.startsWith('FST_ERR_VALIDATION')) {
      return invalidInput(MSG_BODY_INVALID);
    }
    if (DB_DOWN_CODES.has(code)) return serviceUnavailable();
    if (NET_CODES.has(code) && isDbError(err)) return serviceUnavailable();
    if (DB_CONFLICT_CODES.has(code)) return invalidState(MSG_CONFLICT);
    if (DB_INVALID_CODES.has(code)) return invalidInput(MSG_DATA_INVALID);
    if (DB_NOT_FOUND_CODES.has(code)) return notFound();
  }
  if (errName(err) === 'PrismaClientInitializationError') return serviceUnavailable();
  if (status === 429) return tooManyRequests();
  if (status === 413) return invalidInput(MSG_BODY_TOO_LARGE);
  if (status === 415) return invalidInput(MSG_BODY_INVALID);
  if (status === 400 && typeof err === 'object' && err !== null && 'validation' in err) {
    return invalidInput(MSG_BODY_INVALID);
  }
  return null;
}

function pathOnly(url: string): string {
  const path = url.split('?')[0]?.split('#')[0] ?? '';
  return path.length > MAX_PATH_IN_MESSAGE ? `${path.slice(0, MAX_PATH_IN_MESSAGE)}…` : path;
}

/** Pila sin su primera línea (que contiene el mensaje original); solo fuera de production. */
function stackWithoutMessage(err: unknown, isProduction: boolean): string | undefined {
  if (isProduction || !(err instanceof Error) || !err.stack) return undefined;
  // Solo los marcos de la pila: una línea del mensaje que empiece con "at " no tiene sangría.
  const frames = err.stack.split('\n').filter((l) => /^\s+at /.test(l));
  return frames.length === 0 ? undefined : frames.join('\n');
}

function isAborted(request: FastifyRequest): boolean {
  // raw.destroyed no sirve: Node destruye la petición al terminar de leer el cuerpo.
  return request.raw.aborted;
}

function logUnexpected(
  request: FastifyRequest,
  err: unknown,
  isProduction: boolean,
  msg: string,
): void {
  // Sin cuerpo, cabeceras ni mensaje original (pueden traer datos personales o SQL).
  const fields = {
    errName: errName(err),
    errCode: errCode(err),
    statusCode: statusOf(err),
    stack: stackWithoutMessage(err, isProduction),
  };
  if (isAborted(request)) request.log.warn(fields, 'Petición abortada por el cliente');
  else request.log.error(fields, msg);
}

/** Para la opción frameworkErrors de Fastify (URL inválida, parámetro demasiado largo, etc.). */
export function createFrameworkErrorHandler(
  isProduction: boolean,
): (err: FastifyError, request: FastifyRequest, reply: FastifyReply) => void {
  return (err: FastifyError, request: FastifyRequest, reply: FastifyReply): void => {
    let appError =
      err.code === 'FST_ERR_BAD_URL' || err.code === 'FST_ERR_MAX_PARAM_LENGTH'
        ? notFound()
        : toAppError(err);
    if (appError === null) {
      logUnexpected(request, err, isProduction, 'Error inesperado');
      appError = internalError();
    }
    void reply.status(appError.httpStatus).send(errorBody(appError));
  };
}

export function registerErrorHandling(
  app: FastifyInstance,
  options: { isProduction: boolean },
): void {
  const { isProduction } = options;

  app.setErrorHandler((err: FastifyError, request: FastifyRequest, reply: FastifyReply) => {
    let appError = toAppError(err);
    if (appError === null) {
      logUnexpected(request, err, isProduction, 'Error inesperado');
      appError = internalError();
    } else if (appError.httpStatus >= 500) {
      logUnexpected(request, err, isProduction, 'Servicio no disponible');
    }
    return reply.status(appError.httpStatus).send(errorBody(appError));
  });

  app.setNotFoundHandler((request, reply) => {
    const err = notFound(`${request.method} ${pathOnly(request.url)} no existe`);
    return reply.status(err.httpStatus).send(errorBody(err));
  });
}
