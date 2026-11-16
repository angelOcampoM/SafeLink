import { defineConfig } from 'prisma/config';

// Prisma 7 no lee .env por su cuenta: se carga aquí si existe (Node 24).
try {
  process.loadEnvFile('.env');
} catch {
  // Sin .env: se usan las variables ya definidas en el entorno.
}

// DATABASE_URL se lee al correr comandos que tocan la base (migrate, db seed).
// `prisma generate` y `prisma validate` no la necesitan.
export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
    seed: 'tsx prisma/seed.ts',
  },
  datasource: {
    url: process.env['DATABASE_URL'] ?? '',
  },
});
