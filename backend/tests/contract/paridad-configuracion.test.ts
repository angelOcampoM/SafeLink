// CR-B04: los valores por defecto del front (lib/dominio/configuracion.dart) y del backend
// (src/config/env.ts) deben coincidir. Si alguien cambia uno sin el otro, el front calcula una
// geocerca, un tiempo o un intervalo distinto al que valida la API (D54, punto 5: un front que
// manda ubicación más rápido que LOCATION_UPDATE_SECONDS vuelve a provocar 429).
// Leer Dart con una expresión regular es frágil: si no encuentra un valor, la prueba FALLA.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { envSchema } from '../../src/config/env.js';

const RAIZ = resolve(import.meta.dirname, '..', '..', '..');
const ARCHIVO_DART = 'lib/dominio/configuracion.dart';
const dart = readFileSync(resolve(RAIZ, ARCHIVO_DART), 'utf8');

/** Default de `this.<campo> = <entero>` en el constructor de Configuracion. */
function defaultDart(campo: string): number {
  const constructor = /const Configuracion\(\{([\s\S]*?)\}\);/.exec(dart)?.[1];
  if (constructor === undefined) throw new Error(`No se encontró el constructor de Configuracion en ${ARCHIVO_DART}`);
  const valor = new RegExp(String.raw`this\.${campo}\s*=\s*(\d+)\s*,`).exec(constructor)?.[1];
  if (valor === undefined) {
    throw new Error(`No se encontró el valor por defecto de "${campo}" en ${ARCHIVO_DART}: ¿cambió de nombre o de forma?`);
  }
  return Number(valor);
}

type Llave = keyof typeof envSchema.shape;

// [campo del front, variable del backend, cuántas unidades del backend vale una del front]
const pares: [string, Llave, number][] = [
  ['radioGeocercaMetros', 'GEOFENCE_METERS', 1],
  ['minutosAceptacion', 'ACCEPT_TIMEOUT_SECONDS', 60],
  ['minutosConfirmacion', 'CONFIRM_TIMEOUT_SECONDS', 60],
  ['segundosActualizacionUbicacion', 'LOCATION_UPDATE_SECONDS', 1],
  ['limiteFalsasAlarmas', 'FALSE_ALARM_LIMIT', 1],
  ['diasBloqueo', 'BLOCK_DAYS', 1],
  ['metrosPorMinutoEspera', 'WAIT_METERS_PER_MINUTE', 1],
  ['metrosPorMinutoGuardia', 'GUARD_METERS_PER_MINUTE', 1],
  ['radioCoberturaMinMetros', 'COVERAGE_RADIUS_MIN_METERS', 1],
  ['radioCoberturaMaxMetros', 'COVERAGE_RADIUS_MAX_METERS', 1],
];

// Solo los defaults del código: un .env local no debe hacer pasar ni fallar esta prueba.
const backend = envSchema
  .pick(Object.fromEntries(pares.map(([, llave]) => [llave, true])) as Record<Llave, true>)
  .parse({}) as Record<Llave, unknown>;

describe('Paridad de configuración front <-> backend (CR-B04)', () => {
  it.each(pares)('%s (front) coincide con %s (backend)', (campo, llave, factor) => {
    const front = defaultDart(campo) * factor;
    const api = backend[llave];
    expect(
      api,
      `Desfase: ${campo} = ${String(front / factor)} en ${ARCHIVO_DART} equivale a ${String(front)}, ` +
        `pero ${llave} = ${String(api)} en backend/src/config/env.ts. Cambia los dos juntos.`,
    ).toBe(front);
  });

  it('falla con un mensaje claro si un campo del front no existe', () => {
    expect(() => defaultDart('campoQueNoExiste')).toThrow(/campoQueNoExiste/);
  });
});
