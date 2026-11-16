// BE-01 paso 3: migración 20261112030815_restricciones_extra (defensa en profundidad),
// contra PostgreSQL real (safelink_test). Cada CHECK: caso rechazado y caso válido.
import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { abrirDb, crearAlerta, crearUsuario, type ContextoDb } from './helpers.js';

let db: ContextoDb;

beforeAll(async () => {
  db = await abrirDb();
}, 30_000);

afterAll(async () => {
  await db.cerrar();
});

beforeEach(async () => {
  await db.limpiar();
});

describe('refresh_tokens.token_hash: SHA-256 en hexadecimal minúsculas', () => {
  async function token(tokenHash: string) {
    const u = await crearUsuario(db.prisma);
    return db.prisma.refreshToken.create({
      data: { familyId: randomUUID(), userId: u.id, tokenHash, expiresAt: new Date('2030-01-01T00:00:00Z') },
    });
  }

  it.each([
    ['63 caracteres', 'a'.repeat(63)],
    ['mayúsculas', 'A'.repeat(64)],
    ['no hexadecimal', 'g'.repeat(64)],
  ])('rechaza un hash con %s', async (_caso, hash) => {
    await expect(token(hash)).rejects.toThrow(/refresh_tokens_token_hash_format_chk/);
  });

  it('rechaza un hash de 65 caracteres (lo frena el tipo CHAR(64) antes que el CHECK)', async () => {
    await expect(token('a'.repeat(65))).rejects.toThrow(/too long/i);
  });

  it('acepta 64 caracteres hexadecimales en minúsculas', async () => {
    const hash = '0123456789abcdef'.repeat(4);
    expect((await token(hash)).tokenHash).toBe(hash);
  });
});

describe('alerts: coherencia de guardia y cierre', () => {
  it('rechaza que el guardia sea el mismo dueño de la alerta', async () => {
    const u = await crearUsuario(db.prisma, { role: 'guard' });
    await expect(crearAlerta(db.prisma, u.id, { status: 'in_progress', guardId: u.id })).rejects.toThrow(
      /alerts_guard_not_user_chk/,
    );
  });

  it('acepta un guardia distinto del dueño', async () => {
    const u = await crearUsuario(db.prisma);
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    expect((await crearAlerta(db.prisma, u.id, { status: 'in_progress', guardId: g.id })).guardId).toBe(g.id);
  });

  it.each(['in_progress', 'guard_arrived', 'closed'] as const)('rechaza el estado %s sin guardia', async (status) => {
    const u = await crearUsuario(db.prisma);
    // Se usa prisma directo: el helper asignaría un guardia por su cuenta.
    await expect(
      db.prisma.alert.create({
        data: { userId: u.id, status, triggerMethod: 'tap', triggeredAt: new Date(), closedAt: new Date() },
      }),
    ).rejects.toThrow(/alerts_guard_required_chk/);
  });

  it.each(['pending_location', 'searching', 'no_response', 'escalated', 'resolved_by_admin'] as const)(
    'acepta el estado %s sin guardia',
    async (status) => {
      const u = await crearUsuario(db.prisma);
      const closedAt = status === 'resolved_by_admin' ? new Date() : null;
      await expect(
        db.prisma.alert.create({ data: { userId: u.id, status, triggerMethod: 'tap', triggeredAt: new Date(), closedAt } }),
      ).resolves.toBeDefined();
    },
  );

  it.each(['closed', 'resolved_by_admin'] as const)('rechaza el estado %s sin closed_at', async (status) => {
    const u = await crearUsuario(db.prisma);
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    await expect(
      db.prisma.alert.create({
        data: { userId: u.id, status, triggerMethod: 'tap', triggeredAt: new Date(), guardId: g.id },
      }),
    ).rejects.toThrow(/alerts_closed_at_required_chk/);
  });

  it.each(['closed', 'resolved_by_admin'] as const)('acepta el estado %s con closed_at', async (status) => {
    const u = await crearUsuario(db.prisma);
    const a = await crearAlerta(db.prisma, u.id, { status });
    expect(a.closedAt).not.toBeNull();
  });

  it('cerrar una alerta existente sin closed_at se rechaza', async () => {
    const u = await crearUsuario(db.prisma);
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    const a = await crearAlerta(db.prisma, u.id, { status: 'in_progress', guardId: g.id });
    await expect(db.prisma.alert.update({ where: { id: a.id }, data: { status: 'closed' } })).rejects.toThrow(
      /alerts_closed_at_required_chk/,
    );
  });
});

describe('alerts.photo_key: UUID en minúsculas, nunca una ruta', () => {
  it.each([
    ['ruta local', '/data/user/0/foto.jpg'],
    ['UUID en mayúsculas', 'ABCDEF01-2345-4678-89AB-CDEF01234567'],
    ['UUID sin guiones', 'abcdef0123454678'.padEnd(32, '0')],
    ['cadena vacía', ''],
    ['UUID con sufijo', `${randomUUID()}.jpg`],
  ])('rechaza photo_key: %s', async (_caso, photoKey) => {
    const u = await crearUsuario(db.prisma);
    await expect(crearAlerta(db.prisma, u.id, { photoKey })).rejects.toThrow(/alerts_photo_key_format_chk/);
  });

  it('acepta un UUID en minúsculas y acepta nulo', async () => {
    const u1 = await crearUsuario(db.prisma);
    const u2 = await crearUsuario(db.prisma);
    const llave = randomUUID();
    expect((await crearAlerta(db.prisma, u1.id, { photoKey: llave })).photoKey).toBe(llave);
    expect((await crearAlerta(db.prisma, u2.id, { photoKey: null })).photoKey).toBeNull();
  });
});

describe('topes de longitud en texto libre', () => {
  it('users.name: rechaza 201 y acepta 200 caracteres', async () => {
    await expect(crearUsuario(db.prisma, { name: 'n'.repeat(201) })).rejects.toThrow(/users_name_len_chk/);
    await expect(crearUsuario(db.prisma, { name: 'n'.repeat(200) })).resolves.toBeDefined();
  });

  it('users.email: rechaza 255 y acepta 254 caracteres', async () => {
    const sufijo = '@prueba.test';
    await expect(crearUsuario(db.prisma, { email: 'a'.repeat(255 - sufijo.length) + sufijo })).rejects.toThrow(
      /users_email_len_chk/,
    );
    await expect(crearUsuario(db.prisma, { email: 'a'.repeat(254 - sufijo.length) + sufijo })).resolves.toBeDefined();
  });

  it('users.phone: rechaza 31 y acepta 30 caracteres', async () => {
    await expect(crearUsuario(db.prisma, { phone: '7'.repeat(31) })).rejects.toThrow(/users_phone_len_chk/);
    await expect(crearUsuario(db.prisma, { phone: '7'.repeat(30) })).resolves.toBeDefined();
  });

  it('guard_profiles.zone: rechaza 101, acepta 100 y acepta nulo', async () => {
    const crear = async (zone: string | null) => {
      const g = await crearUsuario(db.prisma, { role: 'guard' });
      return db.prisma.guardProfile.create({ data: { userId: g.id, shiftStart: '08:00', shiftEnd: '16:00', zone } });
    };
    await expect(crear('z'.repeat(101))).rejects.toThrow(/guard_profiles_zone_len_chk/);
    await expect(crear('z'.repeat(100))).resolves.toBeDefined();
    await expect(crear(null)).resolves.toBeDefined();
  });
});
