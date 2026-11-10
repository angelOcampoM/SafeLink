import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ConfigError, loadConfig } from '../../src/config/env.js';

const SECRETO = 'x'.repeat(32);
const base = (extra: Record<string, string> = {}): NodeJS.ProcessEnv => ({
  JWT_SECRET: SECRETO,
  ...extra,
});

function mensaje(fn: () => unknown): string {
  try {
    fn();
  } catch (e) {
    expect(e).toBeInstanceOf(ConfigError);
    return (e as ConfigError).message;
  }
  throw new Error('Se esperaba un ConfigError y no se lanzó nada');
}

// Lee un valor entero de lib/dominio/configuracion.dart (fuente de verdad).
const dart = readFileSync(
  resolve(import.meta.dirname, '../../../lib/dominio/configuracion.dart'),
  'utf8',
);
function dartInt(nombre: string): number {
  const m = new RegExp(`this\\.${nombre}\\s*=\\s*(\\d+)`).exec(dart);
  if (!m) throw new Error(`No se encontró ${nombre} en configuracion.dart`);
  return Number(m[1]);
}

describe('loadConfig - valores por defecto (BE-01 paso 1)', () => {
  it('config mínima válida produce defaults de servidor', () => {
    const c = loadConfig(base());
    expect(c.PORT).toBe(3000);
    expect(c.HOST).toBe('127.0.0.1');
    expect(c.TZ_SHIFTS).toBe('America/Mexico_City');
    expect(c.CORS_ORIGINS).toEqual([]);
    expect(c.DATABASE_URL).toBeUndefined();
  });

  it('los valores de dominio coinciden con lib/dominio/configuracion.dart', () => {
    const c = loadConfig(base());
    expect(c.GEOFENCE_METERS).toBe(dartInt('radioGeocercaMetros'));
    expect(c.ACCEPT_TIMEOUT_SECONDS).toBe(dartInt('minutosAceptacion') * 60);
    expect(c.CONFIRM_TIMEOUT_SECONDS).toBe(dartInt('minutosConfirmacion') * 60);
    expect(c.FALSE_ALARM_LIMIT).toBe(dartInt('limiteFalsasAlarmas'));
    expect(c.BLOCK_DAYS).toBe(dartInt('diasBloqueo'));
    expect(c.LOCATION_UPDATE_SECONDS).toBe(dartInt('segundosActualizacionUbicacion'));
    expect(c.WAIT_METERS_PER_MINUTE).toBe(dartInt('metrosPorMinutoEspera'));
    expect(c.GUARD_METERS_PER_MINUTE).toBe(dartInt('metrosPorMinutoGuardia'));
    expect(c.COVERAGE_RADIUS_MIN_METERS).toBe(dartInt('radioCoberturaMinMetros'));
    expect(c.COVERAGE_RADIUS_MAX_METERS).toBe(dartInt('radioCoberturaMaxMetros'));
  });

  it('valores literales esperados (50, 300, 900, 3, 7, 5, 100, 250, 500-10000, 300)', () => {
    const c = loadConfig(base());
    expect([
      c.GEOFENCE_METERS,
      c.ACCEPT_TIMEOUT_SECONDS,
      c.CONFIRM_TIMEOUT_SECONDS,
      c.FALSE_ALARM_LIMIT,
      c.BLOCK_DAYS,
      c.LOCATION_UPDATE_SECONDS,
      c.WAIT_METERS_PER_MINUTE,
      c.GUARD_METERS_PER_MINUTE,
      c.COVERAGE_RADIUS_MIN_METERS,
      c.COVERAGE_RADIUS_MAX_METERS,
      c.ADMIN_NOTE_MAX_LENGTH,
    ]).toEqual([50, 300, 900, 3, 7, 5, 100, 250, 500, 10000, 300]);
  });

  it('los valores configurables se pueden sobrescribir por entorno', () => {
    const c = loadConfig(base({ GEOFENCE_METERS: '80', PORT: '4000' }));
    expect(c.GEOFENCE_METERS).toBe(80);
    expect(c.PORT).toBe(4000);
  });
});

describe('loadConfig - JWT_SECRET', () => {
  it('falta JWT_SECRET: ConfigError en español que nombra la variable', () => {
    const m = mensaje(() => loadConfig({}));
    expect(m).toContain('JWT_SECRET');
    expect(m).toContain('Configuración inválida');
    expect(m).toContain('obligatoria');
  });

  it('JWT_SECRET de 31 caracteres falla (borde)', () => {
    const m = mensaje(() => loadConfig({ JWT_SECRET: 'x'.repeat(31) }));
    expect(m).toContain('JWT_SECRET');
    expect(m).toContain('32 caracteres');
  });

  it('JWT_SECRET de 32 caracteres es válido (borde)', () => {
    expect(() => loadConfig({ JWT_SECRET: 'x'.repeat(32) })).not.toThrow();
  });

  it('el mensaje de error no filtra el valor del secreto', () => {
    const corto = 'secreto-corto';
    expect(mensaje(() => loadConfig({ JWT_SECRET: corto }))).not.toContain(corto);
  });
});

describe('loadConfig - PORT y rangos', () => {
  it.each(['abc', '3000.5', '0', '-1', '65536', '99999'])('PORT=%j es inválido', (valor) => {
    const m = mensaje(() => loadConfig(base({ PORT: valor })));
    expect(m).toContain('PORT');
  });

  it.each(['1', '65535'])('PORT=%s es válido (bordes)', (valor) => {
    expect(loadConfig(base({ PORT: valor })).PORT).toBe(Number(valor));
  });

  it.each(['0', '-5', 'abc'])('GEOFENCE_METERS=%s es inválido', (valor) => {
    expect(mensaje(() => loadConfig(base({ GEOFENCE_METERS: valor })))).toContain(
      'GEOFENCE_METERS',
    );
  });

  it('NODE_ENV fuera del catálogo es inválido', () => {
    expect(mensaje(() => loadConfig(base({ NODE_ENV: 'staging' })))).toContain('NODE_ENV');
  });

  it('acumula varios errores en un solo ConfigError', () => {
    const m = mensaje(() => loadConfig({ PORT: 'abc' }));
    expect(m).toContain('JWT_SECRET');
    expect(m).toContain('PORT');
  });
});

describe('loadConfig - radio de cobertura', () => {
  it('mínimo mayor que máximo falla nombrando las variables', () => {
    const m = mensaje(() =>
      loadConfig(
        base({ COVERAGE_RADIUS_MIN_METERS: '20000', COVERAGE_RADIUS_MAX_METERS: '10000' }),
      ),
    );
    expect(m).toContain('COVERAGE_RADIUS_MIN_METERS');
    expect(m).toContain('COVERAGE_RADIUS_MAX_METERS');
  });

  it('mínimo igual al máximo es válido (borde)', () => {
    const c = loadConfig(
      base({ COVERAGE_RADIUS_MIN_METERS: '1000', COVERAGE_RADIUS_MAX_METERS: '1000' }),
    );
    expect(c.COVERAGE_RADIUS_MIN_METERS).toBe(1000);
  });
});

describe('loadConfig - CORS_ORIGINS', () => {
  it('se parsea como lista recortando espacios', () => {
    const c = loadConfig(
      base({ CORS_ORIGINS: 'http://localhost:3000, https://app.safelink.mx ' }),
    );
    expect(c.CORS_ORIGINS).toEqual(['http://localhost:3000', 'https://app.safelink.mx']);
  });

  it('descarta elementos vacíos', () => {
    expect(loadConfig(base({ CORS_ORIGINS: ' , a.com,, ' })).CORS_ORIGINS).toEqual(['a.com']);
  });

  it('cadena vacía produce lista vacía', () => {
    expect(loadConfig(base({ CORS_ORIGINS: '' })).CORS_ORIGINS).toEqual([]);
  });
});

describe('loadConfig - aislamiento', () => {
  it('no muta el objeto de entorno recibido', () => {
    const env = base();
    const copia = { ...env };
    loadConfig(env);
    expect(env).toEqual(copia);
  });
});
