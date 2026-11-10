import { defineConfig } from 'vitest/config';

// Las pruebas no dependen de un .env: aquí se definen variables de prueba.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    passWithNoTests: true,
    env: {
      NODE_ENV: 'test',
      JWT_SECRET: 'secreto-solo-para-pruebas-minimo-32-caracteres',
      DATABASE_URL: 'postgresql://safelink:safelink@localhost:5433/safelink_test',
      DATABASE_URL_TEST: 'postgresql://safelink:safelink@localhost:5433/safelink_test',
    },
  },
});
