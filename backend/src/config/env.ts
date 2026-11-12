import { z } from 'zod';

const entero = (def: number) => z.coerce.number().int().positive().default(def);

export const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().min(1).default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.string().min(1).optional(),
  DATABASE_URL_TEST: z.string().min(1).optional(),
  JWT_SECRET: z.string().min(32, 'debe tener al menos 32 caracteres'),
  JWT_ACCESS_EXPIRES_IN: z.string().min(1).default('15m'),
  JWT_REFRESH_EXPIRES_IN: z.string().min(1).default('30d'),
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((v) =>
      v
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
    ),
  TZ_SHIFTS: z.string().min(1).default('America/Mexico_City'),
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
