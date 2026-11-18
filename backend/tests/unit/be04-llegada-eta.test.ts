// BE-04 paso 7 (unitarias): D47, el ETA que ve el dueño se redondea hacia arriba (roundEtaUp),
// ETA_ROUNDING_SECONDS en la configuración y qué vistas redondean (solo la del dueño).
import { describe, expect, it } from 'vitest';
import { etaSeconds, roundEtaUp } from '../../src/domain/alert-rules.js';
import { ConfigError, loadConfig } from '../../src/config/env.js';
import { haversineMeters, snapToGrid, type GeoPoint } from '../../src/domain/geo.js';
import {
  serializeGuardAlert,
  serializeOwnAlert,
  type AlertRecord,
  type SerializeOptions,
} from '../../src/modules/alerts/serializers.js';

describe('roundEtaUp (D47)', () => {
  it('null pasa igual', () => {
    expect(roundEtaUp(null, 60)).toBeNull();
    expect(roundEtaUp(null, 1)).toBeNull();
  });

  it('0 se queda en 0 (ya llegó o está encima)', () => {
    expect(roundEtaUp(0, 60)).toBe(0);
  });

  it('un múltiplo exacto no cambia', () => {
    expect(roundEtaUp(60, 60)).toBe(60);
    expect(roundEtaUp(120, 60)).toBe(120);
    expect(roundEtaUp(600, 60)).toBe(600);
  });

  it('1 s por encima de un múltiplo sube al siguiente; 1 s por debajo se queda en el múltiplo', () => {
    expect(roundEtaUp(61, 60)).toBe(120);
    expect(roundEtaUp(59, 60)).toBe(60);
    expect(roundEtaUp(1, 60)).toBe(60);
    expect(roundEtaUp(119, 60)).toBe(120);
    expect(roundEtaUp(121, 60)).toBe(180);
  });

  it('paso 1 (y menores) no redondea', () => {
    expect(roundEtaUp(267, 1)).toBe(267);
    expect(roundEtaUp(267, 0)).toBe(267);
    expect(roundEtaUp(267, -5)).toBe(267);
  });

  it('paso grande: cualquier ETA positivo sube al paso completo', () => {
    expect(roundEtaUp(1, 3600)).toBe(3600);
    expect(roundEtaUp(3600, 3600)).toBe(3600);
    expect(roundEtaUp(3601, 3600)).toBe(7200);
  });

  it('nunca baja el ETA y siempre devuelve un múltiplo del paso (barrido 0..400)', () => {
    for (let eta = 0; eta <= 400; eta += 1) {
      const r = roundEtaUp(eta, 60) as number;
      expect(r, `eta ${String(eta)}`).toBeGreaterThanOrEqual(eta);
      expect(r - eta, `eta ${String(eta)}`).toBeLessThan(60);
      expect(r % 60, `eta ${String(eta)}`).toBe(0);
    }
  });

  it('es monótono: un ETA mayor nunca da un redondeo menor', () => {
    let previo = 0;
    for (let eta = 0; eta <= 400; eta += 1) {
      const r = roundEtaUp(eta, 45) as number;
      expect(r).toBeGreaterThanOrEqual(previo);
      previo = r;
    }
  });
});

describe('loadConfig: ETA_ROUNDING_SECONDS (D47)', () => {
  const base = (extra: Record<string, string> = {}): NodeJS.ProcessEnv => ({ JWT_SECRET: 'x'.repeat(32), ...extra });

  it('por defecto 60', () => {
    expect(loadConfig(base()).ETA_ROUNDING_SECONDS).toBe(60);
  });

  it('se puede sobrescribir por entorno', () => {
    expect(loadConfig(base({ ETA_ROUNDING_SECONDS: '30' })).ETA_ROUNDING_SECONDS).toBe(30);
    expect(loadConfig(base({ ETA_ROUNDING_SECONDS: '120' })).ETA_ROUNDING_SECONDS).toBe(120);
  });

  it.each(['0', '-1', '-60', '1', '29', '1.5', '60.5', 'abc', 'NaN', 'Infinity'])('rechaza %s nombrando la variable', (valor) => {
    let error: unknown;
    try {
      loadConfig(base({ ETA_ROUNDING_SECONDS: valor }));
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(ConfigError);
    expect((error as ConfigError).message).toContain('ETA_ROUNDING_SECONDS');
  });
});

describe('loadConfig: ETA_GUARD_GRID_METERS (D47)', () => {
  const base = (extra: Record<string, string> = {}): NodeJS.ProcessEnv => ({ JWT_SECRET: 'x'.repeat(32), ...extra });

  it('por defecto 250', () => {
    expect(loadConfig(base()).ETA_GUARD_GRID_METERS).toBe(250);
  });

  it('se puede sobrescribir por entorno; 100 es el mínimo válido', () => {
    expect(loadConfig(base({ ETA_GUARD_GRID_METERS: '100' })).ETA_GUARD_GRID_METERS).toBe(100);
    expect(loadConfig(base({ ETA_GUARD_GRID_METERS: '500' })).ETA_GUARD_GRID_METERS).toBe(500);
  });

  it.each(['99', '0', '-1', '-250', '250.5', '1.5', 'abc', 'NaN', 'Infinity'])('rechaza %s nombrando la variable', (valor) => {
    let error: unknown;
    try {
      loadConfig(base({ ETA_GUARD_GRID_METERS: valor }));
    } catch (e) {
      error = e;
    }
    expect(error).toBeInstanceOf(ConfigError);
    expect((error as ConfigError).message).toContain('ETA_GUARD_GRID_METERS');
  });
});

describe('snapToGrid (D47)', () => {
  const CELDA = 250;
  const P: GeoPoint = { lat: 18.85, lng: -99.18 };
  const enRango = (p: GeoPoint) =>
    Number.isFinite(p.lat) && Number.isFinite(p.lng) && p.lat >= -90 && p.lat <= 90 && p.lng >= -180 && p.lng <= 180;

  it('es idempotente: ajustar un centro lo deja igual', () => {
    const puntos: GeoPoint[] = [P, { lat: -33.4, lng: 151.2 }, { lat: 64.1, lng: -21.9 }, { lat: 0.0001, lng: 0.0001 }, { lat: 18.8502, lng: -99.1801 }];
    for (const p of puntos) {
      const una = snapToGrid(p, CELDA);
      const dos = snapToGrid(una, CELDA);
      expect(dos.lat).toBeCloseTo(una.lat, 9);
      expect(dos.lng).toBeCloseTo(una.lng, 9);
    }
  });

  it('dos puntos de la misma celda dan exactamente el mismo centro', () => {
    const a = snapToGrid({ lat: 18.85, lng: -99.18 }, CELDA);
    expect(snapToGrid({ lat: 18.8504, lng: -99.1803 }, CELDA)).toEqual(a);
    expect(snapToGrid({ lat: 18.8497, lng: -99.1795 }, CELDA)).toEqual(a);
  });

  it('puntos a ambos lados de un borde de la celda dan centros distintos (latitud y longitud)', () => {
    const centro = snapToGrid(P, CELDA);
    const paso = CELDA / 111_320;
    const bordeNorte = centro.lat + paso / 2;
    const sur = snapToGrid({ lat: bordeNorte - 1e-6, lng: P.lng }, CELDA);
    const norte = snapToGrid({ lat: bordeNorte + 1e-6, lng: P.lng }, CELDA);
    expect(sur.lat).not.toBe(norte.lat);
    expect(norte.lat - sur.lat).toBeCloseTo(paso, 9);

    const pasoLng = paso / Math.cos((centro.lat * Math.PI) / 180);
    const bordeEste = centro.lng + pasoLng / 2;
    const oeste = snapToGrid({ lat: centro.lat, lng: bordeEste - 1e-6 }, CELDA);
    const este = snapToGrid({ lat: centro.lat, lng: bordeEste + 1e-6 }, CELDA);
    expect(oeste.lng).not.toBe(este.lng);
    expect(oeste.lat).toBe(este.lat);
  });

  it.each([100, 250, 1000])('el centro queda a <= 0.75 x celda (%i m) del punto original', (celda) => {
    const puntos: GeoPoint[] = [P, { lat: 18.8497, lng: -99.1795 }, { lat: -33.4, lng: 151.2 }, { lat: 60, lng: 10 }, { lat: 0, lng: 0 }, { lat: -12.3456, lng: -77.7777 }];
    for (const p of puntos) {
      expect(haversineMeters(p, snapToGrid(p, celda)), JSON.stringify(p)).toBeLessThanOrEqual(celda * 0.75);
    }
  });

  it('con celda positiva mueve el punto al centro de la celda', () => {
    expect(snapToGrid(P, CELDA)).not.toEqual(P);
  });

  it('bordes de latitud y longitud: resultado finito y dentro de rango', () => {
    const puntos: GeoPoint[] = [
      { lat: 90, lng: 0 }, { lat: -90, lng: 0 }, { lat: 0, lng: 180 }, { lat: 0, lng: -180 },
      { lat: 90, lng: 180 }, { lat: -90, lng: -180 }, { lat: 89.99999, lng: 179.99999 }, { lat: -89.99999, lng: -179.99999 },
    ];
    for (const p of puntos) expect(enRango(snapToGrid(p, CELDA)), JSON.stringify(p)).toBe(true);
  });

  it('valores fuera de rango se recortan y el resultado sigue en rango', () => {
    const puntos: GeoPoint[] = [{ lat: 123, lng: 0 }, { lat: -123, lng: 0 }, { lat: 0, lng: 500 }, { lat: 0, lng: -500 }, { lat: 1e6, lng: -1e6 }];
    for (const p of puntos) expect(enRango(snapToGrid(p, CELDA)), JSON.stringify(p)).toBe(true);
    expect(snapToGrid({ lat: 123, lng: 10 }, CELDA)).toEqual(snapToGrid({ lat: 90, lng: 10 }, CELDA));
    expect(snapToGrid({ lat: 10, lng: -500 }, CELDA)).toEqual(snapToGrid({ lat: 10, lng: -180 }, CELDA));
  });

  it('cerca del polo no se divide entre cero ni se sale de rango', () => {
    expect(enRango(snapToGrid({ lat: 89.9999, lng: 45 }, CELDA))).toBe(true);
  });

  it('punto no finito devuelve el mismo punto sin cambios', () => {
    const puntos: GeoPoint[] = [{ lat: NaN, lng: 1 }, { lat: 1, lng: NaN }, { lat: Infinity, lng: 1 }, { lat: 1, lng: -Infinity }];
    for (const p of puntos) expect(snapToGrid(p, CELDA)).toBe(p);
  });

  it.each([0, -1, -250, NaN])('celda %s devuelve el punto sin cambios', (celda) => {
    expect(snapToGrid(P, celda)).toBe(P);
    expect(snapToGrid(P, celda)).toEqual({ lat: 18.85, lng: -99.18 });
  });

  it('es determinista: la misma entrada da siempre la misma salida', () => {
    const primero = snapToGrid(P, CELDA);
    for (let i = 0; i < 20; i += 1) expect(snapToGrid({ ...P }, CELDA)).toEqual(primero);
  });
});

describe('qué vistas redondean el ETA (D47)', () => {
  const MIO = '33333333-3333-4333-8333-333333333333';
  const registro = (extra: Partial<AlertRecord> = {}): AlertRecord => ({
    id: '11111111-1111-4111-8111-111111111111',
    userId: '22222222-2222-4222-8222-222222222222',
    guardId: MIO,
    status: 'in_progress',
    triggerMethod: 'tap',
    photoKey: null,
    evidenceIncomplete: false,
    lat: 18.84,
    lng: -99.18,
    heading: null,
    triggeredAt: new Date('2026-11-16T17:50:00.000Z'),
    acceptedAt: new Date('2026-11-16T17:51:10.000Z'),
    arrivedAt: null,
    closedAt: null,
    escalationReason: null,
    resolution: null,
    adminNote: null,
    user: { name: 'Dueño', phone: '7771234567' },
    guard: { name: 'Guardia', guardProfile: { lastLocationLat: 18.85, lastLocationLng: -99.18 } },
    ...extra,
  });
  const opciones = (extra: Partial<SerializeOptions> = {}): SerializeOptions => ({
    photoUrl: () => null,
    guardMetersPerMinute: 250,
    etaRoundingSeconds: 1,
    guardGridMeters: 0, // sin celda por defecto: las pruebas de redondeo fijan solo el paso (la celda se prueba aparte)
    ...extra,
  });
  const exacto = etaSeconds('in_progress', { lat: 18.85, lng: -99.18 }, { lat: 18.84, lng: -99.18 }, 250) as number;

  it('el caso de prueba sirve: el ETA exacto no es múltiplo de 60', () => {
    expect(exacto % 60).not.toBe(0);
  });

  it('serializeOwnAlert (dueño) redondea hacia arriba al paso configurado', () => {
    const json = serializeOwnAlert(registro(), opciones({ etaRoundingSeconds: 60 }));
    expect(json.etaSeconds).toBe(roundEtaUp(exacto, 60));
    expect((json.etaSeconds as number) % 60).toBe(0);
    expect(json.etaSeconds).toBeGreaterThan(exacto);
  });

  it('serializeOwnAlert respeta otro paso', () => {
    expect(serializeOwnAlert(registro(), opciones({ etaRoundingSeconds: 100 })).etaSeconds).toBe(
      roundEtaUp(exacto, 100),
    );
  });

  it('serializeGuardAlert (guardia) devuelve el valor exacto aunque haya paso configurado', () => {
    const json = serializeGuardAlert(registro(), MIO, opciones({ etaRoundingSeconds: 60 }));
    expect(json.etaSeconds).toBe(exacto);
  });

  describe('con celda real (ETA_GUARD_GRID_METERS)', () => {
    const CELDA = 250;
    const PASO = 60;
    const alerta: GeoPoint = { lat: 18.84, lng: -99.18 };
    const guardia: GeoPoint = { lat: 18.85, lng: -99.18 };
    const conGuardia = (p: GeoPoint) =>
      registro({ guard: { name: 'Guardia', guardProfile: { lastLocationLat: p.lat, lastLocationLng: p.lng } } });
    const o = opciones({ etaRoundingSeconds: PASO, guardGridMeters: CELDA });

    it('serializeOwnAlert devuelve roundEtaUp(etaSeconds(snap(guardia), alerta), paso)', () => {
      const esperado = roundEtaUp(etaSeconds('in_progress', snapToGrid(guardia, CELDA), alerta, 250), PASO);
      expect(serializeOwnAlert(registro(), o).etaSeconds).toBe(esperado);
      expect((esperado as number) % PASO).toBe(0);
    });

    it('serializeGuardAlert devuelve el ETA con la posición exacta (sin celda ni redondeo)', () => {
      expect(serializeGuardAlert(registro(), MIO, o).etaSeconds).toBe(exacto);
    });

    it('dos posiciones del guardia dentro de la misma celda dan el mismo ETA al dueño y distinto al guardia', () => {
      const b: GeoPoint = { lat: 18.8504, lng: -99.1803 };
      expect(snapToGrid(guardia, CELDA)).toEqual(snapToGrid(b, CELDA)); // el caso sirve: misma celda
      expect(serializeOwnAlert(conGuardia(guardia), o).etaSeconds).toBe(serializeOwnAlert(conGuardia(b), o).etaSeconds);
      expect(serializeGuardAlert(conGuardia(guardia), MIO, o).etaSeconds).not.toBe(
        serializeGuardAlert(conGuardia(b), MIO, o).etaSeconds,
      );
    });

    it('celda 0 y paso 1: el dueño ve el ETA exacto', () => {
      expect(serializeOwnAlert(registro(), opciones({ etaRoundingSeconds: 1, guardGridMeters: 0 })).etaSeconds).toBe(exacto);
    });

    it('guardia sin ubicación o alerta fuera de curso: null aunque haya celda', () => {
      expect(serializeOwnAlert(registro({ guard: { name: 'G', guardProfile: null } }), o).etaSeconds).toBeNull();
      expect(serializeOwnAlert(registro({ status: 'closed' }), o).etaSeconds).toBeNull();
    });
  });

  it('con alerta que no está en curso o sin ubicaciones el ETA sigue siendo null en ambas vistas', () => {
    const o = opciones({ etaRoundingSeconds: 60 });
    expect(serializeOwnAlert(registro({ status: 'searching', guardId: null, guard: null }), o).etaSeconds).toBeNull();
    expect(serializeOwnAlert(registro({ guard: { name: 'G', guardProfile: null } }), o).etaSeconds).toBeNull();
    expect(serializeGuardAlert(registro({ status: 'closed' }), MIO, o).etaSeconds).toBeNull();
  });

  it('un guardia encima de la alerta: ETA 0 en ambas vistas', () => {
    const encima = registro({ guard: { name: 'G', guardProfile: { lastLocationLat: 18.84, lastLocationLng: -99.18 } } });
    expect(serializeOwnAlert(encima, opciones({ etaRoundingSeconds: 60 })).etaSeconds).toBe(0);
    expect(serializeGuardAlert(encima, MIO, opciones({ etaRoundingSeconds: 60 })).etaSeconds).toBe(0);
  });
});
