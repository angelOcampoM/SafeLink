// BE-04 paso 3 · Prioridad del listado del guardia (G-03, D22, D24). Función pura, sin reloj real.
// Los casos espejan test/dominio/regla_prioridad_test.dart y lib/dominio/regla_prioridad.dart:
//   1. urgentes (`shake`) primero; 2. menor score = distancia - minutosEspera x metrosPorMinuto.
import { describe, expect, it } from 'vitest';
import { haversineMeters, type GeoPoint } from '../../src/domain/geo.js';
import {
  isUrgent,
  prioritizeAlerts,
  waitingMinutes,
  type PriorityCandidate,
} from '../../src/domain/priority.js';

const AHORA = new Date('2026-06-01T12:00:00.000Z');
const ORIGEN: GeoPoint = { lat: 0, lng: 0 };
const METROS_POR_GRADO = (6_371_000 * Math.PI) / 180; // 111 194.9266 m
const WAIT = 100;

/** Punto al norte del origen a `grados` de latitud: distancia = grados x METROS_POR_GRADO. */
const norte = (grados: number): GeoPoint => ({ lat: grados, lng: 0 });
const haceSegundos = (s: number): Date => new Date(AHORA.getTime() - s * 1000);

function cand(
  id: string,
  grados: number,
  segundos: number,
  triggerMethod = 'tap',
  receivedAt: Date = haceSegundos(segundos),
): PriorityCandidate<{ id: string }> {
  return { alert: { id }, id, triggerMethod, receivedAt, location: norte(grados) };
}
const ids = (r: Array<{ alert: { id: string } }>): string[] => r.map((x) => x.alert.id);

describe('prioritizeAlerts: orden (G-03)', () => {
  it('lista vacía -> lista vacía', () => {
    expect(prioritizeAlerts([], ORIGEN, AHORA, WAIT)).toEqual([]);
  });

  it('una sola alerta -> un elemento', () => {
    expect(ids(prioritizeAlerts([cand('a', 0.01, 0)], ORIGEN, AHORA, WAIT))).toEqual(['a']);
  });

  it('las urgentes (shake) van primero aunque estén mucho más lejos y esperen menos', () => {
    const r = prioritizeAlerts(
      [cand('cerca', 0.001, 600), cand('lejos-urgente', 0.2, 0, 'shake'), cand('media', 0.01, 60)],
      ORIGEN,
      AHORA,
      WAIT,
    );
    expect(ids(r)).toEqual(['lejos-urgente', 'cerca', 'media']);
  });

  it('hold y tap no son urgentes; solo shake lo es', () => {
    expect(isUrgent('shake')).toBe(true);
    expect(isUrgent('tap')).toBe(false);
    expect(isUrgent('hold')).toBe(false);
    const r = prioritizeAlerts([cand('t', 0.001, 0, 'tap'), cand('h', 0.0005, 0, 'hold')], ORIGEN, AHORA, WAIT);
    expect(ids(r)).toEqual(['h', 't']);
  });

  it('entre urgentes manda el score, igual que entre las demás', () => {
    const r = prioritizeAlerts(
      [cand('u-lejos', 0.1, 0, 'shake'), cand('u-cerca', 0.01, 0, 'shake'), cand('n', 0.0001, 0)],
      ORIGEN,
      AHORA,
      WAIT,
    );
    expect(ids(r)).toEqual(['u-cerca', 'u-lejos', 'n']);
  });

  it('más espera sube la prioridad: una más lejana pero antigua le gana a una cercana reciente', () => {
    // 0.01 grados ~ 1111.9 m; 0.012 grados ~ 1334.3 m. Con 5 min de espera: 1334.3 - 500 = 834.3 < 1111.9.
    const r = prioritizeAlerts([cand('cerca-nueva', 0.01, 0), cand('lejos-vieja', 0.012, 300)], ORIGEN, AHORA, WAIT);
    expect(ids(r)).toEqual(['lejos-vieja', 'cerca-nueva']);
  });

  it('a igual distancia gana la que espera más', () => {
    const r = prioritizeAlerts([cand('reciente', 0.01, 10), cand('antigua', 0.01, 120)], ORIGEN, AHORA, WAIT);
    expect(ids(r)).toEqual(['antigua', 'reciente']);
  });

  it('el peso de la espera sale del parámetro: con 0 solo cuenta la distancia', () => {
    const lista = [cand('lejos-vieja', 0.012, 3000), cand('cerca-nueva', 0.01, 0)];
    expect(ids(prioritizeAlerts(lista, ORIGEN, AHORA, 0))).toEqual(['cerca-nueva', 'lejos-vieja']);
    expect(ids(prioritizeAlerts(lista, ORIGEN, AHORA, 100))).toEqual(['lejos-vieja', 'cerca-nueva']);
  });

  it('empate exacto de score: desempata receivedAt más antiguo', () => {
    // Peso 0 y misma distancia: mismo score aunque la espera difiera.
    const viejo = cand('z-viejo', 0.01, 0, 'tap', haceSegundos(500));
    const nuevo = cand('a-nuevo', 0.01, 0, 'tap', haceSegundos(100));
    const r = prioritizeAlerts([nuevo, viejo], ORIGEN, AHORA, 0);
    expect(r[0]?.score).toBe(r[1]?.score);
    expect(ids(r)).toEqual(['z-viejo', 'a-nuevo']);
  });

  it('empate de score y de receivedAt: desempata por id ascendente, sin importar el orden de entrada', () => {
    const base = haceSegundos(60);
    const a = cand('aaa', 0.01, 60, 'tap', base);
    const b = cand('bbb', 0.01, 60, 'tap', base);
    const c = cand('ccc', 0.01, 60, 'tap', base);
    expect(ids(prioritizeAlerts([c, a, b], ORIGEN, AHORA, WAIT))).toEqual(['aaa', 'bbb', 'ccc']);
    expect(ids(prioritizeAlerts([b, c, a], ORIGEN, AHORA, WAIT))).toEqual(['aaa', 'bbb', 'ccc']);
  });

  it('las urgentes empatadas también se desempatan por receivedAt y luego id', () => {
    const base = haceSegundos(0);
    const r = prioritizeAlerts(
      [cand('b', 0.01, 0, 'shake', base), cand('a', 0.01, 0, 'shake', base), cand('c', 0.01, 0, 'shake', base)],
      ORIGEN,
      AHORA,
      WAIT,
    );
    expect(ids(r)).toEqual(['a', 'b', 'c']);
  });
});

describe('prioritizeAlerts: cifras (D24)', () => {
  it('fórmula exacta con valores calculados a mano', () => {
    // Alerta a 0.01 grados al norte: distancia = 0.01 x 111 194.9266 = 1 111.949266 m.
    // Espera 150 s = 2.5 min -> score = 1 111.949266 - 2.5 x 100 = 861.949266.
    const [r] = prioritizeAlerts([cand('a', 0.01, 150)], ORIGEN, AHORA, 100);
    expect(r?.distanceMeters).toBeCloseTo(0.01 * METROS_POR_GRADO, 6);
    expect(r?.distanceMeters).toBeCloseTo(1111.949266, 5);
    expect(r?.waitingMinutes).toBe(2.5);
    expect(r?.score).toBeCloseTo(861.949266, 5);
  });

  it('distanceMeters coincide con haversine desde el origen dado', () => {
    const origen: GeoPoint = { lat: 18.84, lng: -99.18 };
    const destino: GeoPoint = { lat: 18.85, lng: -99.17 };
    const c: PriorityCandidate<string> = { alert: 'x', id: 'x', triggerMethod: 'tap', receivedAt: AHORA, location: destino };
    const [r] = prioritizeAlerts([c], origen, AHORA, WAIT);
    expect(r?.distanceMeters).toBe(haversineMeters(origen, destino));
    expect(r?.waitingMinutes).toBe(0);
    expect(r?.score).toBe(r?.distanceMeters);
  });

  it('el peso de la espera usa el parámetro recibido', () => {
    const [r] = prioritizeAlerts([cand('a', 0.01, 60)], ORIGEN, AHORA, 250);
    expect(r?.score).toBeCloseTo(0.01 * METROS_POR_GRADO - 250, 6);
  });

  it('una alerta sin espera tiene waitingMinutes 0 y score = distancia', () => {
    const [r] = prioritizeAlerts([cand('a', 0.01, 0)], ORIGEN, AHORA, WAIT);
    expect(r?.waitingMinutes).toBe(0);
    expect(r?.score).toBe(r?.distanceMeters);
  });

  it('en el mismo punto del origen la distancia es 0 y el score es -espera x peso', () => {
    const [r] = prioritizeAlerts([cand('a', 0, 120)], ORIGEN, AHORA, WAIT);
    expect(r?.distanceMeters).toBe(0);
    expect(r?.waitingMinutes).toBe(2);
    expect(r?.score).toBe(-200);
  });

  it('waitingMinutes trunca los segundos: 59.9 s cuenta como 59 s (59/60 min)', () => {
    const recibida = new Date(AHORA.getTime() - 59_900);
    expect(waitingMinutes(recibida, AHORA)).toBe(59 / 60);
    const [r] = prioritizeAlerts([cand('a', 0.01, 0, 'tap', recibida)], ORIGEN, AHORA, WAIT);
    expect(r?.waitingMinutes).toBe(59 / 60);
  });

  it('con 0.9 s cuenta 0; con 60.999 s cuenta 1 min exacto; con 61 s, 61/60', () => {
    expect(waitingMinutes(new Date(AHORA.getTime() - 900), AHORA)).toBe(0);
    expect(waitingMinutes(new Date(AHORA.getTime() - 60_999), AHORA)).toBe(1);
    expect(waitingMinutes(new Date(AHORA.getTime() - 61_000), AHORA)).toBe(61 / 60);
  });

  it('no redondea: 90 s son 1.5 minutos', () => {
    expect(waitingMinutes(haceSegundos(90), AHORA)).toBe(1.5);
  });
});

describe('prioritizeAlerts: forma y pureza', () => {
  it('cada elemento tiene exactamente cuatro claves: alert, distanceMeters, waitingMinutes, score', () => {
    const r = prioritizeAlerts([cand('a', 0.01, 30), cand('b', 0.02, 0, 'shake')], ORIGEN, AHORA, WAIT);
    expect(r).toHaveLength(2);
    for (const e of r) {
      expect(Object.keys(e).sort()).toEqual(['alert', 'distanceMeters', 'score', 'waitingMinutes']);
      expect(typeof e.distanceMeters).toBe('number');
      expect(typeof e.waitingMinutes).toBe('number');
      expect(typeof e.score).toBe('number');
    }
  });

  it('devuelve el mismo objeto alert que recibió, sin copiarlo ni añadirle campos', () => {
    const alerta = { id: 'a', extra: 1 };
    const c: PriorityCandidate<typeof alerta> = {
      alert: alerta, id: 'a', triggerMethod: 'tap', receivedAt: haceSegundos(10), location: norte(0.01),
    };
    const [r] = prioritizeAlerts([c], ORIGEN, AHORA, WAIT);
    expect(r?.alert).toBe(alerta);
    expect(alerta).toEqual({ id: 'a', extra: 1 });
  });

  it('no muta la entrada: ni el arreglo, ni los candidatos, ni las fechas', () => {
    const entrada = [cand('lejos', 0.1, 0), cand('urgente', 0.2, 0, 'shake'), cand('cerca', 0.001, 0)];
    const copia = structuredClone(entrada);
    const refs = [...entrada];
    const salida = prioritizeAlerts(entrada, ORIGEN, AHORA, WAIT);
    expect(entrada).toEqual(copia);
    expect(entrada.every((c, i) => c === refs[i])).toBe(true);
    expect(salida).not.toBe(entrada);
    expect(ids(salida)).toEqual(['urgente', 'cerca', 'lejos']);
    expect(ids(entrada)).toEqual(['lejos', 'urgente', 'cerca']);
  });

  it('es determinista: la misma entrada da la misma salida', () => {
    const entrada = [cand('a', 0.01, 30), cand('b', 0.01, 30), cand('c', 0.02, 5, 'shake')];
    expect(prioritizeAlerts(entrada, ORIGEN, AHORA, WAIT)).toEqual(prioritizeAlerts(entrada, ORIGEN, AHORA, WAIT));
  });
});

describe('equivalencia con lib/dominio/regla_prioridad.dart', () => {
  /** Reimplementación literal de ReglaPrioridad.ordenar (Dart), con triggeredAt = receivedAt. */
  function referenciaDart(
    lista: Array<{ id: string; urgente: boolean; ubicacion: GeoPoint; disparadaEn: Date }>,
    guardia: GeoPoint,
    ahora: Date,
    metrosPorMinuto: number,
  ) {
    const p = lista.map((a) => {
      const d = haversineMeters(guardia, a.ubicacion);
      const w = Math.trunc((ahora.getTime() - a.disparadaEn.getTime()) / 1000) / 60.0;
      return { id: a.id, urgente: a.urgente, d, w, puntaje: d - w * metrosPorMinuto };
    });
    p.sort((x, y) => (x.urgente !== y.urgente ? (x.urgente ? -1 : 1) : x.puntaje - y.puntaje));
    return p;
  }

  const aCandidatos = (lista: Array<{ id: string; urgente: boolean; ubicacion: GeoPoint; disparadaEn: Date }>) =>
    lista.map((a) => ({
      alert: a.id, id: a.id, triggerMethod: a.urgente ? 'shake' : 'tap', receivedAt: a.disparadaEn, location: a.ubicacion,
    }));

  it('regla_prioridad_test.dart "doble clic de volumen primero": cerca vs lejos-shake', () => {
    const guardia: GeoPoint = { lat: 18.84, lng: -99.18 };
    const lista = [
      { id: 'cerca', urgente: false, ubicacion: { lat: guardia.lat + 0.001, lng: guardia.lng }, disparadaEn: AHORA },
      { id: 'lejos-shake', urgente: true, ubicacion: { lat: guardia.lat + 0.02, lng: guardia.lng }, disparadaEn: AHORA },
    ];
    const real = prioritizeAlerts(aCandidatos(lista), guardia, AHORA, 100).map((r) => r.alert);
    expect(real).toEqual(['lejos-shake', 'cerca']);
    expect(real).toEqual(referenciaDart(lista, guardia, AHORA, 100).map((e) => e.id));
  });

  it('regla_prioridad_test.dart "cada minuto de espera equivale a 100 m": A ~555 m / 0 min vs B ~888 m / 5 min', () => {
    const guardia: GeoPoint = { lat: 18.84, lng: -99.18 };
    const lista = [
      { id: 'A', urgente: false, ubicacion: { lat: guardia.lat + 0.005, lng: guardia.lng }, disparadaEn: AHORA },
      { id: 'B', urgente: false, ubicacion: { lat: guardia.lat + 0.008, lng: guardia.lng }, disparadaEn: haceSegundos(300) },
    ];
    const real = prioritizeAlerts(aCandidatos(lista), guardia, AHORA, 100);
    expect(real[0]?.alert).toBe('B');
    expect(real[0]?.distanceMeters).toBeCloseTo(889.56, 1);
    expect(real[0]?.score).toBeCloseTo(389.56, 1);
    expect(real[1]?.score).toBeCloseTo(555.97, 1);
  });

  it('caso mixto: urgente lejana + dos normales con distinta espera; mismas cifras que el Dart', () => {
    const guardia: GeoPoint = { lat: 18.84, lng: -99.18 };
    const lista = [
      { id: 'a', urgente: false, ubicacion: { lat: 18.842, lng: -99.18 }, disparadaEn: haceSegundos(30) },
      { id: 'b', urgente: true, ubicacion: { lat: 18.9, lng: -99.1 }, disparadaEn: haceSegundos(5) },
      { id: 'c', urgente: false, ubicacion: { lat: 18.845, lng: -99.18 }, disparadaEn: haceSegundos(600) },
    ];
    const esperado = referenciaDart(lista, guardia, AHORA, 100);
    const real = prioritizeAlerts(aCandidatos(lista), guardia, AHORA, 100);
    expect(real.map((r) => r.alert)).toEqual(esperado.map((e) => e.id));
    expect(real.map((r) => r.alert)).toEqual(['b', 'c', 'a']);
    real.forEach((r, i) => {
      expect(r.distanceMeters).toBe(esperado[i]?.d);
      expect(r.waitingMinutes).toBe(esperado[i]?.w);
      expect(r.score).toBe(esperado[i]?.puntaje);
    });
  });
});
