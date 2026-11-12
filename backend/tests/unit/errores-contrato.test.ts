import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  AppError,
  ERROR_CODES,
  MESSAGES,
  alertTaken,
  emailTaken,
  forbidden,
  internalError,
  invalidCredentials,
  invalidInput,
  invalidState,
  normalizeRemainingMeters,
  notFound,
  outsideGeofence,
  serviceUnavailable,
  unauthorized,
  userBlocked,
} from '../../src/errors/app-error.js';
import { errorBody, ok } from '../../src/http/envelope.js';

const dart = readFileSync(resolve(__dirname, '../../../lib/dominio/errores.dart'), 'utf8');

// super('CODE', 'mensaje')
const pares = [...dart.matchAll(/super\('([A-Z_]+)',\s*'([^']*)'\)/g)].map(
  (m) => [m[1]!, m[2]!] as const,
);

describe('Contrato de mensajes con lib/dominio/errores.dart (BE-01 paso 4)', () => {
  it('el front define 7 códigos con mensaje literal (NOT_FOUND e INVALID_STATE son dinámicos)', () => {
    expect(pares.map(([c]) => c).sort()).toEqual(
      [
        'INVALID_CREDENTIALS',
        'EMAIL_TAKEN',
        'USER_BLOCKED',
        'ALERT_TAKEN',
        'OUTSIDE_GEOFENCE',
        'UNAUTHORIZED',
        'SERVICE_UNAVAILABLE',
      ].sort(),
    );
  });

  it('cada mensaje literal del front coincide carácter por carácter con MESSAGES', () => {
    for (const [codigo, mensaje] of pares) {
      expect(MESSAGES[codigo as keyof typeof MESSAGES], codigo).toBe(mensaje);
    }
  });

  it('INVALID_STATE existe en el front con mensaje dinámico', () => {
    expect(dart).toMatch(/super\('INVALID_STATE',\s*mensaje\)/);
    expect(ERROR_CODES).toContain('INVALID_STATE');
  });

  it('el NOT_FOUND por defecto del front es el de MESSAGES', () => {
    expect(dart).toContain("[String mensaje = 'No encontramos lo que buscabas']");
    expect(notFound().message).toBe('No encontramos lo que buscabas');
  });

  it('los 9 códigos del front están en ERROR_CODES y FORBIDDEN es el único extra', () => {
    const frente = new Set([...pares.map(([c]) => c), 'NOT_FOUND', 'INVALID_STATE']);
    expect(frente.size).toBe(9);
    for (const c of frente) expect(ERROR_CODES).toContain(c);
    const extras = ERROR_CODES.filter((c) => !frente.has(c));
    expect(extras).toEqual(['FORBIDDEN']);
    expect(MESSAGES.FORBIDDEN).toBe('No tienes permiso para realizar esta acción.');
  });

  it('MESSAGES cubre todos los códigos salvo INVALID_STATE', () => {
    expect(Object.keys(MESSAGES).sort()).toEqual(
      ERROR_CODES.filter((c) => c !== 'INVALID_STATE').sort(),
    );
  });
});

describe('Tabla código -> HTTP -> cuerpo (docs/API_CONTRATO.md)', () => {
  const casos: Array<[string, () => AppError, string, number, string]> = [
    ['invalidCredentials', invalidCredentials, 'INVALID_CREDENTIALS', 401, MESSAGES.INVALID_CREDENTIALS],
    ['unauthorized', unauthorized, 'UNAUTHORIZED', 401, MESSAGES.UNAUTHORIZED],
    ['forbidden', forbidden, 'FORBIDDEN', 403, MESSAGES.FORBIDDEN],
    ['userBlocked', userBlocked, 'USER_BLOCKED', 403, MESSAGES.USER_BLOCKED],
    ['notFound', () => notFound(), 'NOT_FOUND', 404, MESSAGES.NOT_FOUND],
    ['emailTaken', emailTaken, 'EMAIL_TAKEN', 409, MESSAGES.EMAIL_TAKEN],
    ['alertTaken', alertTaken, 'ALERT_TAKEN', 409, MESSAGES.ALERT_TAKEN],
    ['invalidState', () => invalidState('Estado no válido'), 'INVALID_STATE', 409, 'Estado no válido'],
    ['invalidInput', () => invalidInput('Entrada mala'), 'INVALID_STATE', 400, 'Entrada mala'],
    ['outsideGeofence', () => outsideGeofence(10), 'OUTSIDE_GEOFENCE', 422, MESSAGES.OUTSIDE_GEOFENCE],
    ['serviceUnavailable', serviceUnavailable, 'SERVICE_UNAVAILABLE', 503, MESSAGES.SERVICE_UNAVAILABLE],
    ['internalError', internalError, 'SERVICE_UNAVAILABLE', 500, MESSAGES.SERVICE_UNAVAILABLE],
  ];

  it.each(casos)('%s', (_n, fabrica, code, status, message) => {
    const err = fabrica();
    expect(err.code).toBe(code);
    expect(err.httpStatus).toBe(status);
    const cuerpo = errorBody(err);
    expect(Object.keys(cuerpo)).toEqual(['error']);
    const esperadas =
      code === 'OUTSIDE_GEOFENCE' ? ['code', 'message', 'remainingMeters'] : ['code', 'message'];
    expect(Object.keys(cuerpo.error).sort()).toEqual(esperadas.sort());
    expect(cuerpo.error.code).toBe(code);
    expect(cuerpo.error.message).toBe(message);
  });

  it('ok envuelve en { data }', () => {
    expect(ok({ a: 1 })).toEqual({ data: { a: 1 } });
    expect(Object.keys(ok(null))).toEqual(['data']);
  });

  it('remainingMeters solo viaja en OUTSIDE_GEOFENCE aunque venga en extra', () => {
    const e = new AppError('ALERT_TAKEN', 'x', 409, { remainingMeters: 5 });
    expect(errorBody(e).error).not.toHaveProperty('remainingMeters');
  });
});

describe('remainingMeters', () => {
  it('redondea a 1 decimal', () => {
    expect(errorBody(outsideGeofence(132.449)).error.remainingMeters).toBe(132.4);
    expect(errorBody(outsideGeofence(132.46)).error.remainingMeters).toBe(132.5);
    expect(errorBody(outsideGeofence(0)).error.remainingMeters).toBe(0);
  });

  it.each([Infinity, -Infinity, NaN])('%s -> null', (v) => {
    const cuerpo = errorBody(outsideGeofence(v));
    expect(cuerpo.error).toHaveProperty('remainingMeters', null);
    expect(normalizeRemainingMeters(v)).toBeNull();
  });

  it('nunca negativo', () => {
    expect(errorBody(outsideGeofence(-5)).error.remainingMeters).toBe(0);
    expect(Object.is(errorBody(outsideGeofence(-0.01)).error.remainingMeters, -0)).toBe(false);
  });
});
