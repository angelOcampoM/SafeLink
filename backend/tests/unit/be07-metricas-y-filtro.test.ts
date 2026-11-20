// BE-07 · Métricas generales (A-06), hora de pared de los turnos y validación del filtro de
// historial (A-05). Unitaria: no toca la base.
//
// Las dos reglas que esta prueba fija y que son fáciles de romper sin darse cuenta:
//  1. `alertsByHour` agrupa por la hora de TZ_SHIFTS, no por la del servidor (en CI es UTC).
//  2. Una fecha del filtro sin zona es hora de pared de TZ_SHIFTS, porque así la manda el
//     front (`DateTime.toIso8601String()` sobre una fecha local, contrato 4.8).
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import {
  ZONA_SIN_ASIGNAR,
  generalMetrics,
  guardMetrics,
  type GeneralMetricsAlert,
} from '../../src/domain/metrics.js';
import { hourInZone, wallClockToUtc, zoneOffsetMinutes } from '../../src/domain/timezone.js';
import { describeZodError } from '../../src/http/validate.js';
import { historyQuerySchema, periodQuerySchema } from '../../src/modules/admin/schemas.js';

const TZ = 'America/Mexico_City';
const GUARDIA = 'g-1';

/** Alerta mínima; cada prueba cambia solo lo que mide. */
function alerta(extra: Partial<GeneralMetricsAlert> = {}): GeneralMetricsAlert {
  return {
    guardId: GUARDIA,
    status: 'closed',
    receivedAt: new Date('2026-03-10T18:00:00Z'),
    acceptedAt: null,
    arrivedAt: null,
    escalationReason: null,
    zone: 'Emiliano Zapata',
    ...extra,
  };
}

// ── A-06 · Métricas generales ─────────────────────────────────────────

describe('generalMetrics con cero alertas', () => {
  const m = generalMetrics([], TZ);

  it('todo vale 0 y no divide entre 0', () => {
    expect(m.totalAlerts).toBe(0);
    expect(m.avgAcceptanceSeconds).toBe(0);
    expect(m.avgArrivalSeconds).toBe(0);
    expect(m.noResponseRate).toBe(0);
    expect(m.confirmedCloseRate).toBe(0);
  });

  it('alertsByHour sigue siendo 24 ceros y alertsByZone va vacío (contrato 4.6)', () => {
    expect(m.alertsByHour).toHaveLength(24);
    expect(m.alertsByHour.every((n) => n === 0)).toBe(true);
    expect(m.alertsByZone).toEqual([]);
  });
});

describe('generalMetrics · promedios', () => {
  it('avgAcceptanceSeconds promedia solo las alertas con acceptedAt', () => {
    const m = generalMetrics(
      [
        alerta({
          receivedAt: new Date('2026-03-10T18:00:00Z'),
          acceptedAt: new Date('2026-03-10T18:00:30Z'),
        }),
        alerta({
          receivedAt: new Date('2026-03-10T19:00:00Z'),
          acceptedAt: new Date('2026-03-10T19:01:30Z'),
        }),
        alerta({ acceptedAt: null }), // no entra al promedio
      ],
      TZ,
    );
    expect(m.totalAlerts).toBe(3);
    expect(m.avgAcceptanceSeconds).toBe(60); // (30 + 90) / 2
  });

  it('avgArrivalSeconds cuenta desde acceptedAt y, si no hay, desde receivedAt', () => {
    const m = generalMetrics(
      [
        alerta({
          receivedAt: new Date('2026-03-10T18:00:00Z'),
          acceptedAt: new Date('2026-03-10T18:01:00Z'),
          arrivedAt: new Date('2026-03-10T18:05:00Z'), // 240 s desde que aceptó
        }),
        alerta({
          receivedAt: new Date('2026-03-10T19:00:00Z'),
          acceptedAt: null,
          arrivedAt: new Date('2026-03-10T19:02:00Z'), // 120 s desde que llegó la alerta
        }),
      ],
      TZ,
    );
    expect(m.avgArrivalSeconds).toBe(180);
  });

  it('las duraciones se truncan a segundos enteros por alerta, como Duration.inSeconds', () => {
    const m = generalMetrics(
      [
        alerta({
          receivedAt: new Date('2026-03-10T18:00:00.000Z'),
          acceptedAt: new Date('2026-03-10T18:00:10.900Z'),
        }),
      ],
      TZ,
    );
    expect(m.avgAcceptanceSeconds).toBe(10);
  });
});

describe('generalMetrics · proporciones', () => {
  it('noResponseRate solo cuenta escalationReason = no_response', () => {
    const m = generalMetrics(
      [
        alerta({ escalationReason: 'no_response' }),
        alerta({ escalationReason: 'no_confirmation' }),
        alerta({ escalationReason: null }),
        alerta({ escalationReason: null }),
      ],
      TZ,
    );
    expect(m.noResponseRate).toBe(0.25);
  });

  it('confirmedCloseRate solo cuenta status = closed', () => {
    const m = generalMetrics(
      [
        alerta({ status: 'closed' }),
        alerta({ status: 'closed' }),
        alerta({ status: 'resolved_by_admin' }),
        alerta({ status: 'escalated' }),
      ],
      TZ,
    );
    expect(m.confirmedCloseRate).toBe(0.5);
  });
});

describe('generalMetrics · alertsByHour', () => {
  it('agrupa por la hora de TZ_SHIFTS, no por la del servidor', () => {
    // 02:00 UTC del 15 de enero son las 20:00 del día 14 en Ciudad de México (UTC-6).
    const m = generalMetrics([alerta({ receivedAt: new Date('2026-01-15T02:00:00Z') })], TZ);
    expect(m.alertsByHour[20]).toBe(1);
    expect(m.alertsByHour[2]).toBe(0);
    expect(m.alertsByHour.reduce((a, b) => a + b, 0)).toBe(1);
  });

  it('la misma alerta en UTC cae en la hora 2: la zona es lo que decide', () => {
    const m = generalMetrics([alerta({ receivedAt: new Date('2026-01-15T02:00:00Z') })], 'UTC');
    expect(m.alertsByHour[2]).toBe(1);
  });
});

describe('generalMetrics · alertsByZone', () => {
  it('sin guardia o sin zona, la alerta cuenta en "Sin zona asignada"', () => {
    const m = generalMetrics(
      [alerta({ guardId: null, zone: null }), alerta({ zone: null })],
      TZ,
    );
    expect(m.alertsByZone).toEqual([{ zone: ZONA_SIN_ASIGNAR, count: 2 }]);
  });

  it('ordena por más alertas primero y, a igualdad, por nombre de zona', () => {
    const m = generalMetrics(
      [
        alerta({ zone: 'Zapata' }),
        alerta({ zone: 'Acapantzingo' }),
        alerta({ zone: 'Lomas' }),
        alerta({ zone: 'Lomas' }),
      ],
      TZ,
    );
    expect(m.alertsByZone).toEqual([
      { zone: 'Lomas', count: 2 },
      { zone: 'Acapantzingo', count: 1 },
      { zone: 'Zapata', count: 1 },
    ]);
  });
});

// ── A-07 · Métricas por guardia (ya existían; aquí se fija que el filtro no las cambia) ──

describe('guardMetrics', () => {
  it('ignora las alertas de otros guardias aunque vengan en la lista', () => {
    const m = guardMetrics(GUARDIA, [
      alerta({ arrivedAt: new Date('2026-03-10T18:05:00Z') }),
      alerta({ guardId: 'otro', arrivedAt: new Date('2026-03-10T18:05:00Z') }),
      alerta({ guardId: null }),
    ]);
    expect(m.attendedCount).toBe(1);
  });
});

// ── Hora de pared de los turnos ───────────────────────────────────────

describe('timezone', () => {
  it('hourInZone da la hora de pared de la zona', () => {
    expect(hourInZone(new Date('2026-01-15T02:00:00Z'), TZ)).toBe(20);
    expect(hourInZone(new Date('2026-01-15T02:00:00Z'), 'UTC')).toBe(2);
  });

  it('zoneOffsetMinutes: Ciudad de México es UTC-6 todo el año (sin horario de verano desde 2022)', () => {
    expect(zoneOffsetMinutes(TZ, new Date('2026-01-15T12:00:00Z'))).toBe(-360);
    expect(zoneOffsetMinutes(TZ, new Date('2026-07-15T12:00:00Z'))).toBe(-360);
  });

  it('una fecha sin zona se lee como hora de pared de la zona', () => {
    // Medianoche del 19 de noviembre en Cuernavaca son las 06:00 UTC.
    expect(wallClockToUtc('2026-11-19T00:00:00.000', TZ).toISOString()).toBe(
      '2026-11-19T06:00:00.000Z',
    );
  });

  it('en una zona con horario de verano usa el desplazamiento de esa fecha, no uno fijo', () => {
    const NY = 'America/New_York';
    expect(wallClockToUtc('2026-01-15T00:00:00', NY).toISOString()).toBe(
      '2026-01-15T05:00:00.000Z', // invierno: UTC-5
    );
    expect(wallClockToUtc('2026-07-15T00:00:00', NY).toISOString()).toBe(
      '2026-07-15T04:00:00.000Z', // verano: UTC-4
    );
  });
});

// ── A-05 · Validación del filtro de historial (contrato 4.8) ──────────

/** Mensaje en español que vería la app, o null si la query es válida. */
function error(schema: z.ZodType, query: unknown): string | null {
  const r = schema.safeParse(query);
  return r.success ? null : describeZodError(r.error, query);
}

describe('historyQuerySchema', () => {
  it('una query vacía es válida: todos los filtros son opcionales', () => {
    expect(error(historyQuerySchema, {})).toBeNull();
  });

  it('acepta la fecha tal como la manda el front, sin zona', () => {
    expect(error(historyQuerySchema, { from: '2026-11-19T00:00:00.000' })).toBeNull();
  });

  it('acepta también una fecha con zona explícita', () => {
    expect(error(historyQuerySchema, { to: '2026-11-20T00:00:00Z' })).toBeNull();
    expect(error(historyQuerySchema, { to: '2026-11-20T00:00:00-06:00' })).toBeNull();
  });

  it.each([
    ['2026-13-01T00:00:00', 'mes 13'],
    ['2026-02-31T00:00:00', '31 de febrero'],
    ['19/11/2026', 'formato del día a día'],
    ['2026-11-19', 'solo la fecha, sin hora'],
    ['ayer', 'texto libre'],
  ])('rechaza %s (%s)', (valor) => {
    expect(error(historyQuerySchema, { from: valor })).toBe('La fecha no es válida');
  });

  it('un estado desconocido es error de validación (400), no una lista vacía', () => {
    expect(error(historyQuerySchema, { status: 'inventado' })).toBe('El estado no es válido');
  });

  it('acepta los estados del modelo', () => {
    for (const status of ['searching', 'closed', 'escalated', 'resolved_by_admin']) {
      expect(error(historyQuerySchema, { status })).toBeNull();
    }
  });

  it('guardId y userId tienen que ser ids válidos', () => {
    expect(error(historyQuerySchema, { guardId: 'abc' })).toBe('El guardia no es válido');
    expect(error(historyQuerySchema, { userId: 'abc' })).toBe('El usuario no es válido');
  });

  it('un parámetro que no existe se rechaza en lugar de ignorarse en silencio', () => {
    expect(error(historyQuerySchema, { limit: '10' })).toBe('Campos no permitidos: limit');
  });
});

describe('periodQuerySchema', () => {
  it('solo acepta from y to: los filtros del historial no aplican a las métricas', () => {
    expect(error(periodQuerySchema, { from: '2026-11-01T00:00:00' })).toBeNull();
    expect(error(periodQuerySchema, { status: 'closed' })).toBe('Campos no permitidos: status');
  });
});
