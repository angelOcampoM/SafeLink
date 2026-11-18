// BE-04 paso 10 (D43): si buildApp lanza por la cuenta de servicio FCM, server.ts imprime solo el
// mensaje (sin stack ni contenido del JSON), desconecta Prisma y termina con código 1.
// Se ejecuta server.ts real en un proceso hijo con node + tsx (ya es devDependency del repo). No se
// carga backend/.env: el entorno del hijo se arma desde cero. Nunca hay red ni credenciales reales.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';

const backendDir = resolve(import.meta.dirname, '..', '..');
const dir = mkdtempSync(join(tmpdir(), 'safelink-server-test-'));
afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

function arrancar(file: string) {
  return spawnSync(process.execPath, ['--import', 'tsx', 'src/server.ts'], {
    cwd: backendDir,
    encoding: 'utf8',
    timeout: 60_000,
    env: {
      PATH: process.env.PATH ?? '',
      SystemRoot: process.env.SystemRoot ?? '',
      NODE_ENV: 'test',
      JWT_SECRET: 'secreto-solo-para-pruebas-minimo-32-caracteres',
      DATABASE_URL: 'postgresql://safelink:safelink@127.0.0.1:1/safelink_inexistente',
      PORT: '3999',
      PUSH_PROVIDER: 'fcm',
      FCM_PROJECT_ID: 'proyecto-prueba',
      FCM_SERVICE_ACCOUNT_FILE: file,
    },
  });
}

describe('server.ts con PUSH_PROVIDER=fcm y cuenta de servicio inválida (D43)', () => {
  it('archivo inexistente: termina con código 1 y solo imprime el mensaje, sin stack', () => {
    const r = arrancar(join(dir, 'no-existe.json'));
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('No se pudo iniciar la API: FCM_SERVICE_ACCOUNT_FILE: no se pudo leer el archivo');
    expect(r.stderr).not.toMatch(/\n\s+at /);
    expect(r.stderr).not.toContain('node:internal');
    expect(r.stdout).toBe('');
  }, 90_000);

  it('JSON corrupto: el contenido del archivo no aparece en la salida', () => {
    const file = join(dir, 'corrupto.json');
    writeFileSync(file, '{ CONTENIDO-SECRETO-SERVIDOR');
    const r = arrancar(file);
    expect(r.status).toBe(1);
    expect(r.stderr).toContain('No se pudo iniciar la API: FCM_SERVICE_ACCOUNT_FILE: el archivo no es un JSON válido');
    expect(`${r.stdout}${r.stderr}`).not.toContain('CONTENIDO-SECRETO-SERVIDOR');
    expect(r.stderr).not.toMatch(/\n\s+at /);
  }, 90_000);
});
