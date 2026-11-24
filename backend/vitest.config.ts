import { defineConfig } from 'vitest/config';

// Las pruebas unitarias no dependen de un .env; las de integración toman
// DATABASE_URL_TEST de backend/.env (y fallan con mensaje claro si falta).
export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    passWithNoTests: true,
    // Archivos uno tras otro: los de integración comparten la base de pruebas y se turnan con
    // un advisory lock; en paralelo, los últimos esperaban el lock dentro de su beforeAll y
    // fallaban por timeout al crecer la suite, aunque el código estuviera bien.
    fileParallelism: false,
    env: {
      NODE_ENV: 'test',
      JWT_SECRET: 'secreto-solo-para-pruebas-minimo-32-caracteres',
      DATABASE_URL: 'postgresql://safelink:safelink@localhost:5433/safelink_test',
    },
  },
});
