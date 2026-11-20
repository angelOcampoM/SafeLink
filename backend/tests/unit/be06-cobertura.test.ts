// BE-06 · Validación de la forma del cuerpo de la cobertura (A-03). Unitaria: no toca la base.
// Las tres reglas de negocio (turno, radio y zona) viven en el servicio porque dependen de la
// configuración; aquí se fija lo que el esquema sí decide.
import { describe, expect, it } from 'vitest';
import { describeZodError } from '../../src/http/validate.js';
import { coverageBodySchema } from '../../src/modules/admin/schemas.js';

const VALIDO = {
  shiftStart: '08:00',
  shiftEnd: '16:00',
  center: { lat: 18.84, lng: -99.18 },
  radiusMeters: 4000,
  zone: 'Emiliano Zapata',
};

/** Mensaje en español que vería la app, o null si el cuerpo es válido. */
function error(body: unknown): string | null {
  const r = coverageBodySchema.safeParse(body);
  return r.success ? null : describeZodError(r.error, body);
}

describe('coverageBodySchema', () => {
  it('acepta el cuerpo que manda el front (nube_admin_repository.dart:56-62)', () => {
    expect(error(VALIDO)).toBeNull();
  });

  // Un campo que falta se reporta con el mensaje del propio campo, no con un
  // "es obligatorio" genérico: así la app muestra algo que el usuario entiende.
  it.each([
    ['shiftStart', 'Usa el formato HH:mm'],
    ['shiftEnd', 'Usa el formato HH:mm'],
    ['center', 'El campo center es obligatorio'],
    ['radiusMeters', 'El radio de cobertura no es válido'],
    ['zone', 'Escribe la zona de cobertura'],
  ])('si falta %s, el error lo dice en español', (campo, mensaje) => {
    const body: Record<string, unknown> = { ...VALIDO };
    delete body[campo];
    expect(error(body)).toBe(mensaje);
  });

  it('un campo que no existe se rechaza en lugar de ignorarse', () => {
    expect(error({ ...VALIDO, extra: 1 })).toBe('Campos no permitidos: extra');
  });

  it('el radio tiene que ser entero: el front lo castea con as int', () => {
    expect(error({ ...VALIDO, radiusMeters: 4000.5 })).toBe('El radio de cobertura no es válido');
    expect(error({ ...VALIDO, radiusMeters: '4000' })).toBe('El radio de cobertura no es válido');
  });

  it('el esquema no juzga si el radio está en rango: eso es del servicio', () => {
    expect(error({ ...VALIDO, radiusMeters: 1 })).toBeNull();
    expect(error({ ...VALIDO, radiusMeters: 999_999 })).toBeNull();
  });

  it('las coordenadas tienen que estar en rango', () => {
    expect(error({ ...VALIDO, center: { lat: 91, lng: 0 } })).toBe('La ubicación no es válida');
    expect(error({ ...VALIDO, center: { lat: 0, lng: 181 } })).toBe('La ubicación no es válida');
    expect(error({ ...VALIDO, center: { lat: 0 } })).toBe('La ubicación no es válida');
  });

  it('el centro no admite campos de más (no es un punto cualquiera)', () => {
    expect(error({ ...VALIDO, center: { lat: 0, lng: 0, alt: 10 } })).toBe(
      'Campos no permitidos: alt',
    );
  });

  it('una zona demasiado larga se rechaza', () => {
    expect(error({ ...VALIDO, zone: 'z'.repeat(101) })).toBe('La zona es demasiado larga');
  });

  it('el turno recortado vale: el front puede mandar espacios', () => {
    const r = coverageBodySchema.safeParse({ ...VALIDO, shiftStart: ' 08:00 ' });
    expect(r.success).toBe(true);
    expect(r.success && r.data.shiftStart).toBe('08:00');
  });
});
