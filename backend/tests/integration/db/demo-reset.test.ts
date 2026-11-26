// CR-B01: `npm run demo:reset` (scripts/demo-reset.ts) corre como proceso hijo contra safelink_test.
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createRequire } from 'node:module';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { envSchema } from '../../../src/config/env.js';
import { localMinutesOfDay } from '../../../src/domain/shift.js';
import { abrirDb, crearAlerta, crearUsuario, urlPrueba, type ContextoDb } from './helpers.js';

const TSX = createRequire(import.meta.url).resolve('tsx/cli');

/** `entorno` null = sin NODE_ENV (undefined activaría el valor por defecto). */
function correrReset(args: string[], entorno: string | null = 'test') {
  // La URL de la base de pruebas solo viaja en el entorno del hijo; no se imprime.
  const env: NodeJS.ProcessEnv = { ...process.env, DATABASE_URL: urlPrueba() };
  if (entorno === null) delete env['NODE_ENV'];
  else env['NODE_ENV'] = entorno;
  const r = spawnSync(process.execPath, [TSX, 'scripts/demo-reset.ts', ...args], {
    cwd: process.cwd(),
    env,
    encoding: 'utf8',
    timeout: 60_000,
  });
  return { codigo: r.status, salida: `${r.stdout}${r.stderr}` };
}

/** "HH:mm" a `horas` de ahora en la zona de los turnos: sirve para armar un turno que no está vigente. */
function enHoras(horas: number): string {
  const tz = envSchema.pick({ TZ_SHIFTS: true }).parse(process.env).TZ_SHIFTS;
  const m = (localMinutesOfDay(new Date(), tz) + horas * 60) % (24 * 60);
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

let db: ContextoDb;
const centroOriginal = { coverageCenterLat: 18.84, coverageCenterLng: -99.18, coverageRadiusMeters: 4000 };

async function sembrar() {
  const usuario = await crearUsuario(db.prisma);
  const deTurno = await crearUsuario(db.prisma, { role: 'guard' });
  const fueraDeTurno = await crearUsuario(db.prisma, { role: 'guard' });
  // Inicio = fin: turno de 24 h (D1), siempre vigente.
  await db.prisma.guardProfile.create({ data: { userId: deTurno.id, shiftStart: '00:00', shiftEnd: '00:00', ...centroOriginal } });
  await db.prisma.guardProfile.create({
    data: { userId: fueraDeTurno.id, shiftStart: enHoras(3), shiftEnd: enHoras(4), ...centroOriginal },
  });
  const activa = await crearAlerta(db.prisma, usuario.id, { status: 'searching', lat: 18.84, lng: -99.18 });
  await crearAlerta(db.prisma, usuario.id, { status: 'closed', guardId: deTurno.id });
  await db.prisma.alertStatusHistory.create({ data: { alertId: activa.id, toStatus: 'searching' } });
  await db.prisma.alertIgnore.create({ data: { guardId: deTurno.id, alertId: activa.id } });
  await db.prisma.refreshToken.create({
    data: { familyId: randomUUID(), userId: usuario.id, tokenHash: 'a'.repeat(64), expiresAt: new Date(Date.now() + 86_400_000) },
  });
  return { usuario, deTurno, fueraDeTurno };
}

beforeAll(async () => {
  db = await abrirDb();
}, 120_000);

beforeEach(async () => {
  await db.limpiar();
});

afterAll(async () => {
  await db.cerrar();
});

describe('demo:reset (CR-B01)', () => {
  it('borra alertas, historial e "ignorar"; conserva cuentas, perfiles y sesiones', async () => {
    await sembrar();
    const usuariosAntes = await db.prisma.user.count();

    const r = correrReset([]);

    expect(r.codigo, r.salida).toBe(0);
    expect(await db.prisma.alert.count()).toBe(0);
    expect(await db.prisma.alertStatusHistory.count()).toBe(0);
    expect(await db.prisma.alertIgnore.count()).toBe(0);
    expect(await db.prisma.user.count()).toBe(usuariosAntes);
    expect(await db.prisma.guardProfile.count()).toBe(2);
    expect(await db.prisma.refreshToken.count(), 'nadie tiene que volver a iniciar sesión').toBe(1);
  }, 60_000);

  it('sin --center no mueve la cobertura de nadie', async () => {
    const { deTurno } = await sembrar();

    expect(correrReset([]).codigo).toBe(0);

    const perfil = await db.prisma.guardProfile.findUniqueOrThrow({ where: { userId: deTurno.id } });
    expect(perfil).toMatchObject(centroOriginal);
  }, 60_000);

  it('con --center y --radius mueve solo la cobertura de los guardias de turno', async () => {
    const { deTurno, fueraDeTurno } = await sembrar();

    const r = correrReset(['--center', '19.4326,-99.1332', '--radius', '3000']);

    expect(r.codigo, r.salida).toBe(0);
    const movido = await db.prisma.guardProfile.findUniqueOrThrow({ where: { userId: deTurno.id } });
    expect(movido).toMatchObject({ coverageCenterLat: 19.4326, coverageCenterLng: -99.1332, coverageRadiusMeters: 3000 });
    const quieto = await db.prisma.guardProfile.findUniqueOrThrow({ where: { userId: fueraDeTurno.id } });
    expect(quieto).toMatchObject(centroOriginal);
  }, 60_000);

  it('con --center sin --radius conserva el radio que ya tenía', async () => {
    const { deTurno } = await sembrar();

    expect(correrReset(['--center', '19.4326,-99.1332']).codigo).toBe(0);

    const movido = await db.prisma.guardProfile.findUniqueOrThrow({ where: { userId: deTurno.id } });
    expect(movido).toMatchObject({ coverageCenterLat: 19.4326, coverageRadiusMeters: 4000 });
  }, 60_000);

  it.each([['production'], ['staging'], [null]])('se niega a correr con NODE_ENV=%s y no borra nada', async (entorno) => {
    await sembrar();

    const r = correrReset([], entorno);

    expect(r.codigo).not.toBe(0);
    expect(r.codigo).not.toBeNull();
    expect(await db.prisma.alert.count()).toBe(2);
  }, 60_000);

  it.each([
    [['--center', '91,-99.18']],
    [['--center', '18.84,-181']],
    [['--center', 'abc']],
    [['--center', '18.84']],
    [['--center', '18.84,-99.18', '--radius', '10']],
    [['--center', '18.84,-99.18', '--radius', '999999']],
    [['--radius', '3000']],
    [['--otra']],
  ])('rechaza argumentos inválidos %j sin tocar la base', async (args) => {
    await sembrar();

    const r = correrReset(args);

    expect(r.codigo).not.toBe(0);
    expect(await db.prisma.alert.count()).toBe(2);
  }, 60_000);
});
