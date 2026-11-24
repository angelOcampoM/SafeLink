// BE-04 paso 5 · migración 20261118170000_guard_assignment contra PostgreSQL real (D35, D36):
// CHECK alerts_guard_absent_chk e índice único parcial alerts_one_active_per_guard_idx.
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { abrirDb, crearAlerta, crearUsuario, type ContextoDb } from './helpers.js';

let db: ContextoDb;

beforeAll(async () => {
  db = await abrirDb();
}, 120_000);

afterAll(async () => {
  await db.cerrar();
});

beforeEach(async () => {
  await db.limpiar();
});

const guardia = () => crearUsuario(db.prisma, { role: 'guard' });
const dueno = () => crearUsuario(db.prisma);

describe('alerts_guard_absent_chk (D35): sin guardia en pending_location, searching y no_response', () => {
  it.each(['pending_location', 'searching', 'no_response'] as const)('rechaza el estado %s con guard_id', async (status) => {
    const u = await dueno();
    const g = await guardia();
    await expect(crearAlerta(db.prisma, u.id, { status, guardId: g.id })).rejects.toThrow(/alerts_guard_absent_chk/);
  });

  it.each(['pending_location', 'searching', 'no_response'] as const)('acepta el estado %s sin guard_id', async (status) => {
    const u = await dueno();
    await expect(crearAlerta(db.prisma, u.id, { status, guardId: null })).resolves.toBeDefined();
  });

  it.each(['in_progress', 'guard_arrived', 'closed', 'escalated'] as const)(
    'acepta el estado %s con guard_id',
    async (status) => {
      const u = await dueno();
      const g = await guardia();
      const a = await crearAlerta(db.prisma, u.id, {
        status,
        guardId: g.id,
        closedAt: status === 'closed' ? new Date() : null,
      });
      expect(a.guardId).toBe(g.id);
    },
  );

  it('rechaza asignar guardia con UPDATE a una alerta en searching (no solo al crearla)', async () => {
    const u = await dueno();
    const g = await guardia();
    const a = await crearAlerta(db.prisma, u.id, { status: 'searching' });
    await expect(db.prisma.alert.update({ where: { id: a.id }, data: { guardId: g.id } })).rejects.toThrow(
      /alerts_guard_absent_chk/,
    );
  });
});

describe('alerts_one_active_per_guard_idx (D36): un guardia, una alerta en atención', () => {
  const indice = /alerts_one_active_per_guard_idx|unique constraint/i;

  it('rechaza dos alertas in_progress del mismo guardia', async () => {
    const g = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g.id });
    await expect(crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g.id })).rejects.toThrow(indice);
  });

  it('rechaza in_progress + guard_arrived del mismo guardia (en ambos órdenes)', async () => {
    const g = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g.id });
    await expect(crearAlerta(db.prisma, (await dueno()).id, { status: 'guard_arrived', guardId: g.id })).rejects.toThrow(indice);
    const g2 = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'guard_arrived', guardId: g2.id });
    await expect(crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g2.id })).rejects.toThrow(indice);
  });

  it('rechaza pasar a in_progress una segunda alerta del guardia que ya atiende otra (UPDATE)', async () => {
    const g = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'guard_arrived', guardId: g.id });
    const otra = await crearAlerta(db.prisma, (await dueno()).id, { status: 'escalated', guardId: g.id });
    await expect(db.prisma.alert.update({ where: { id: otra.id }, data: { status: 'in_progress' } })).rejects.toThrow(indice);
  });

  it('permite una alerta en curso y varias cerradas/escaladas del mismo guardia', async () => {
    const g = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g.id });
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'closed', guardId: g.id });
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'closed', guardId: g.id });
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'escalated', guardId: g.id });
    expect(await db.prisma.alert.count({ where: { guardId: g.id } })).toBe(4);
  });

  it('permite que dos guardias distintos tengan cada uno su alerta en curso (in_progress y guard_arrived)', async () => {
    const g1 = await guardia();
    const g2 = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g1.id });
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g2.id });
    const g3 = await guardia();
    await crearAlerta(db.prisma, (await dueno()).id, { status: 'guard_arrived', guardId: g3.id });
    expect(await db.prisma.alert.count({ where: { status: { in: ['in_progress', 'guard_arrived'] } } })).toBe(3);
  });

  it('al cerrar la alerta en curso, el guardia queda libre para otra', async () => {
    const g = await guardia();
    const a = await crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g.id });
    await db.prisma.alert.update({ where: { id: a.id }, data: { status: 'closed', closedAt: new Date() } });
    await expect(crearAlerta(db.prisma, (await dueno()).id, { status: 'in_progress', guardId: g.id })).resolves.toBeDefined();
  });
});
