// BE-03 · Reglas, validación y forma JSON de las alertas del usuario protegido.
// Unitaria: no toca la base. Cubre U-03 a U-09 del lado del servidor.
import { describe, expect, it } from 'vitest';
import {
  ACTIVE_STATUSES,
  canUserConfirm,
  clampTriggeredAt,
  etaSeconds,
  initialStatus,
  isActiveStatus,
  isBlocked,
  statusAfterLocation,
} from '../../src/domain/alert-rules.js';
import { describeZodError } from '../../src/http/validate.js';
import { createAlertBodySchema, locationBodySchema } from '../../src/modules/alerts/schemas.js';
import { serializeOwnAlert, type AlertRecord } from '../../src/modules/alerts/serializers.js';

const AHORA = new Date('2026-11-16T18:00:00.000Z');

/** Mensaje en español que vería la app, o null si el cuerpo es válido. */
function error(schema: typeof createAlertBodySchema | typeof locationBodySchema, body: unknown): string | null {
  const r = schema.safeParse(body);
  return r.success ? null : describeZodError(r.error, body);
}

const CUERPO = {
  triggerMethod: 'tap',
  triggeredAt: '2026-11-16T17:59:58.123Z',
  location: { lat: 18.84, lng: -99.18 },
  heading: 35,
  photoPath: '/data/user/0/mx.safelink/cache/foto.jpg',
};

// ── Reglas ─────────────────────────────────────────────────────────────

describe('alert-rules', () => {
  it('los activos son los cuatro de enums.dart (D15)', () => {
    expect([...ACTIVE_STATUSES].sort()).toEqual(['guard_arrived', 'in_progress', 'pending_location', 'searching']);
    for (const s of ['closed', 'no_response', 'escalated', 'resolved_by_admin'] as const) {
      expect(isActiveStatus(s)).toBe(false);
    }
  });

  it('U-06: sin coordenadas la alerta nace pendiente de ubicación; con ellas, buscando guardia', () => {
    expect(initialStatus(null)).toBe('pending_location');
    expect(initialStatus({ lat: 18.84, lng: -99.18 })).toBe('searching');
  });

  it('A-08: el bloqueo cuenta solo mientras está vigente', () => {
    expect(isBlocked(null, AHORA)).toBe(false);
    expect(isBlocked(new Date('2026-11-20T00:00:00Z'), AHORA)).toBe(true);
    expect(isBlocked(new Date('2026-11-10T00:00:00Z'), AHORA)).toBe(false);
    expect(isBlocked(AHORA, AHORA)).toBe(false);
  });

  it('D24: triggeredAt se respeta dentro de la tolerancia y se recorta fuera de ella', () => {
    const cerca = new Date(AHORA.getTime() - 599_000);
    expect(clampTriggeredAt(cerca, AHORA, 600)).toBe(cerca);
    const futuro = new Date(AHORA.getTime() + 600_000);
    expect(clampTriggeredAt(futuro, AHORA, 600)).toBe(futuro);
    expect(clampTriggeredAt(new Date(AHORA.getTime() - 601_000), AHORA, 600)).toBe(AHORA);
    expect(clampTriggeredAt(new Date('2020-01-01T00:00:00Z'), AHORA, 600)).toBe(AHORA);
  });

  it('U-09: solo se confirma con el guardia en el lugar y asignado', () => {
    expect(canUserConfirm({ status: 'guard_arrived', guardId: 'g' })).toBe(true);
    expect(canUserConfirm({ status: 'guard_arrived', guardId: null })).toBe(false);
    for (const s of ['pending_location', 'searching', 'in_progress', 'closed', 'escalated'] as const) {
      expect(canUserConfirm({ status: s, guardId: 'g' })).toBe(false);
    }
  });

  it('U-07: la primera ubicación publica la alerta; las siguientes no cambian el estado', () => {
    expect(statusAfterLocation('pending_location')).toBe('searching');
    for (const s of ['searching', 'in_progress', 'guard_arrived'] as const) {
      expect(statusAfterLocation(s)).toBe(s);
    }
  });

  it('U-08: el ETA solo existe en atención, con las dos ubicaciones, y baja al acercarse', () => {
    const alerta = { lat: 18.84, lng: -99.18 };
    const lejos = { lat: 18.85, lng: -99.18 }; // ~1.1 km
    const cerca = { lat: 18.841, lng: -99.18 }; // ~111 m
    expect(etaSeconds('searching', lejos, alerta, 250)).toBeNull();
    expect(etaSeconds('in_progress', null, alerta, 250)).toBeNull();
    expect(etaSeconds('in_progress', lejos, null, 250)).toBeNull();
    const etaLejos = etaSeconds('in_progress', lejos, alerta, 250);
    const etaCerca = etaSeconds('in_progress', cerca, alerta, 250);
    expect(Number.isInteger(etaLejos)).toBe(true);
    expect(etaLejos).toBeGreaterThan(etaCerca ?? Infinity);
    expect(etaSeconds('in_progress', alerta, alerta, 250)).toBe(0);
    expect(etaSeconds('in_progress', lejos, alerta, 0)).toBe(0);
  });
});

// ── Validación de entrada ──────────────────────────────────────────────

describe('POST /alerts · cuerpo', () => {
  it('acepta exactamente lo que manda nube_alerta_usuario_repository.dart', () => {
    const r = createAlertBodySchema.safeParse(CUERPO);
    expect(r.success).toBe(true);
  });

  it('acepta los tres métodos de la API: shake es el doble clic de volumen', () => {
    for (const triggerMethod of ['tap', 'hold', 'shake']) {
      expect(error(createAlertBodySchema, { ...CUERPO, triggerMethod })).toBeNull();
    }
    expect(error(createAlertBodySchema, { ...CUERPO, triggerMethod: 'volume' })).toBe(
      'El método de disparo no es válido',
    );
  });

  it('U-06: ubicación, rumbo y foto pueden ir en null (o faltar)', () => {
    const r = createAlertBodySchema.safeParse({ ...CUERPO, location: null, heading: null, photoPath: null });
    expect(r.success).toBe(true);
    const sinClaves = createAlertBodySchema.safeParse({ triggerMethod: 'hold', triggeredAt: CUERPO.triggeredAt });
    expect(sinClaves.success).toBe(true);
    if (sinClaves.success) {
      expect(sinClaves.data.location).toBeNull();
      expect(sinClaves.data.heading).toBeNull();
      expect(sinClaves.data.photoPath).toBeNull();
    }
  });

  it('exige una hora ISO válida', () => {
    expect(error(createAlertBodySchema, { ...CUERPO, triggeredAt: 'ayer' })).toBe('La hora del disparo no es válida');
    expect(error(createAlertBodySchema, { ...CUERPO, triggeredAt: '2026-11-16T12:00:00-06:00' })).toBeNull();
  });

  it('rechaza coordenadas fuera de rango o no numéricas', () => {
    for (const location of [{ lat: 91, lng: 0 }, { lat: 0, lng: -181 }, { lat: '18', lng: 0 }]) {
      expect(error(createAlertBodySchema, { ...CUERPO, location })).toBe('La ubicación no es válida');
    }
    expect(error(createAlertBodySchema, { ...CUERPO, location: { lat: 1, lng: 2, alt: 3 } })).not.toBeNull();
  });

  it('el rumbo es entero de 0 a 359', () => {
    for (const heading of [-1, 360, 12.5]) {
      expect(error(createAlertBodySchema, { ...CUERPO, heading })).toBe('El rumbo no es válido');
    }
    expect(error(createAlertBodySchema, { ...CUERPO, heading: 0 })).toBeNull();
    expect(error(createAlertBodySchema, { ...CUERPO, heading: 359 })).toBeNull();
  });

  it('no deja colar campos que decide el servidor', () => {
    for (const extra of [{ status: 'closed' }, { userId: 'otro' }, { evidenceIncomplete: false }, { photoKey: 'x' }]) {
      expect(error(createAlertBodySchema, { ...CUERPO, ...extra })).toMatch(/^Campos no permitidos/);
    }
  });

  it('photoPath tiene un largo máximo', () => {
    expect(error(createAlertBodySchema, { ...CUERPO, photoPath: 'a'.repeat(501) })).toBe(
      'La ruta de la foto es demasiado larga',
    );
  });
});

describe('POST /alerts/:id/locations · cuerpo', () => {
  it('pide una ubicación válida', () => {
    expect(error(locationBodySchema, { location: { lat: 18.84, lng: -99.18 } })).toBeNull();
    expect(error(locationBodySchema, {})).toBe('El campo location es obligatorio');
    expect(error(locationBodySchema, { location: null })).not.toBeNull();
  });
});

// ── Forma JSON ─────────────────────────────────────────────────────────

const REGISTRO: AlertRecord = {
  id: '11111111-1111-4111-8111-111111111111',
  userId: '22222222-2222-4222-8222-222222222222',
  guardId: '33333333-3333-4333-8333-333333333333',
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
};

const OPCIONES = { photoUrl: (_id: string, key: string | null) => (key ? `/foto/${key}` : null), guardMetersPerMinute: 250 };

describe('serializeOwnAlert (contrato 4.4)', () => {
  it('envía exactamente las 20 claves del front', () => {
    const json = serializeOwnAlert(REGISTRO, OPCIONES);
    expect(Object.keys(json).sort()).toEqual(
      [
        'acceptedAt', 'adminNote', 'arrivedAt', 'closedAt', 'escalationReason', 'etaSeconds', 'evidenceIncomplete',
        'guardId', 'guardName', 'heading', 'id', 'location', 'photoUrl', 'resolution', 'status', 'triggerMethod',
        'triggeredAt', 'userId', 'userName', 'userPhone',
      ].sort(),
    );
  });

  it('el dueño ve su alerta completa, con fechas ISO en UTC y el ETA calculado', () => {
    const json = serializeOwnAlert(REGISTRO, OPCIONES);
    expect(json.location).toEqual({ lat: 18.84, lng: -99.18 });
    expect(json.userPhone).toBe('7771234567');
    expect(json.guardName).toBe('Carlos Hernández López');
    expect(json.triggeredAt).toBe('2026-11-16T17:50:00.000Z');
    expect(json.acceptedAt).toBe('2026-11-16T17:51:10.000Z');
    expect(json.photoUrl).toBe('/foto/44444444-4444-4444-8444-444444444444');
    expect(json.etaSeconds).toBeGreaterThan(0);
  });

  it('nunca filtra campos internos', () => {
    const json = serializeOwnAlert(
      { ...REGISTRO, receivedAt: new Date(), statusChangedAt: new Date() } as AlertRecord,
      OPCIONES,
    ) as unknown as Record<string, unknown>;
    for (const interno of ['photoKey', 'receivedAt', 'statusChangedAt', 'lat', 'lng', 'user', 'guard']) {
      expect(json).not.toHaveProperty(interno);
    }
  });

  it('U-06: sin ubicación, sin guardia y sin foto todo va en null', () => {
    const json = serializeOwnAlert(
      { ...REGISTRO, status: 'pending_location', lat: null, lng: null, guardId: null, guard: null, photoKey: null, evidenceIncomplete: true, acceptedAt: null },
      OPCIONES,
    );
    expect(json.location).toBeNull();
    expect(json.guardName).toBeNull();
    expect(json.photoUrl).toBeNull();
    expect(json.evidenceIncomplete).toBe(true);
    expect(json.etaSeconds).toBeNull();
  });
});
