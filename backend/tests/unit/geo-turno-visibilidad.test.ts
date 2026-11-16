// BE-01 paso 6: reglas puras de geografía, turno, visibilidad de alertas para el guardia (D22)
// y propiedad de recursos. Los casos salen de test/dominio/ del front (regla_geocerca, regla_turno).
import { describe, expect, it } from 'vitest';
import { haversineMeters, isWithinRadius, metersRemaining } from '../../src/domain/geo.js';
import {
  isAlertAvailableToGuard,
  isAlertVisibleToGuard,
  isAssignedTo,
  type VisibilityAlert,
  type VisibilityContext,
  type VisibilityGuard,
} from '../../src/domain/guard-visibility.js';
import {
  hhmmToMinutes,
  isShiftActive,
  isWithinShift,
  localMinutesOfDay,
} from '../../src/domain/shift.js';
import { AppError } from '../../src/errors/app-error.js';
import {
  GUARD_NOT_FOUND_MESSAGE,
  assertAssignedGuard,
  assertGuardCanSee,
  assertIsGuardTarget,
  assertOwnsAlert,
} from '../../src/security/ownership.js';

const ZOCALO = { lat: 19.4326, lng: -99.1332 };

describe('geo.ts', () => {
  it('distancia de un punto a sí mismo es 0', () => {
    expect(haversineMeters(ZOCALO, ZOCALO)).toBe(0);
  });

  it('1 grado de latitud ~ 111.19 km (radio terrestre 6 371 km)', () => {
    const d = haversineMeters({ lat: 0, lng: 0 }, { lat: 1, lng: 0 });
    expect(d).toBeCloseTo(111_194.9, 0);
  });

  it('1 grado de longitud en el ecuador ~ 111.19 km', () => {
    const d = haversineMeters({ lat: 0, lng: 0 }, { lat: 0, lng: 1 });
    expect(d).toBeCloseTo(111_194.9, 0);
  });

  it('Ciudad de México a Cuernavaca ~ 60 km (distancia conocida)', () => {
    const d = haversineMeters(ZOCALO, { lat: 18.9242, lng: -99.2216 });
    expect(d).toBeGreaterThan(55_000);
    expect(d).toBeLessThan(70_000);
  });

  it('es simétrica', () => {
    const a = { lat: 19.43, lng: -99.13 };
    const b = { lat: 19.5, lng: -99.2 };
    expect(haversineMeters(a, b)).toBeCloseTo(haversineMeters(b, a), 6);
  });

  it('puntos antipodales: media circunferencia, sin NaN', () => {
    const d = haversineMeters({ lat: 0, lng: 0 }, { lat: 0, lng: 180 });
    expect(Number.isNaN(d)).toBe(false);
    expect(d).toBeCloseTo(Math.PI * 6_371_000, 0);
  });

  it('isWithinRadius incluye el borde exacto y excluye un epsilon más allá', () => {
    const p = { lat: 19.4336, lng: -99.1332 };
    const d = haversineMeters(ZOCALO, p);
    expect(isWithinRadius(ZOCALO, d, p)).toBe(true);
    expect(isWithinRadius(ZOCALO, d - 1e-6, p)).toBe(false);
    expect(isWithinRadius(ZOCALO, d + 1, p)).toBe(true);
  });

  it('isWithinRadius: el propio centro con radio 0 está dentro', () => {
    expect(isWithinRadius(ZOCALO, 0, ZOCALO)).toBe(true);
  });

  it('metersRemaining nunca es negativo (0 si ya está dentro)', () => {
    const p = { lat: 19.4336, lng: -99.1332 };
    const d = haversineMeters(ZOCALO, p);
    expect(metersRemaining(ZOCALO, p, d + 500)).toBe(0);
    expect(metersRemaining(ZOCALO, p, d)).toBe(0);
    expect(metersRemaining(ZOCALO, ZOCALO, 50)).toBe(0);
  });

  it('metersRemaining = distancia - radio cuando está fuera', () => {
    const p = { lat: 19.4336, lng: -99.1332 };
    const d = haversineMeters(ZOCALO, p);
    expect(metersRemaining(ZOCALO, p, 50)).toBeCloseTo(d - 50, 6);
    expect(metersRemaining(ZOCALO, p, 50)).toBeGreaterThan(0);
  });
});

describe('shift.ts', () => {
  it('hhmmToMinutes convierte HH:mm', () => {
    expect(hhmmToMinutes('00:00')).toBe(0);
    expect(hhmmToMinutes('08:30')).toBe(510);
    expect(hhmmToMinutes('23:59')).toBe(1439);
  });

  it.each(['24:00', '8:00', '08:60', '0800', '', 'ab:cd', '08:00:00', ' 08:00'])(
    'hhmmToMinutes rechaza "%s"',
    (v) => {
      expect(() => hhmmToMinutes(v)).toThrow(RangeError);
    },
  );

  describe('08:00 - 16:00 (mismo día)', () => {
    const dentro = (hhmm: string) => isWithinShift('08:00', '16:00', hhmmToMinutes(hhmm));
    it('incluye el inicio', () => expect(dentro('08:00')).toBe(true));
    it('excluye el fin', () => expect(dentro('16:00')).toBe(false));
    it('un minuto antes del fin está dentro', () => expect(dentro('15:59')).toBe(true));
    it('un minuto antes del inicio está fuera', () => expect(dentro('07:59')).toBe(false));
    it('medianoche está fuera', () => expect(dentro('00:00')).toBe(false));
  });

  describe('22:00 - 06:00 (cruza medianoche)', () => {
    const dentro = (hhmm: string) => isWithinShift('22:00', '06:00', hhmmToMinutes(hhmm));
    it('incluye el inicio', () => expect(dentro('22:00')).toBe(true));
    it('23:59 y 00:00 están dentro', () => {
      expect(dentro('23:59')).toBe(true);
      expect(dentro('00:00')).toBe(true);
    });
    it('05:59 dentro; 06:00 (fin) fuera', () => {
      expect(dentro('05:59')).toBe(true);
      expect(dentro('06:00')).toBe(false);
    });
    it('21:59 y mediodía están fuera', () => {
      expect(dentro('21:59')).toBe(false);
      expect(dentro('12:00')).toBe(false);
    });
  });

  it('inicio == fin es un turno de 24 horas', () => {
    for (const m of [0, 1, 479, 480, 1439]) expect(isWithinShift('08:00', '08:00', m)).toBe(true);
    expect(isWithinShift('00:00', '00:00', 700)).toBe(true);
  });

  describe('localMinutesOfDay / isShiftActive en America/Mexico_City (UTC-6 todo el año)', () => {
    const TZ = 'America/Mexico_City';
    it('14:00Z = 08:00 locales', () => {
      expect(localMinutesOfDay(new Date('2026-03-10T14:00:00Z'), TZ)).toBe(480);
    });
    it('06:00Z = 00:00 locales (h23, no 24:00)', () => {
      expect(localMinutesOfDay(new Date('2026-07-10T06:00:00Z'), TZ)).toBe(0);
    });
    it('05:59Z = 23:59 locales del día anterior', () => {
      expect(localMinutesOfDay(new Date('2026-07-10T05:59:00Z'), TZ)).toBe(1439);
    });
    it('turno 08:00-16:00: 14:00Z activo, 13:59Z no, 21:59Z activo, 22:00Z no', () => {
      const act = (iso: string) => isShiftActive('08:00', '16:00', new Date(iso), TZ);
      expect(act('2026-03-10T14:00:00Z')).toBe(true);
      expect(act('2026-03-10T13:59:00Z')).toBe(false);
      expect(act('2026-03-10T21:59:00Z')).toBe(true);
      expect(act('2026-03-10T22:00:00Z')).toBe(false);
    });
    it('turno 22:00-06:00 cruza medianoche en hora local', () => {
      const act = (iso: string) => isShiftActive('22:00', '06:00', new Date(iso), TZ);
      expect(act('2026-03-11T04:00:00Z')).toBe(true); // 22:00 local
      expect(act('2026-03-11T03:59:00Z')).toBe(false); // 21:59 local
      expect(act('2026-03-11T06:00:00Z')).toBe(true); // 00:00 local
      expect(act('2026-03-11T11:59:00Z')).toBe(true); // 05:59 local
      expect(act('2026-03-11T12:00:00Z')).toBe(false); // 06:00 local
    });
    it('la zona horaria cambia el resultado (UTC vs México)', () => {
      const t = new Date('2026-03-10T10:00:00Z');
      expect(isShiftActive('08:00', '16:00', t, 'UTC')).toBe(true);
      expect(isShiftActive('08:00', '16:00', t, TZ)).toBe(false);
    });
  });
});

// --- visibilidad y propiedad -------------------------------------------------

const TZ = 'America/Mexico_City';
const AHORA = new Date('2026-03-10T18:00:00Z'); // 12:00 locales
const CENTRO = { lat: 19.4326, lng: -99.1332 };
const DENTRO = { lat: 19.433, lng: -99.1332 }; // ~44 m
const LEJOS = { lat: 19.5, lng: -99.1332 };

const guardia = (extra: Partial<VisibilityGuard> = {}): VisibilityGuard => ({
  id: 'g-1',
  active: true,
  shiftStart: '08:00',
  shiftEnd: '16:00',
  coverage: { center: CENTRO, radiusMeters: 1000 },
  ...extra,
});
const alerta = (extra: Partial<VisibilityAlert> = {}): VisibilityAlert => ({
  guardId: null,
  status: 'searching',
  location: DENTRO,
  ...extra,
});
const ctx = (extra: Partial<VisibilityContext> = {}): VisibilityContext => ({
  now: AHORA,
  timeZone: TZ,
  ignoredByGuard: false,
  ...extra,
});

function lanzado(fn: () => void): AppError {
  try {
    fn();
  } catch (e) {
    expect(e).toBeInstanceOf(AppError);
    return e as AppError;
  }
  throw new Error('La función no lanzó');
}

describe('guard-visibility.ts', () => {
  it('disponible: searching, dentro de cobertura, turno vigente, no ignorada', () => {
    expect(isAlertAvailableToGuard(alerta(), guardia(), ctx())).toBe(true);
    expect(isAlertVisibleToGuard(alerta(), guardia(), ctx())).toBe(true);
  });

  it('isAssignedTo compara con guardId y null nunca coincide', () => {
    expect(isAssignedTo({ guardId: 'g-1' }, 'g-1')).toBe(true);
    expect(isAssignedTo({ guardId: 'g-2' }, 'g-1')).toBe(false);
    expect(isAssignedTo({ guardId: null }, 'null')).toBe(false);
  });

  it('asignada al guardia es visible aunque no esté searching, esté inactivo o sin cobertura', () => {
    const a = alerta({ guardId: 'g-1', status: 'in_progress', location: LEJOS });
    const g = guardia({ active: false, coverage: null });
    expect(isAlertVisibleToGuard(a, g, ctx({ ignoredByGuard: true }))).toBe(true);
  });

  it('asignada a OTRO guardia no es visible', () => {
    const a = alerta({ guardId: 'g-2', status: 'in_progress' });
    expect(isAlertVisibleToGuard(a, guardia(), ctx())).toBe(false);
  });

  it.each([
    ['guardia inactivo', alerta(), guardia({ active: false }), ctx()],
    ['sin cobertura', alerta(), guardia({ coverage: null }), ctx()],
    ['alerta sin ubicación', alerta({ location: null }), guardia(), ctx()],
    ['fuera de cobertura', alerta({ location: LEJOS }), guardia(), ctx()],
    ['ignorada', alerta(), guardia(), ctx({ ignoredByGuard: true })],
    ['fuera de turno', alerta(), guardia({ shiftStart: '16:00', shiftEnd: '20:00' }), ctx()],
    ['no searching', alerta({ status: 'in_progress' }), guardia(), ctx()],
    ['pending_location', alerta({ status: 'pending_location' }), guardia(), ctx()],
  ] as const)('no disponible: %s', (_n, a, g, c) => {
    expect(isAlertAvailableToGuard(a, g, c)).toBe(false);
    expect(isAlertVisibleToGuard(a, g, c)).toBe(false);
  });

  it('skipStatusCheck hace disponible una alerta in_progress (accept responde 409 después)', () => {
    const a = alerta({ status: 'in_progress' });
    expect(isAlertAvailableToGuard(a, guardia(), ctx({ skipStatusCheck: true }))).toBe(true);
  });

  it('skipStatusCheck NO salta el resto de condiciones', () => {
    const c = ctx({ skipStatusCheck: true });
    const a = alerta({ status: 'closed' });
    expect(isAlertAvailableToGuard(a, guardia({ active: false }), c)).toBe(false);
    expect(isAlertAvailableToGuard(a, guardia({ coverage: null }), c)).toBe(false);
    expect(isAlertAvailableToGuard({ ...a, location: LEJOS }, guardia(), c)).toBe(false);
    expect(isAlertAvailableToGuard({ ...a, location: null }, guardia(), c)).toBe(false);
    expect(isAlertAvailableToGuard(a, guardia(), { ...c, ignoredByGuard: true })).toBe(false);
    expect(
      isAlertAvailableToGuard(a, guardia({ shiftStart: '16:00', shiftEnd: '20:00' }), c),
    ).toBe(false);
  });

  it('turno que cruza medianoche usa la hora local', () => {
    const g = guardia({ shiftStart: '22:00', shiftEnd: '06:00' });
    const noche = ctx({ now: new Date('2026-03-11T04:30:00Z') }); // 22:30 local
    expect(isAlertAvailableToGuard(alerta(), g, noche)).toBe(true);
    expect(isAlertAvailableToGuard(alerta(), g, ctx())).toBe(false); // 12:00 local
  });

  it('cobertura: el borde del radio cuenta como dentro', () => {
    const d = haversineMeters(CENTRO, DENTRO);
    const g = guardia({ coverage: { center: CENTRO, radiusMeters: d } });
    expect(isAlertAvailableToGuard(alerta(), g, ctx())).toBe(true);
    const g2 = guardia({ coverage: { center: CENTRO, radiusMeters: d - 0.001 } });
    expect(isAlertAvailableToGuard(alerta(), g2, ctx())).toBe(false);
  });
});

describe('ownership.ts - todos los negativos lanzan NOT_FOUND (nunca FORBIDDEN)', () => {
  const usuario = { id: 'u-1' };

  describe('assertOwnsAlert', () => {
    it('propia: no lanza', () => {
      expect(() => assertOwnsAlert({ userId: 'u-1' }, usuario)).not.toThrow();
    });
    it.each([
      ['alerta ajena', { userId: 'u-2' }],
      ['null', null],
      ['undefined', undefined],
    ] as const)('%s -> NOT_FOUND 404', (_n, a) => {
      const e = lanzado(() => assertOwnsAlert(a, usuario));
      expect(e.code).toBe('NOT_FOUND');
      expect(e.httpStatus).toBe(404);
    });
  });

  describe('assertAssignedGuard', () => {
    it('asignado: no lanza', () => {
      expect(() => assertAssignedGuard({ guardId: 'g-1' }, { id: 'g-1' })).not.toThrow();
    });
    it.each([
      ['asignada a otro', { guardId: 'g-2' }],
      ['sin asignar', { guardId: null }],
      ['null', null],
    ] as const)('%s -> NOT_FOUND', (_n, a) => {
      const e = lanzado(() => assertAssignedGuard(a, { id: 'g-1' }));
      expect(e.code).toBe('NOT_FOUND');
      expect(e.httpStatus).toBe(404);
    });
  });

  describe('assertGuardCanSee', () => {
    it('asignada o disponible: no lanza', () => {
      expect(() => assertGuardCanSee(alerta(), guardia(), ctx())).not.toThrow();
      expect(() =>
        assertGuardCanSee(alerta({ guardId: 'g-1', status: 'in_progress' }), guardia(), ctx()),
      ).not.toThrow();
    });
    it('con skipStatusCheck una alerta in_progress sin asignar sigue siendo visible', () => {
      expect(() =>
        assertGuardCanSee(
          alerta({ status: 'in_progress' }),
          guardia(),
          ctx({ skipStatusCheck: true }),
        ),
      ).not.toThrow();
    });
    it.each([
      ['null', null, guardia(), ctx()],
      ['asignada a otro', alerta({ guardId: 'g-2', status: 'in_progress' }), guardia(), ctx()],
      ['fuera de cobertura', alerta({ location: LEJOS }), guardia(), ctx()],
      ['fuera de turno', alerta(), guardia({ shiftStart: '16:00', shiftEnd: '20:00' }), ctx()],
      ['ignorada', alerta(), guardia(), ctx({ ignoredByGuard: true })],
      ['guardia inactivo', alerta(), guardia({ active: false }), ctx()],
      ['sin cobertura', alerta(), guardia({ coverage: null }), ctx()],
      ['alerta sin ubicación', alerta({ location: null }), guardia(), ctx()],
      ['no searching sin skipStatusCheck', alerta({ status: 'in_progress' }), guardia(), ctx()],
    ] as const)('%s -> NOT_FOUND', (_n, a, g, c) => {
      const e = lanzado(() => assertGuardCanSee(a, g, c));
      expect(e.code).toBe('NOT_FOUND');
      expect(e.httpStatus).toBe(404);
    });
  });

  describe('assertIsGuardTarget', () => {
    it('rol guard: no lanza', () => {
      expect(() => assertIsGuardTarget({ role: 'guard' })).not.toThrow();
    });
    it.each([
      ['protected_user', { role: 'protected_user' as const }],
      ['admin', { role: 'admin' as const }],
      ['null', null],
      ['undefined', undefined],
    ] as const)('%s -> NOT_FOUND "No encontramos a ese guardia"', (_n, t) => {
      const e = lanzado(() => assertIsGuardTarget(t));
      expect(e.code).toBe('NOT_FOUND');
      expect(e.httpStatus).toBe(404);
      expect(e.message).toBe('No encontramos a ese guardia');
      expect(GUARD_NOT_FOUND_MESSAGE).toBe('No encontramos a ese guardia');
    });
  });
});
