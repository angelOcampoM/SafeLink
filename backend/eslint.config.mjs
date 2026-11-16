import eslint from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist', 'coverage', 'node_modules', 'src/generated'] },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['scripts/**/*.mjs'],
    languageOptions: { globals: { process: 'readonly', console: 'readonly', URL: 'readonly' } },
  },
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/ban-ts-comment': 'error',
    },
  },
  // Seguridad: passwordHash solo se lee en el módulo de auth y el cliente Prisma solo se crea en src/db.
  {
    files: ['**/*.ts', '**/*.mjs'],
    ignores: ['src/modules/auth/**', 'src/db/**', 'tests/**'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: "Property[key.name=/^(select|omit)$/] Property[key.name='passwordHash']",
          message: 'passwordHash solo puede pedirse con select/omit dentro de src/modules/auth/.',
        },
        {
          selector: "Property[key.name=/^(select|omit)$/] Property[key.value='passwordHash']",
          message: 'passwordHash solo puede pedirse con select/omit dentro de src/modules/auth/.',
        },
        {
          selector: "NewExpression[callee.name='PrismaClient']",
          message: 'Crea el cliente con createPrisma() (src/db/prisma.ts); new PrismaClient solo vive en src/db/.',
        },
      ],
    },
  },
);
