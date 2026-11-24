// Base de pruebas de integración (DATABASE_URL_TEST).
//   node scripts/db-test.mjs create  -> crea la base si no existe (vía el contenedor db)
//   node scripts/db-test.mjs deploy  -> aplica las migraciones pendientes (no borra datos)
//   node scripts/db-test.mjs reset   -> reaplica todas las migraciones desde cero (sin semilla)
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';

// CLI de Prisma ejecutado con el mismo Node (sin shell: funciona igual en Windows y Linux).
const PRISMA = createRequire(import.meta.url).resolve('prisma/build/index.js');

try {
  process.loadEnvFile('.env');
} catch {
  // Sin .env: se usan las variables del entorno.
}

const accion = process.argv[2];
const urlTest = process.env.DATABASE_URL_TEST;
if (!urlTest) {
  console.error('Falta DATABASE_URL_TEST en backend/.env.');
  process.exit(1);
}
let nombre;
try {
  nombre = decodeURIComponent(new URL(urlTest).pathname.slice(1));
} catch {
  console.error('DATABASE_URL_TEST no es una URL válida. Revisa backend/.env.');
  process.exit(1);
}
if (!/^[a-z_][a-z0-9_]*$/.test(nombre) || !nombre.endsWith('_test')) {
  console.error('El nombre de la base de pruebas debe terminar en "_test" (solo minúsculas, números y guion bajo).');
  process.exit(1);
}

function ejecutar(cmd, args, env = process.env) {
  const r = spawnSync(cmd, args, { stdio: 'inherit', env });
  if (r.status !== 0) process.exit(r.status ?? 1);
}

function psql(sql) {
  const usuario = process.env.POSTGRES_USER ?? 'safelink';
  const base = process.env.POSTGRES_DB ?? 'safelink';
  const r = spawnSync('docker', ['compose', 'exec', '-T', 'db', 'psql', '-U', usuario, '-d', base, '-v', 'ON_ERROR_STOP=1', '-Atc', sql], { encoding: 'utf8' });
  if (r.status !== 0) {
    console.error(r.stderr || 'No se pudo ejecutar psql en el contenedor db.');
    process.exit(r.status ?? 1);
  }
  return r.stdout.trim();
}

if (accion === 'create') {
  // CREATE DATABASE no admite IF NOT EXISTS: se consulta primero.
  if (psql(`SELECT 1 FROM pg_database WHERE datname = '${nombre}'`) !== '1') {
    psql(`CREATE DATABASE "${nombre}"`);
  }
  console.log(`Base de pruebas "${nombre}" lista.`);
} else if (accion === 'reset') {
  ejecutar(process.execPath, [PRISMA, 'migrate', 'reset', '--force'], { ...process.env, DATABASE_URL: urlTest });
} else if (accion === 'deploy') {
  ejecutar(process.execPath, [PRISMA, 'migrate', 'deploy'], { ...process.env, DATABASE_URL: urlTest });
} else {
  console.error('Uso: node scripts/db-test.mjs create|deploy|reset');
  process.exit(1);
}
