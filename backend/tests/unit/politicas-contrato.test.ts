// BE-01 paso 6: las políticas centrales (ROUTE_POLICIES) deben cubrir EXACTAMENTE las rutas que el
// front usa (lib/datos/safelink_service.dart) y los canales que escucha (escuchar('...')).
// Extra permitido: POST /auth/refresh (D8) y los 4 canales SSE como GET /events/<canal>.
import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ROUTE_POLICIES } from '../../src/security/policies.js';

const RAIZ = resolve(import.meta.dirname, '..', '..', '..');
const DATOS = resolve(RAIZ, 'lib/datos');
const servicio = readFileSync(resolve(DATOS, 'safelink_service.dart'), 'utf8');

// _Ruta('METODO', '/ruta', ...) en una o varias líneas (el constructor `_Ruta(this.metodo` no coincide).
const rutasFront = [...servicio.matchAll(/_Ruta\(\s*'([A-Z]+)'\s*,\s*'(\/[^']*)'/g)].map(
  (m) => `${m[1] as string} ${m[2] as string}`,
);

const canalesFront = (() => {
  const canales = new Set<string>();
  for (const f of readdirSync(DATOS).filter((n) => n.endsWith('.dart'))) {
    const src = readFileSync(resolve(DATOS, f), 'utf8');
    for (const m of src.matchAll(/escuchar\(\s*'([^']+)'/g)) {
      canales.add((m[1] as string).replace(/\$\w+/g, ':id'));
    }
  }
  return [...canales].sort();
})();

const claves = Object.keys(ROUTE_POLICIES);
const clavesEvents = claves.filter((k) => k.startsWith('GET /events/'));
const clavesRest = claves.filter((k) => !k.startsWith('GET /events/') && k !== 'POST /auth/refresh');

describe('Contrato de políticas de acceso front <-> backend (BE-01 paso 6)', () => {
  it('la extracción por regex encuentra las 31 rutas del front, sin duplicados', () => {
    expect(rutasFront).toHaveLength(31);
    expect(new Set(rutasFront).size).toBe(31);
  });

  it('las claves REST de ROUTE_POLICIES coinciden EXACTAMENTE con safelink_service.dart', () => {
    expect([...clavesRest].sort()).toEqual([...rutasFront].sort());
  });

  it('el front escucha exactamente 4 canales y los canales SSE de la política coinciden', () => {
    expect(canalesFront).toEqual([
      'admin/alerts/escalated',
      'alerts/active',
      'guard/alerts',
      'guard/alerts/:id',
    ]);
    expect(clavesEvents.map((k) => k.replace('GET /events/', '')).sort()).toEqual(canalesFront);
  });

  it('POST /auth/refresh es la única ruta extra y no existe en el front', () => {
    expect(rutasFront).not.toContain('POST /auth/refresh');
    expect(claves).toContain('POST /auth/refresh');
    expect(claves).toHaveLength(rutasFront.length + canalesFront.length + 1);
    expect(claves).toHaveLength(36);
  });

  it('todas las claves siguen el formato "MÉTODO /ruta" y los canales SSE son GET', () => {
    for (const k of claves) expect(k, k).toMatch(/^(GET|POST|PUT|PATCH|DELETE) \/[a-z/:]+$/);
    for (const k of clavesEvents) expect(k.startsWith('GET ')).toBe(true);
  });
});
