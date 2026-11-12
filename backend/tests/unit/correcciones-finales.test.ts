// BE-01 paso 6, correcciones finales: visibilidad con guardId ajeno, TZ_SHIFTS, DST y policiesEqual.
import { describe, expect, it } from 'vitest';
import {
  isAlertAvailableToGuard,
  isAlertVisibleToGuard,
  type VisibilityAlert,
  type VisibilityContext,
  type VisibilityGuard,
} from '../../src/domain/guard-visibility.js';
import { isShiftActive, localMinutesOfDay } from '../../src/domain/shift.js';
import { ConfigError, loadConfig } from '../../src/config/env.js';
import { AppError } from '../../src/errors/app-error.js';
import { Role } from '../../src/generated/prisma/enums.js';
import { policiesEqual } from '../../src/security/policies.js';
import { assertGuardCanSee } from '../../src/security/ownership.js';

const CENTRO = { lat: 19.4326, lng: -99.1332 };
const guardia: VisibilityGuard = {
  id: 'g-1',
  active: true,
  shiftStart: '08:00',
  shiftEnd: '16:00',
  coverage: { center: CENTRO, radiusMeters: 1000 },
};
const ajena: VisibilityAlert = {
  guardId: 'g-2',
  status: 'searching',
  location: { lat: 19.433, lng: -99.1332 },
};
const ctx = (extra: Partial<VisibilityContext> = {}): VisibilityContext => ({
  now: new Date('2026-03-10T18:00:00Z'), // 12:00 en Ciudad de México
  timeZone: 'America/Mexico_City',
  ignoredByGuard: false,
  ...extra,
});

describe('guard-visibility: searching con guardId de OTRO guardia', () => {
  it('sin skipStatusCheck NO está disponible ni visible', () => {
    expect(isAlertAvailableToGuard(ajena, guardia, ctx())).toBe(false);
    expect(isAlertVisibleToGuard(ajena, guardia, ctx())).toBe(false);
  });

  it('assertGuardCanSee lanza NOT_FOUND 404', () => {
    let error: unknown;
    try {
      assertGuardCanSee(ajena, guardia, ctx());
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(AppError);
    expect((error as AppError).code).toBe('NOT_FOUND');
    expect((error as AppError).httpStatus).toBe(404);
  });

  it('con skipStatusCheck pasa la visibilidad (solo para decidir 404 vs 409)', () => {
    const c = ctx({ skipStatusCheck: true });
    expect(isAlertAvailableToGuard(ajena, guardia, c)).toBe(true);
    expect(isAlertVisibleToGuard(ajena, guardia, c)).toBe(true);
    expect(() => assertGuardCanSee(ajena, guardia, c)).not.toThrow();
  });

  it('con skipStatusCheck siguen aplicando cobertura, turno, ignorada y guardia inactivo', () => {
    const c = ctx({ skipStatusCheck: true });
    expect(isAlertAvailableToGuard({ ...ajena, location: { lat: 19.5, lng: -99.13 } }, guardia, c)).toBe(false);
    expect(isAlertAvailableToGuard(ajena, guardia, { ...c, ignoredByGuard: true })).toBe(false);
    expect(isAlertAvailableToGuard(ajena, { ...guardia, active: false }, c)).toBe(false);
    expect(isAlertAvailableToGuard(ajena, { ...guardia, shiftStart: '16:00', shiftEnd: '20:00' }, c)).toBe(
      false,
    );
  });

  it('searching sin asignar sigue disponible (control)', () => {
    expect(isAlertAvailableToGuard({ ...ajena, guardId: null }, guardia, ctx())).toBe(true);
  });
});

describe('env: TZ_SHIFTS', () => {
  const base = { NODE_ENV: 'test', JWT_SECRET: 'x'.repeat(32) };

  it.each(['Mars/Olympus', '', 'no es zona', 'America/Nowhere'])('"%s" -> ConfigError en español', (tz) => {
    let error: unknown;
    try {
      loadConfig({ ...base, TZ_SHIFTS: tz });
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(ConfigError);
    const msg = (error as ConfigError).message;
    expect(msg).toContain('Configuración inválida');
    expect(msg).toContain('TZ_SHIFTS');
    expect((error as ConfigError).details.join(' ')).not.toMatch(/Too small|Invalid|expected/i);
  });

  it.each(['America/Mexico_City', 'America/Tijuana'])('"%s" es válida', (tz) => {
    expect(loadConfig({ ...base, TZ_SHIFTS: tz }).TZ_SHIFTS).toBe(tz);
  });

  it('sin definir usa America/Mexico_City', () => {
    expect(loadConfig(base).TZ_SHIFTS).toBe('America/Mexico_City');
  });
});

describe('turnos en America/Tijuana en los cambios de horario (DST 2026)', () => {
  const TZ = 'America/Tijuana';
  const activo = (inicio: string, fin: string, iso: string) =>
    isShiftActive(inicio, fin, new Date(iso), TZ);

  it('primavera (8 de marzo): 08:00 locales es 16:00Z antes y 15:00Z después del cambio', () => {
    expect(activo('08:00', '16:00', '2026-03-07T15:59:00Z')).toBe(false); // 07:59 PST
    expect(activo('08:00', '16:00', '2026-03-07T16:00:00Z')).toBe(true); // 08:00 PST
    expect(activo('08:00', '16:00', '2026-03-08T14:59:00Z')).toBe(false); // 07:59 PDT
    expect(activo('08:00', '16:00', '2026-03-08T15:00:00Z')).toBe(true); // 08:00 PDT
    expect(activo('08:00', '16:00', '2026-03-08T22:59:00Z')).toBe(true); // 15:59 PDT
    expect(activo('08:00', '16:00', '2026-03-08T23:00:00Z')).toBe(false); // 16:00 PDT
  });

  it('otoño (1 de noviembre): 08:00 locales pasa a ser 16:00Z', () => {
    expect(activo('08:00', '16:00', '2026-11-01T15:00:00Z')).toBe(false); // 07:00 PST
    expect(activo('08:00', '16:00', '2026-11-01T15:59:00Z')).toBe(false); // 07:59 PST
    expect(activo('08:00', '16:00', '2026-11-01T16:00:00Z')).toBe(true); // 08:00 PST
    expect(activo('08:00', '16:00', '2026-10-31T15:00:00Z')).toBe(true); // 08:00 PDT
  });

  it('la hora local salta de 01:59 a 03:00 en primavera y repite la 01:00 en otoño', () => {
    expect(localMinutesOfDay(new Date('2026-03-08T09:59:00Z'), TZ)).toBe(119);
    expect(localMinutesOfDay(new Date('2026-03-08T10:00:00Z'), TZ)).toBe(180);
    expect(localMinutesOfDay(new Date('2026-11-01T08:59:00Z'), TZ)).toBe(119);
    expect(localMinutesOfDay(new Date('2026-11-01T09:00:00Z'), TZ)).toBe(60);
  });

  it('turno nocturno 22:00-06:00 se mantiene activo a través del cambio', () => {
    expect(activo('22:00', '06:00', '2026-03-08T09:59:00Z')).toBe(true); // 01:59 PST
    expect(activo('22:00', '06:00', '2026-03-08T10:00:00Z')).toBe(true); // 03:00 PDT
    expect(activo('22:00', '06:00', '2026-03-08T12:59:00Z')).toBe(true); // 05:59 PDT
    expect(activo('22:00', '06:00', '2026-03-08T13:00:00Z')).toBe(false); // 06:00 PDT
    expect(activo('22:00', '06:00', '2026-11-01T08:59:00Z')).toBe(true);
    expect(activo('22:00', '06:00', '2026-11-01T09:00:00Z')).toBe(true);
    expect(activo('22:00', '06:00', '2026-11-01T13:59:00Z')).toBe(true); // 05:59 PST
    expect(activo('22:00', '06:00', '2026-11-01T14:00:00Z')).toBe(false); // 06:00 PST
  });

  it('México (sin horario de verano) y Tijuana difieren el mismo instante en verano', () => {
    const t = new Date('2026-07-10T15:00:00Z'); // 09:00 en Tijuana (PDT), 09:00 en CDMX (UTC-6)
    expect(localMinutesOfDay(t, TZ)).toBe(8 * 60);
    expect(localMinutesOfDay(t, 'America/Mexico_City')).toBe(9 * 60);
  });
});

describe('policiesEqual con duplicados', () => {
  it('["admin","admin"] vs ["admin","guard"] -> false (en ambos sentidos)', () => {
    expect(policiesEqual([Role.admin, Role.admin], [Role.admin, Role.guard])).toBe(false);
    expect(policiesEqual([Role.admin, Role.guard], [Role.admin, Role.admin])).toBe(false);
  });

  it('mismo conjunto en otro orden -> true', () => {
    expect(policiesEqual([Role.admin, Role.guard], [Role.guard, Role.admin])).toBe(true);
    expect(
      policiesEqual(
        [Role.admin, Role.guard, Role.protected_user],
        [Role.protected_user, Role.admin, Role.guard],
      ),
    ).toBe(true);
  });

  it('["admin","admin"] vs ["admin"] no es equivalente (duplicados no cuentan como política válida)', () => {
    expect(policiesEqual([Role.admin, Role.admin], [Role.admin])).toBe(false);
  });
});
