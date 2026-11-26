// Reinicio de la demo (CR-B01 del plan de consumo real).
//   npm run demo:reset                                   -> borra todas las alertas
//   npm run demo:reset -- --center 18.84,-99.18          -> además mueve la cobertura de los
//                                                           guardias de turno a ese punto
//   npm run demo:reset -- --center 18.84,-99.18 --radius 3000
// Borra alertas (su historial y los "ignorar" caen en cascada). Conserva cuentas, perfiles,
// sesiones y tokens de dispositivo: nadie tiene que volver a iniciar sesión.
// Igual que la semilla, solo corre con NODE_ENV development o test (D28).

import { envSchema } from '../src/config/env.js';
import { createPrisma } from '../src/db/prisma.js';
import { isShiftActive } from '../src/domain/shift.js';
import { Role } from '../src/generated/prisma/enums.js';

interface Opciones {
  center: { lat: number; lng: number } | null;
  radius: number | null;
}

const USO = 'Uso: npm run demo:reset -- [--center <lat>,<lng>] [--radius <metros>]';

function fallar(mensaje: string): never {
  console.error(mensaje);
  process.exit(1);
}

/** Lee `--center` y `--radius`. Cualquier error sale antes de tocar la base. */
function leerOpciones(args: readonly string[], radioMin: number, radioMax: number): Opciones {
  let center: Opciones['center'] = null;
  let radius: number | null = null;
  for (let i = 0; i < args.length; i++) {
    const nombre = args[i];
    const valor = args[i + 1];
    if (nombre !== '--center' && nombre !== '--radius') fallar(`Opción desconocida: ${nombre}. ${USO}`);
    if (valor === undefined) fallar(`Falta el valor de ${nombre}. ${USO}`);
    i++;
    if (nombre === '--center') {
      const partes = valor.split(',').map((p) => p.trim());
      const [lat, lng] = partes.map(Number);
      if (partes.length !== 2 || lat === undefined || lng === undefined || !Number.isFinite(lat) || !Number.isFinite(lng)) {
        fallar(`--center debe ser "<lat>,<lng>" con números (ej. 18.84,-99.18). ${USO}`);
      }
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        fallar('--center fuera de rango: la latitud va de -90 a 90 y la longitud de -180 a 180.');
      }
      center = { lat, lng };
    } else {
      const metros = Number(valor);
      if (!Number.isInteger(metros) || metros < radioMin || metros > radioMax) {
        fallar(`--radius debe ser un entero entre ${radioMin} y ${radioMax} metros.`);
      }
      radius = metros;
    }
  }
  if (radius !== null && center === null) fallar(`--radius solo tiene sentido junto con --center. ${USO}`);
  return { center, radius };
}

async function main(): Promise<void> {
  const entorno = process.env['NODE_ENV'];
  if (entorno !== 'development' && entorno !== 'test') {
    fallar(
      'demo:reset exige NODE_ENV=development o NODE_ENV=test definido de forma explícita (en backend/.env o en el entorno). No se hizo ningún cambio.',
    );
  }
  const url = process.env['DATABASE_URL'];
  if (!url) fallar('Falta DATABASE_URL: define la variable en backend/.env.');

  // Mismos valores y defaults que la API (src/config/env.ts).
  const cfg = envSchema
    .pick({ TZ_SHIFTS: true, COVERAGE_RADIUS_MIN_METERS: true, COVERAGE_RADIUS_MAX_METERS: true })
    .safeParse(process.env);
  if (!cfg.success) {
    fallar(`Configuración inválida en: ${cfg.error.issues.map((i) => i.path.join('.')).join(', ')}.`);
  }
  const { TZ_SHIFTS: tz, COVERAGE_RADIUS_MIN_METERS: radioMin, COVERAGE_RADIUS_MAX_METERS: radioMax } = cfg.data;
  const opciones = leerOpciones(process.argv.slice(2), radioMin, radioMax);

  const prisma = createPrisma(url);
  try {
    const { count: alertas } = await prisma.alert.deleteMany({});
    console.log(`Alertas borradas: ${alertas} (con su historial y sus "ignorar").`);

    if (opciones.center) {
      const ahora = new Date();
      const perfiles = await prisma.guardProfile.findMany({
        where: { user: { role: Role.guard, isActive: true } },
        select: { userId: true, shiftStart: true, shiftEnd: true, coverageRadiusMeters: true, user: { select: { email: true } } },
      });
      const deTurno = perfiles.filter((p) => isShiftActive(p.shiftStart, p.shiftEnd, ahora, tz));
      for (const p of deTurno) {
        await prisma.guardProfile.update({
          where: { userId: p.userId },
          data: {
            coverageCenterLat: opciones.center.lat,
            coverageCenterLng: opciones.center.lng,
            coverageRadiusMeters: opciones.radius ?? p.coverageRadiusMeters ?? radioMin,
          },
        });
      }
      const correos = deTurno.map((p) => p.user.email).join(', ') || 'ninguno';
      console.log(
        `Cobertura movida a ${opciones.center.lat},${opciones.center.lng} para ${deTurno.length} guardia(s) de turno: ${correos}.`,
      );
    }
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e: unknown) => {
  console.error('demo:reset falló:', e instanceof Error ? e.message : e);
  process.exit(1);
});
