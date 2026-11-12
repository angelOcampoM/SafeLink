// BE-01 paso 3: la semilla (prisma/seed.ts) corre como proceso hijo contra safelink_test.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import argon2 from 'argon2';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { abrirDb, urlPrueba, type ContextoDb } from './helpers.js';

const TSX = createRequire(import.meta.url).resolve('tsx/cli');
const PASSWORD = 'SafeLink1';

function entornoHijo(entorno: string | undefined): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env, DATABASE_URL: urlPrueba() };
  if (entorno === undefined) delete env['NODE_ENV'];
  else env['NODE_ENV'] = entorno;
  return env;
}

function correrSemilla(entorno: string | undefined) {
  // La URL de la base de pruebas solo viaja en el entorno del hijo; no se imprime.
  const r = spawnSync(process.execPath, [TSX, 'prisma/seed.ts'], {
    cwd: process.cwd(),
    env: entornoHijo(entorno),
    encoding: 'utf8',
    timeout: 120_000,
  });
  return { codigo: r.status, salida: `${r.stdout}${r.stderr}` };
}

function uuidV5(name: string): string {
  const ns = Buffer.from('5afe11c0-0000-4000-8000-000000000001'.replaceAll('-', ''), 'hex');
  const h = createHash('sha1').update(ns).update(name, 'utf8').digest();
  h[6] = ((h[6] ?? 0) & 0x0f) | 0x50;
  h[8] = ((h[8] ?? 0) & 0x3f) | 0x80;
  const x = h.subarray(0, 16).toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`;
}

let db: ContextoDb;

async function foto() {
  const [usuarios, perfiles, alertas] = await Promise.all([
    db.prisma.user.findMany({ orderBy: { email: 'asc' } }),
    db.prisma.guardProfile.count(),
    db.prisma.alert.findMany({ orderBy: { id: 'asc' } }),
  ]);
  return { usuarios, perfiles, alertas };
}

beforeAll(async () => {
  db = await abrirDb();
}, 30_000);

afterAll(async () => {
  await db.cerrar();
});

// Las pruebas dependen del orden: la segunda siembra la base que usan las demás.
describe('Semilla de desarrollo (BE-01 paso 3)', () => {
  it('se niega a correr con NODE_ENV=production: sale con código distinto de 0 y no escribe nada', async () => {
    await db.limpiar();
    const r = correrSemilla('production');
    expect(r.codigo).not.toBe(0);
    expect(r.codigo).not.toBeNull();
    expect(await db.prisma.user.count()).toBe(0);
    expect(await db.prisma.alert.count()).toBe(0);
    expect(await db.prisma.guardProfile.count()).toBe(0);
    expect(await db.prisma.alertStatusHistory.count()).toBe(0);
  }, 60_000);

  it('se niega a correr sin NODE_ENV (debe ser exactamente development o test) y no escribe nada', async () => {
    await db.limpiar();
    const r = correrSemilla(undefined);
    expect(r.codigo).not.toBe(0);
    expect(r.codigo).not.toBeNull();
    expect(await db.prisma.user.count()).toBe(0);
    expect(await db.prisma.alert.count()).toBe(0);
    expect(await db.prisma.guardProfile.count()).toBe(0);
    expect(await db.prisma.alertStatusHistory.count()).toBe(0);
  }, 60_000);

  it.each(['Production', 'staging', ''])('se niega a correr con NODE_ENV="%s"', async (valor) => {
    await db.limpiar();
    const r = correrSemilla(valor);
    expect(r.codigo).not.toBe(0);
    expect(await db.prisma.user.count()).toBe(0);
  }, 60_000);

  it('es idempotente: dos corridas dejan los mismos conteos, ids y datos de cuentas', async () => {
    await db.limpiar();
    const r1 = correrSemilla('test');
    expect(r1.codigo, r1.salida).toBe(0);
    const f1 = await foto();
    const r2 = correrSemilla('test');
    expect(r2.codigo, r2.salida).toBe(0);
    const f2 = await foto();

    for (const f of [f1, f2]) {
      expect(f.usuarios).toHaveLength(44);
      expect(f.perfiles).toBe(8);
      expect(f.alertas).toHaveLength(30);
    }
    expect(f2.usuarios.map((u) => [u.id, u.email, u.role, u.createdAt.getTime()])).toEqual(
      f1.usuarios.map((u) => [u.id, u.email, u.role, u.createdAt.getTime()]),
    );
    expect(f2.alertas.map((a) => a.id)).toEqual(f1.alertas.map((a) => a.id));
    // El historial se reinicia en cada corrida: no se duplica.
    const historial2 = await db.prisma.alertStatusHistory.count();
    expect(historial2).toBeGreaterThanOrEqual(30);
    expect(historial2).toBeLessThanOrEqual(30 * 5);
  }, 240_000);

  it('cuentas demo: correos, roles y estados del front (datos_semilla.dart)', async () => {
    const porCorreo = async (email: string) => db.prisma.user.findUniqueOrThrow({ where: { email } });
    expect((await porCorreo('admin@safelink.mx')).role).toBe('admin');
    expect((await porCorreo('guardia@safelink.mx')).role).toBe('guard');
    expect((await porCorreo('guardia.noche@safelink.mx')).role).toBe('guard');
    const usr = await porCorreo('usuario@safelink.mx');
    expect(usr.role).toBe('protected_user');
    expect(usr.volumeDoubleClickEnabled).toBe(true);
    const bloqueado = await porCorreo('bloqueado@safelink.mx');
    expect(bloqueado.falseAlarmCount).toBe(3);
    expect(bloqueado.blockedUntil).not.toBeNull();

    const roles = await db.prisma.user.groupBy({ by: ['role'], _count: { _all: true } });
    const conteo = Object.fromEntries(roles.map((r) => [r.role, r._count._all]));
    expect(conteo).toEqual({ admin: 1, guard: 8, protected_user: 35 });
  });

  it('grd-5 (Luis Nava) es el único inactivo; todos los correos en minúsculas', async () => {
    const grd5 = await db.prisma.user.findUniqueOrThrow({ where: { email: 'luis.nava@safelink.mx' } });
    expect(grd5.isActive).toBe(false);
    expect(grd5.id).toBe(uuidV5('grd-5'));
    expect(await db.prisma.user.count({ where: { isActive: false } })).toBe(1);
    const todos = await db.prisma.user.findMany({ select: { email: true } });
    expect(todos.every((u) => u.email === u.email.toLowerCase())).toBe(true);
  });

  it('el hash de SafeLink1 verifica con argon2 (una cuenta por rol) y no es la contraseña en claro', async () => {
    for (const email of ['admin@safelink.mx', 'guardia@safelink.mx', 'usuario@safelink.mx']) {
      const u = await db.prisma.user.findUniqueOrThrow({ where: { email }, omit: { passwordHash: false } });
      expect(u.passwordHash).toMatch(/^\$argon2id\$/);
      expect(u.passwordHash).not.toContain(PASSWORD);
      expect(await argon2.verify(u.passwordHash, PASSWORD)).toBe(true);
      expect(await argon2.verify(u.passwordHash, 'otraClave1')).toBe(false);
    }
  });

  it('UUID estables: derivan por v5 de los ids del front', async () => {
    const claves: [string, string][] = [
      ['adm-1', 'admin@safelink.mx'],
      ['grd-1', 'guardia@safelink.mx'],
      ['usr-1', 'usuario@safelink.mx'],
    ];
    for (const [clave, email] of claves) {
      const u = await db.prisma.user.findUniqueOrThrow({ where: { email } });
      expect(u.id).toBe(uuidV5(clave));
      expect(u.id[14]).toBe('5');
    }
    expect(await db.prisma.alert.count({ where: { id: uuidV5('alt-101') } })).toBe(1);
  });

  it('cada alerta tiene historial que empieza con from_status nulo y termina en su estado', async () => {
    expect(await db.prisma.alert.count({ where: { history: { none: {} } } })).toBe(0);
    const alertas = await db.prisma.alert.findMany({ include: { history: { orderBy: { at: 'asc' } } } });
    for (const a of alertas) {
      expect(a.history[0]?.fromStatus).toBeNull();
      expect(a.history[a.history.length - 1]?.toStatus).toBe(a.status);
    }
  });

  it('ningún usuario tiene dos alertas activas; hay alertas en todos los estados sembrados', async () => {
    const dobles = await db.prisma.$queryRawUnsafe<{ user_id: string }[]>(
      `SELECT user_id FROM alerts
       WHERE status IN ('pending_location','searching','in_progress','guard_arrived')
       GROUP BY user_id HAVING count(*) > 1`,
    );
    expect(dobles).toEqual([]);
    for (const s of ['pending_location', 'searching', 'in_progress', 'guard_arrived', 'no_response', 'escalated', 'resolved_by_admin'] as const) {
      expect(await db.prisma.alert.count({ where: { status: s } }), s).toBeGreaterThan(0);
    }
  });

  it('createPrisma omite passwordHash por defecto y solo lo trae con omit: { passwordHash: false }', async () => {
    const sin = await db.prisma.user.findFirst();
    expect(sin).not.toBeNull();
    expect(sin).not.toHaveProperty('passwordHash');
    const lista = await db.prisma.user.findMany({ take: 3 });
    for (const u of lista) expect(u).not.toHaveProperty('passwordHash');
    const con = await db.prisma.user.findFirstOrThrow({ omit: { passwordHash: false } });
    expect(con.passwordHash).toMatch(/^\$argon2id\$/);
  });

  it('el turno nocturno del guardia grd-4 cruza la medianoche (22:00 a 06:00)', async () => {
    const p = await db.prisma.guardProfile.findUniqueOrThrow({ where: { userId: uuidV5('grd-4') } });
    expect([p.shiftStart, p.shiftEnd]).toEqual(['22:00', '06:00']);
  });
});
