// BE-04 paso 1 (unitarias): métricas del guardia (G-01, A-07) y vista del guardia de una alerta (D23).
// Los casos de métricas salen de lib/dominio/regla_metricas.dart (ReglaMetricas.deGuardia);
// las 20 claves de AlertaJson, de lib/datos/nube_mapeadores.dart:117-165.
import { describe, expect, it } from 'vitest';
import { guardMetrics, type MetricsAlert } from '../../src/domain/metrics.js';
import {
  serializeGuardAlert,
  serializeOwnAlert,
  type AlertRecord,
} from '../../src/modules/alerts/serializers.js';

// ── guardMetrics ───────────────────────────────────────────────────────

const G1 = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const G2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const T0 = Date.parse('2026-11-16T18:00:00.000Z');
const en = (ms: number): Date => new Date(T0 + ms);

function alerta(extra: Partial<MetricsAlert> = {}): MetricsAlert {
  return { guardId: G1, receivedAt: en(0), acceptedAt: null, arrivedAt: null, escalationReason: null, ...extra };
}

describe('guardMetrics (G-01, A-07)', () => {
  it('con cero alertas todo es 0 y no hay división entre cero', () => {
    const m = guardMetrics(G1, []);
    expect(m).toEqual({ attendedCount: 0, avgAcceptanceSeconds: 0, avgArrivalSeconds: 0, escalatedCount: 0 });
    expect(Number.isNaN(m.avgAcceptanceSeconds)).toBe(false);
    expect(Number.isNaN(m.avgArrivalSeconds)).toBe(false);
  });

  it('promedia aceptación y llegada y cuenta atendidas y escaladas', () => {
    const m = guardMetrics(G1, [
      alerta({ acceptedAt: en(10_000), arrivedAt: en(70_000) }),
      alerta({ acceptedAt: en(20_000), arrivedAt: en(140_000), escalationReason: 'no_confirmation' }),
      alerta({ escalationReason: 'no_response' }),
    ]);
    expect(m.attendedCount).toBe(2);
    expect(m.avgAcceptanceSeconds).toBe(15); // (10 + 20) / 2
    expect(m.avgArrivalSeconds).toBe(90); // (60 + 120) / 2
    expect(m.escalatedCount).toBe(2);
  });

  it('cada duración se trunca a segundos enteros ANTES de promediar (Duration.inSeconds)', () => {
    const m = guardMetrics(G1, [
      alerta({ acceptedAt: en(1_999) }), // 1 s
      alerta({ acceptedAt: en(2_999) }), // 2 s
    ]);
    // Sin truncar sería 2.4995; truncando cada una da (1 + 2) / 2.
    expect(m.avgAcceptanceSeconds).toBe(1.5);
  });

  it('una duración menor a un segundo cuenta como 0 y aun así entra en el promedio', () => {
    const m = guardMetrics(G1, [alerta({ acceptedAt: en(999) }), alerta({ acceptedAt: en(10_000) })]);
    expect(m.avgAcceptanceSeconds).toBe(5);
  });

  it('solo cuenta las alertas del guardId pedido (las de otro guardia y las sin asignar no suman)', () => {
    const m = guardMetrics(G1, [
      alerta({ acceptedAt: en(10_000), arrivedAt: en(20_000) }),
      alerta({ guardId: G2, acceptedAt: en(500_000), arrivedAt: en(900_000), escalationReason: 'no_response' }),
      alerta({ guardId: null, acceptedAt: en(500_000), arrivedAt: en(900_000) }),
    ]);
    expect(m).toEqual({ attendedCount: 1, avgAcceptanceSeconds: 10, avgArrivalSeconds: 10, escalatedCount: 0 });
  });

  it('acceptedAt nulo: no entra al promedio de aceptación y la llegada se mide desde receivedAt', () => {
    const m = guardMetrics(G1, [alerta({ acceptedAt: null, arrivedAt: en(45_000) })]);
    expect(m.avgAcceptanceSeconds).toBe(0);
    expect(m.avgArrivalSeconds).toBe(45);
    expect(m.attendedCount).toBe(1);
  });

  it('sin llegada no cuenta como atendida ni entra al promedio de llegada', () => {
    const m = guardMetrics(G1, [alerta({ acceptedAt: en(5_000) })]);
    expect(m.attendedCount).toBe(0);
    expect(m.avgArrivalSeconds).toBe(0);
    expect(m.avgAcceptanceSeconds).toBe(5);
  });

  it('escaladas: cuenta cualquier razón de escalamiento, con o sin llegada', () => {
    const m = guardMetrics(G1, [
      alerta({ escalationReason: 'no_response' }),
      alerta({ escalationReason: 'no_confirmation', acceptedAt: en(1_000), arrivedAt: en(2_000) }),
      alerta(),
    ]);
    expect(m.escalatedCount).toBe(2);
  });

  it('la forma son exactamente las 4 claves de MetricasGuardiaJson', () => {
    expect(Object.keys(guardMetrics(G1, [])).sort()).toEqual(
      ['attendedCount', 'avgAcceptanceSeconds', 'avgArrivalSeconds', 'escalatedCount'],
    );
  });
});

// ── serializeGuardAlert ────────────────────────────────────────────────

const MIO = '33333333-3333-4333-8333-333333333333';
const OTRO = '99999999-9999-4999-8999-999999999999';
const OPCIONES = {
  photoUrl: (_id: string, key: string | null) => (key ? `/foto/${key}` : null),
  guardMetersPerMinute: 250,
};

const CLAVES_ALERTA_JSON = [
  'acceptedAt', 'adminNote', 'arrivedAt', 'closedAt', 'escalationReason', 'etaSeconds', 'evidenceIncomplete',
  'guardId', 'guardName', 'heading', 'id', 'location', 'photoUrl', 'resolution', 'status', 'triggerMethod',
  'triggeredAt', 'userId', 'userName', 'userPhone',
].sort();

function registro(extra: Partial<AlertRecord> = {}): AlertRecord {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    userId: '22222222-2222-4222-8222-222222222222',
    guardId: MIO,
    status: 'in_progress',
    triggerMethod: 'shake',
    photoKey: '44444444-4444-4444-8444-444444444444',
    evidenceIncomplete: false,
    lat: 18.84,
    lng: -99.18,
    heading: 75,
    triggeredAt: new Date('2026-11-16T17:50:00.000Z'),
    acceptedAt: new Date('2026-11-16T17:51:10.000Z'),
    arrivedAt: null,
    closedAt: null,
    escalationReason: null,
    resolution: null,
    adminNote: null,
    user: { name: 'Fernanda Morales Gil', phone: '7771234567' },
    guard: { name: 'Carlos Hernández López', guardProfile: { lastLocationLat: 18.85, lastLocationLng: -99.18 } },
    ...extra,
  };
}

const ACTIVOS = ['pending_location', 'searching', 'in_progress', 'guard_arrived'] as const;
const NO_ACTIVOS = ['closed', 'no_response', 'escalated', 'resolved_by_admin'] as const;

describe('serializeGuardAlert: minimización de datos (D23)', () => {
  const casos: Array<[string, boolean, 'activo' | 'no activo', boolean, boolean]> = [];
  for (const asignado of [true, false]) {
    for (const [etiqueta, estados] of [['activo', ACTIVOS], ['no activo', NO_ACTIVOS]] as const) {
      for (const estado of estados) {
        const activo = etiqueta === 'activo';
        casos.push([estado, asignado, etiqueta, asignado && activo, activo]);
      }
    }
  }

  it.each(casos)(
    'estado %s, guardia asignado=%s (%s) -> teléfono visible=%s, ubicación visible=%s',
    (estado, asignado, _etiqueta, verTelefono, verUbicacion) => {
      const json = serializeGuardAlert(
        registro({ status: estado as AlertRecord['status'], guardId: asignado ? MIO : OTRO }),
        MIO,
        OPCIONES,
      );
      expect(json.userPhone).toBe(verTelefono ? '7771234567' : null);
      expect(json.location).toEqual(verUbicacion ? { lat: 18.84, lng: -99.18 } : null);
    },
  );

  it('searching sin guardia asignado: el guardia que la ve (disponible) no recibe el teléfono', () => {
    const json = serializeGuardAlert(registro({ status: 'searching', guardId: null, guard: null }), MIO, OPCIONES);
    expect(json.userPhone).toBeNull();
    expect(json.location).toEqual({ lat: 18.84, lng: -99.18 });
  });

  it('el teléfono tampoco sale a un guardia distinto cuando la alerta sigue activa', () => {
    const json = serializeGuardAlert(registro({ status: 'guard_arrived' }), OTRO, OPCIONES);
    expect(json.userPhone).toBeNull();
    expect(json.guardId).toBe(MIO);
  });

  it('la foto se conserva como evidencia aunque la alerta ya no esté activa', () => {
    const json = serializeGuardAlert(registro({ status: 'closed', closedAt: new Date() }), MIO, OPCIONES);
    expect(json.photoUrl).toBe('/foto/44444444-4444-4444-8444-444444444444');
    expect(json.location).toBeNull();
  });

  it('envía exactamente las 20 claves de AlertaJson del front en cualquier combinación', () => {
    for (const estado of [...ACTIVOS, ...NO_ACTIVOS]) {
      for (const visor of [MIO, OTRO]) {
        const json = serializeGuardAlert(registro({ status: estado }), visor, OPCIONES);
        expect(Object.keys(json).sort(), `${estado}/${visor}`).toEqual(CLAVES_ALERTA_JSON);
      }
    }
    // Mismas claves que la vista del dueño: el front usa un solo AlertaJson.
    expect(Object.keys(serializeOwnAlert(registro(), OPCIONES)).sort()).toEqual(CLAVES_ALERTA_JSON);
  });

  it('un campo con null va como null, no se omite la clave (evidencia incompleta, sin foto ni guardia)', () => {
    const json = serializeGuardAlert(
      registro({
        status: 'searching', guardId: null, guard: null, photoKey: null, evidenceIncomplete: true,
        heading: null, acceptedAt: null,
      }),
      MIO,
      OPCIONES,
    );
    expect(json).toMatchObject({
      guardId: null, guardName: null, photoUrl: null, evidenceIncomplete: true, heading: null,
      acceptedAt: null, arrivedAt: null, closedAt: null, escalationReason: null, resolution: null,
      adminNote: null, etaSeconds: null,
    });
  });

  it('nunca filtra campos internos (photoKey, lat, lng, receivedAt, user, guard)', () => {
    const json = serializeGuardAlert(
      { ...registro(), receivedAt: new Date(), statusChangedAt: new Date() } as AlertRecord,
      MIO,
      OPCIONES,
    ) as unknown as Record<string, unknown>;
    for (const interno of ['photoKey', 'lat', 'lng', 'receivedAt', 'statusChangedAt', 'user', 'guard', 'passwordHash']) {
      expect(json, interno).not.toHaveProperty(interno);
    }
  });

  it('fechas en ISO 8601 UTC', () => {
    const json = serializeGuardAlert(registro(), MIO, OPCIONES);
    expect(json.triggeredAt).toBe('2026-11-16T17:50:00.000Z');
    expect(json.acceptedAt).toBe('2026-11-16T17:51:10.000Z');
  });
});

describe('serializeGuardAlert: ETA (D27)', () => {
  it('etaSeconds es null si el guardia no tiene última ubicación', () => {
    for (const guardProfile of [
      null,
      { lastLocationLat: null, lastLocationLng: null },
      { lastLocationLat: 18.85, lastLocationLng: null },
    ]) {
      const json = serializeGuardAlert(
        registro({ guard: { name: 'Carlos', guardProfile } }),
        MIO,
        OPCIONES,
      );
      expect(json.etaSeconds).toBeNull();
    }
  });

  it('etaSeconds es null sin guardia asignado', () => {
    expect(serializeGuardAlert(registro({ guard: null }), MIO, OPCIONES).etaSeconds).toBeNull();
  });

  it('en in_progress se calcula con la ubicación real: ~1112 m a 250 m/min ≈ 267 s', () => {
    const json = serializeGuardAlert(registro(), MIO, OPCIONES);
    expect(json.etaSeconds).toBeGreaterThan(260);
    expect(json.etaSeconds).toBeLessThan(275);
  });

  it('el ETA no se pierde por ocultar la ubicación: se calcula antes de aplicar la minimización', () => {
    // in_progress está activo: se ve la ubicación y el ETA coincide con el de la vista del dueño.
    const guardia = serializeGuardAlert(registro(), MIO, OPCIONES);
    const dueno = serializeOwnAlert(registro(), OPCIONES);
    expect(guardia.etaSeconds).toBe(dueno.etaSeconds);
  });

  it('solo hay ETA en in_progress (D27): guard_arrived y los no activos dan null', () => {
    for (const estado of ['guard_arrived', 'closed', 'escalated'] as const) {
      expect(serializeGuardAlert(registro({ status: estado }), MIO, OPCIONES).etaSeconds, estado).toBeNull();
    }
  });

  it('con GUARD_METERS_PER_MINUTE no positivo el ETA es 0, nunca negativo ni NaN', () => {
    const json = serializeGuardAlert(registro(), MIO, { ...OPCIONES, guardMetersPerMinute: 0 });
    expect(json.etaSeconds).toBe(0);
  });
});
