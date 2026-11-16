import { z } from 'zod';
import { DURATION_PATTERN } from './duration.js';

function esZonaIana(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone });
    return true;
  } catch {
    return false;
  }
}

const entero = (def: number) => z.coerce.number().int().positive().default(def);
const duracion = (def: string) =>
  z
    .string()
    .regex(DURATION_PATTERN, 'formato esperado: número y unidad s, m, h o d (ej. 15m)')
    .default(def);

export const envSchema = z.object({
  // Si falta, se asume 'production' (lo más restrictivo): el modo desarrollo hay que pedirlo.
  NODE_ENV: z.enum(['development', 'test', 'production']).default('production'),
  HOST: z.string().min(1).default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.string().min(1).optional(),
  DATABASE_URL_TEST: z.string().min(1).optional(),
  JWT_SECRET: z.string().min(32, 'debe tener al menos 32 caracteres'),
  JWT_ACCESS_EXPIRES_IN: duracion('15m'),
  JWT_REFRESH_EXPIRES_IN: duracion('30d'),
  // Ventana (segundos) en que un refresh token recién usado se acepta una vez más (D25). 0 la desactiva.
  REFRESH_GRACE_SECONDS: z.coerce.number().int().min(0).max(60).default(5),
  // Vida máxima absoluta de una sesión, aunque se siga rotando el refresh token.
  JWT_SESSION_MAX_AGE: duracion('90d'),
  // Rate limit por IP (memoria del proceso) de POST /auth/login y /auth/refresh.
  RATE_LIMIT_LOGIN_MAX: entero(10),
  RATE_LIMIT_LOGIN_WINDOW: duracion('1m'),
  RATE_LIMIT_REFRESH_MAX: entero(30),
  RATE_LIMIT_REFRESH_WINDOW: duracion('1m'),
  // Parámetros de argon2id (por defecto, los de la librería).
  ARGON2_MEMORY_KIB: entero(65536).pipe(z.number().min(19456).max(1048576)),
  ARGON2_TIME_COST: entero(3).pipe(z.number().min(2).max(10)),
  ARGON2_PARALLELISM: entero(4).pipe(z.number().min(1).max(16)),
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((v) =>
      v
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
    ),
  TZ_SHIFTS: z
    .string()
    .refine(
      (v) => v.length > 0 && esZonaIana(v),
      'debe ser una zona horaria IANA válida (ej. America/Mexico_City)',
    )
    .default('America/Mexico_City'),
  GEOFENCE_METERS: entero(50),
  ACCEPT_TIMEOUT_SECONDS: entero(300),
  CONFIRM_TIMEOUT_SECONDS: entero(900),
  FALSE_ALARM_LIMIT: entero(3),
  BLOCK_DAYS: entero(7),
  LOCATION_UPDATE_SECONDS: entero(5),
  WAIT_METERS_PER_MINUTE: entero(100),
  GUARD_METERS_PER_MINUTE: entero(250),
  COVERAGE_RADIUS_MIN_METERS: entero(500),
  COVERAGE_RADIUS_MAX_METERS: entero(10000),
  ADMIN_NOTE_MAX_LENGTH: entero(300),
  TRIGGERED_AT_TOLERANCE_SECONDS: entero(600),
  BODY_LIMIT_BYTES: entero(1048576).pipe(z.number().max(10 * 1024 * 1024)),
});

export type Config = z.infer<typeof envSchema>;

export class ConfigError extends Error {
  constructor(public readonly details: string[]) {
    super(
      `Configuración inválida. Revisa estas variables de entorno:\n${details
        .map((d) => `  - ${d}`)
        .join('\n')}`,
    );
    this.name = 'ConfigError';
  }
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const result = envSchema.safeParse(env);
  if (!result.success) {
    const details = result.error.issues.map((i) => {
      const nombre = i.path.join('.') || '(general)';
      const faltante = env[nombre] === undefined;
      return faltante
        ? `${nombre}: es obligatoria y no está definida`
        : `${nombre}: valor inválido (${i.message})`;
    });
    throw new ConfigError(details);
  }
  const cfg = result.data;
  if (cfg.COVERAGE_RADIUS_MIN_METERS > cfg.COVERAGE_RADIUS_MAX_METERS) {
    throw new ConfigError([
      'COVERAGE_RADIUS_MIN_METERS: no puede ser mayor que COVERAGE_RADIUS_MAX_METERS',
    ]);
  }
  return cfg;
}
