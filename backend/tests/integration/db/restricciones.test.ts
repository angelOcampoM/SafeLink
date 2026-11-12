// BE-01 paso 3: CHECKs, índice único parcial, llaves foráneas y valores por defecto
// del modelo, contra PostgreSQL real (safelink_test). Reglas D1, D15, D17, D18.
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { abrirDb, crearAlerta, crearUsuario, correoUnico, type ContextoDb } from './helpers.js';

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

describe('alerts: coordenadas y rumbo (D17)', () => {
  it.each([360, -1, 1000])('rechaza heading %i', async (heading) => {
    const u = await crearUsuario(db.prisma);
    await expect(crearAlerta(db.prisma, u.id, { heading })).rejects.toThrow(/alerts_heading_chk/);
  });

  it.each([0, 1, 359])('acepta heading %i', async (heading) => {
    const u = await crearUsuario(db.prisma);
    const a = await crearAlerta(db.prisma, u.id, { heading });
    expect(a.heading).toBe(heading);
  });

  it('acepta heading nulo', async () => {
    const u = await crearUsuario(db.prisma);
    expect((await crearAlerta(db.prisma, u.id)).heading).toBeNull();
  });

  it.each([91, -91])('rechaza lat %i', async (lat) => {
    const u = await crearUsuario(db.prisma);
    await expect(crearAlerta(db.prisma, u.id, { lat, lng: 0 })).rejects.toThrow(/alerts_lat_chk/);
  });

  it.each([181, -181])('rechaza lng %i', async (lng) => {
    const u = await crearUsuario(db.prisma);
    await expect(crearAlerta(db.prisma, u.id, { lat: 0, lng })).rejects.toThrow(/alerts_lng_chk/);
  });

  it('acepta los extremos lat 90/-90 y lng 180/-180', async () => {
    const u1 = await crearUsuario(db.prisma);
    const u2 = await crearUsuario(db.prisma);
    await expect(crearAlerta(db.prisma, u1.id, { lat: 90, lng: 180 })).resolves.toBeDefined();
    await expect(crearAlerta(db.prisma, u2.id, { lat: -90, lng: -180 })).resolves.toBeDefined();
  });

  it('rechaza admin_note de más de 1000 caracteres y acepta 1000', async () => {
    const u = await crearUsuario(db.prisma);
    await expect(crearAlerta(db.prisma, u.id, { status: 'closed', adminNote: 'x'.repeat(1001) })).rejects.toThrow(
      /alerts_admin_note_len_chk/,
    );
    await expect(crearAlerta(db.prisma, u.id, { status: 'closed', adminNote: 'x'.repeat(1000) })).resolves.toBeDefined();
  });
});

describe('users: correo y falsas alarmas (D18)', () => {
  it('rechaza un correo con mayúsculas', async () => {
    await expect(crearUsuario(db.prisma, { email: 'Mayus@Prueba.test' })).rejects.toThrow(/users_email_lowercase_chk/);
  });

  it('rechaza un correo duplicado (unicidad)', async () => {
    const email = correoUnico('dup');
    await crearUsuario(db.prisma, { email });
    await expect(crearUsuario(db.prisma, { email })).rejects.toThrow(/Unique constraint|users_email_key|duplicate/i);
  });

  it('rechaza false_alarm_count negativo y acepta 0', async () => {
    await expect(crearUsuario(db.prisma, { falseAlarmCount: -1 })).rejects.toThrow(/users_false_alarm_count_chk/);
    await expect(crearUsuario(db.prisma, { falseAlarmCount: 0 })).resolves.toBeDefined();
  });

  it('valores por defecto: doble clic de volumen apagado, 0 falsas alarmas, activo', async () => {
    const u = await crearUsuario(db.prisma);
    expect(u.volumeDoubleClickEnabled).toBe(false);
    expect(u.falseAlarmCount).toBe(0);
    expect(u.isActive).toBe(true);
    expect(u.blockedUntil).toBeNull();
    expect(u.createdAt).toBeInstanceOf(Date);
    expect(u.id).toMatch(/^[0-9a-f-]{36}$/);
  });
});

describe('guard_profiles: turno y cobertura (D1)', () => {
  async function perfil(shiftStart: string, shiftEnd: string, extra: Record<string, number> = {}) {
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    return db.prisma.guardProfile.create({ data: { userId: g.id, shiftStart, shiftEnd, ...extra } });
  }

  it.each([
    ['24:00', '06:00'],
    ['7:00', '15:00'],
    ['07:60', '15:00'],
    ['08:00', '24:00'],
    ['08:00', '8:00'],
    ['ab:cd', '15:00'],
  ])('rechaza turno %s a %s', async (ini, fin) => {
    await expect(perfil(ini, fin)).rejects.toThrow(/guard_profiles_shift_format_chk/);
  });

  it.each([
    ['23:59', '00:00'],
    ['00:00', '23:59'],
    ['22:00', '06:00'],
    ['08:00', '08:00'],
  ])('acepta turno %s a %s (incluye cruce de medianoche y 24 h)', async (ini, fin) => {
    const p = await perfil(ini, fin);
    expect(p.shiftStart).toBe(ini);
    expect(p.shiftEnd).toBe(fin);
  });

  it('rechaza radio de cobertura 0 o negativo y coordenadas fuera de rango', async () => {
    await expect(perfil('08:00', '16:00', { coverageRadiusMeters: 0 })).rejects.toThrow(/guard_profiles_coverage_chk/);
    await expect(perfil('08:00', '16:00', { coverageRadiusMeters: -5 })).rejects.toThrow(/guard_profiles_coverage_chk/);
    await expect(perfil('08:00', '16:00', { coverageCenterLat: 91 })).rejects.toThrow(/guard_profiles_coverage_chk/);
    await expect(perfil('08:00', '16:00', { coverageCenterLng: -181 })).rejects.toThrow(/guard_profiles_coverage_chk/);
    await expect(perfil('08:00', '16:00', { lastLocationLat: -91 })).rejects.toThrow(/guard_profiles_coverage_chk/);
    await expect(perfil('08:00', '16:00', { lastLocationLng: 181 })).rejects.toThrow(/guard_profiles_coverage_chk/);
  });

  it('acepta radio 1 y cobertura opcional (nula)', async () => {
    await expect(perfil('08:00', '16:00', { coverageRadiusMeters: 1 })).resolves.toBeDefined();
    const p = await perfil('08:00', '16:00');
    expect(p.coverageRadiusMeters).toBeNull();
  });
});

describe('alerts: una sola alerta activa por usuario (D15, índice parcial)', () => {
  const activos = ['pending_location', 'searching', 'in_progress', 'guard_arrived'] as const;

  it.each(activos)('rechaza una segunda alerta activa si la primera está en %s', async (estado) => {
    const u = await crearUsuario(db.prisma);
    await crearAlerta(db.prisma, u.id, { status: estado });
    for (const segundo of activos) {
      await expect(crearAlerta(db.prisma, u.id, { status: segundo })).rejects.toThrow(
        /alerts_one_active_per_user_idx|Unique constraint/,
      );
    }
  });

  it('permite varias alertas no activas junto a una activa', async () => {
    const u = await crearUsuario(db.prisma);
    await crearAlerta(db.prisma, u.id, { status: 'searching' });
    await crearAlerta(db.prisma, u.id, { status: 'closed' });
    await crearAlerta(db.prisma, u.id, { status: 'closed' });
    await crearAlerta(db.prisma, u.id, { status: 'escalated' });
    await crearAlerta(db.prisma, u.id, { status: 'no_response' });
    await crearAlerta(db.prisma, u.id, { status: 'resolved_by_admin' });
    expect(await db.prisma.alert.count({ where: { userId: u.id } })).toBe(6);
  });

  it('otro usuario sí puede tener su propia alerta activa', async () => {
    const a = await crearUsuario(db.prisma);
    const b = await crearUsuario(db.prisma);
    await crearAlerta(db.prisma, a.id, { status: 'searching' });
    await expect(crearAlerta(db.prisma, b.id, { status: 'searching' })).resolves.toBeDefined();
  });

  it('al cerrar la activa, el usuario puede crear otra', async () => {
    const u = await crearUsuario(db.prisma);
    const primera = await crearAlerta(db.prisma, u.id, { status: 'searching' });
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    await db.prisma.alert.update({ where: { id: primera.id }, data: { status: 'closed', guardId: g.id, closedAt: new Date() } });
    await expect(crearAlerta(db.prisma, u.id, { status: 'pending_location' })).resolves.toBeDefined();
  });

  it('rechaza reactivar una alerta cuando ya hay otra activa del mismo usuario', async () => {
    const u = await crearUsuario(db.prisma);
    const vieja = await crearAlerta(db.prisma, u.id, { status: 'escalated' });
    await crearAlerta(db.prisma, u.id, { status: 'searching' });
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    await expect(
      db.prisma.alert.update({ where: { id: vieja.id }, data: { status: 'in_progress', guardId: g.id } }),
    ).rejects.toThrow(/alerts_one_active_per_user_idx|Unique constraint/);
  });

  it('la doble creación concurrente deja exactamente una activa', async () => {
    const u = await crearUsuario(db.prisma);
    const r = await Promise.allSettled([
      crearAlerta(db.prisma, u.id, { status: 'searching' }),
      crearAlerta(db.prisma, u.id, { status: 'searching' }),
    ]);
    expect(r.filter((x) => x.status === 'fulfilled')).toHaveLength(1);
    expect(r.filter((x) => x.status === 'rejected')).toHaveLength(1);
  });
});

describe('alerts: llaves foráneas y valores por defecto', () => {
  it('no se puede borrar un usuario con alertas (RESTRICT)', async () => {
    const u = await crearUsuario(db.prisma);
    await crearAlerta(db.prisma, u.id, { status: 'closed' });
    await expect(db.prisma.user.delete({ where: { id: u.id } })).rejects.toThrow();
    expect(await db.prisma.user.count({ where: { id: u.id } })).toBe(1);
  });

  it('no se puede borrar un guardia asignado a una alerta (RESTRICT)', async () => {
    const u = await crearUsuario(db.prisma);
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    await crearAlerta(db.prisma, u.id, { status: 'in_progress', guardId: g.id });
    await expect(db.prisma.user.delete({ where: { id: g.id } })).rejects.toThrow();
  });

  it('rechaza una alerta de un usuario inexistente', async () => {
    await expect(crearAlerta(db.prisma, '00000000-0000-4000-8000-000000000000')).rejects.toThrow();
  });

  it('borrar una alerta borra su historial y sus ignores (CASCADE)', async () => {
    const u = await crearUsuario(db.prisma);
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    const a = await crearAlerta(db.prisma, u.id);
    await db.prisma.alertStatusHistory.create({ data: { alertId: a.id, fromStatus: null, toStatus: 'searching', actorId: u.id } });
    await db.prisma.alertIgnore.create({ data: { alertId: a.id, guardId: g.id } });
    await db.prisma.alert.delete({ where: { id: a.id } });
    expect(await db.prisma.alertStatusHistory.count()).toBe(0);
    expect(await db.prisma.alertIgnore.count()).toBe(0);
    expect(await db.prisma.user.count()).toBe(2);
  });

  it('un guardia no puede ignorar dos veces la misma alerta (llave compuesta)', async () => {
    const u = await crearUsuario(db.prisma);
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    const a = await crearAlerta(db.prisma, u.id);
    await db.prisma.alertIgnore.create({ data: { alertId: a.id, guardId: g.id } });
    await expect(db.prisma.alertIgnore.create({ data: { alertId: a.id, guardId: g.id } })).rejects.toThrow();
  });

  it('borrar el actor del historial deja actor_id en nulo (SET NULL)', async () => {
    const u = await crearUsuario(db.prisma);
    const admin = await crearUsuario(db.prisma, { role: 'admin' });
    const a = await crearAlerta(db.prisma, u.id);
    const h = await db.prisma.alertStatusHistory.create({ data: { alertId: a.id, toStatus: 'searching', actorId: admin.id } });
    await db.prisma.user.delete({ where: { id: admin.id } });
    expect((await db.prisma.alertStatusHistory.findUniqueOrThrow({ where: { id: h.id } })).actorId).toBeNull();
  });

  it('borrar un usuario con perfil de guardia borra el perfil (CASCADE) si no tiene alertas', async () => {
    const g = await crearUsuario(db.prisma, { role: 'guard' });
    await db.prisma.guardProfile.create({ data: { userId: g.id, shiftStart: '08:00', shiftEnd: '16:00' } });
    await db.prisma.user.delete({ where: { id: g.id } });
    expect(await db.prisma.guardProfile.count()).toBe(0);
  });

  it('defaults de alerta: received_at y status_changed_at con valor, evidencia completa', async () => {
    const u = await crearUsuario(db.prisma);
    const a = await crearAlerta(db.prisma, u.id);
    expect(a.receivedAt).toBeInstanceOf(Date);
    expect(a.statusChangedAt).toBeInstanceOf(Date);
    expect(a.createdAt).toBeInstanceOf(Date);
    expect(a.evidenceIncomplete).toBe(false);
    expect(a.guardId).toBeNull();
    expect(a.photoKey).toBeNull();
  });
});
