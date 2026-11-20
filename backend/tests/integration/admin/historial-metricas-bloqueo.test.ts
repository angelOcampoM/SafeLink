// BE-07 · Historial con filtros (A-05), métricas generales (A-06) y por guardia (A-07),
// listado de usuarios y desbloqueo a mano (A-08), contra la base de pruebas.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { USER_KEYS, crearEntorno, login, type Entorno } from '../auth/helpers.js';

const API = '/api/v1';
const TZ = 'America/Mexico_City'; // el TZ_SHIFTS por defecto; UTC-6 todo el año

let env: Entorno;
let adminToken = '';
/** Guardia con zona asignada, para `alertsByZone` y A-07. */
let guardiaConZona = '';

beforeAll(async () => {
  env = await crearEntorno();
  adminToken = (await login(env.app, env.usuarios.admin.email)).body.data.accessToken as string;
  guardiaConZona = env.usuarios.guardia.id;
  await env.prisma.guardProfile.create({
    data: { userId: guardiaConZona, shiftStart: '08:00', shiftEnd: '16:00', zone: 'Lomas' },
  });
}, 120_000);

afterAll(async () => {
  await env.cerrar();
});

/** Cada prueba parte de cero alertas: el historial es acumulativo por naturaleza. */
beforeEach(async () => {
  await env.prisma.alertStatusHistory.deleteMany();
  await env.prisma.alertIgnore.deleteMany();
  await env.prisma.alert.deleteMany();
  await env.prisma.user.update({
    where: { id: env.usuarios.bloqueado.id },
    data: { falseAlarmCount: 3, blockedUntil: new Date('2099-01-01T00:00:00Z') },
  });
});

const conToken = (token = adminToken) => ({ Authorization: `Bearer ${token}` });

/**
 * Estados en los que la base EXIGE que no haya guardia y en los que exige que sí lo haya
 * (CHECK alerts_guard_absent_chk y alerts_guard_required_chk de las migraciones; Prisma no
 * los expresa, así que una alerta de prueba incoherente revienta contra Postgres y no al
 * escribirla). `closed` y `resolved_by_admin` exigen además `closedAt`.
 */
const SIN_GUARDIA = ['pending_location', 'searching', 'no_response'];
const CON_GUARDIA = ['in_progress', 'guard_arrived', 'closed'];
const CON_CIERRE = ['closed', 'resolved_by_admin'];

/**
 * Crea una alerta coherente con esos CHECK y devuelve su id.
 *
 * Si una prueba pide una combinación que la base prohíbe (por ejemplo `closed` sin guardia)
 * se falla aquí con un mensaje claro, en vez de dejar que Postgres conteste con el nombre de
 * la restricción desde dentro de Prisma.
 */
async function crearAlerta(datos: {
  receivedAt: string;
  status?: string;
  guardId?: string | null;
  userId?: string;
  acceptedAt?: string;
  arrivedAt?: string;
  escalationReason?: string;
}): Promise<string> {
  const status = datos.status ?? 'closed';
  const guardId = datos.guardId === undefined ? guardiaConZona : datos.guardId;

  if (SIN_GUARDIA.includes(status) && guardId !== null) {
    throw new Error(`La base no permite guardia en estado ${status}`);
  }
  if (CON_GUARDIA.includes(status) && guardId === null) {
    throw new Error(`La base exige guardia en estado ${status}`);
  }

  const a = await env.prisma.alert.create({
    data: {
      userId: datos.userId ?? env.usuarios.protegido.id,
      guardId,
      status: status as 'closed',
      triggerMethod: 'shake', // el enum llama 'shake' al doble clic de volumen (CodigosJson.metodo)
      triggeredAt: new Date(datos.receivedAt),
      receivedAt: new Date(datos.receivedAt),
      statusChangedAt: new Date(datos.receivedAt),
      acceptedAt: datos.acceptedAt ? new Date(datos.acceptedAt) : null,
      arrivedAt: datos.arrivedAt ? new Date(datos.arrivedAt) : null,
      // Una alerta cerrada sin fecha de cierre no existe en la base.
      closedAt: CON_CIERRE.includes(status)
        ? new Date(datos.arrivedAt ?? datos.acceptedAt ?? datos.receivedAt)
        : null,
      escalationReason: (datos.escalationReason ?? null) as null,
    },
  });
  return a.id;
}

const historial = (query = '') =>
  request(env.app.server).get(`${API}/admin/alerts${query}`).set(conToken());

const metricas = (query = '') =>
  request(env.app.server).get(`${API}/admin/metrics${query}`).set(conToken());

// ── A-05 · GET /admin/alerts ──────────────────────────────────────────

describe('GET /admin/alerts', () => {
  it('sin filtros devuelve todas, de la más reciente a la más antigua por receivedAt', async () => {
    const vieja = await crearAlerta({ receivedAt: '2026-03-01T12:00:00Z' });
    const nueva = await crearAlerta({ receivedAt: '2026-03-05T12:00:00Z' });
    const media = await crearAlerta({ receivedAt: '2026-03-03T12:00:00Z' });

    const res = await historial();
    expect(res.status).toBe(200);
    expect((res.body.data as { id: string }[]).map((a) => a.id)).toEqual([nueva, media, vieja]);
  });

  it('incluye las alertas activas, no solo las cerradas (contrato 5)', async () => {
    // Sin guardia: la base lo exige en `searching` (alerts_guard_absent_chk).
    await crearAlerta({ receivedAt: '2026-03-01T12:00:00Z', status: 'searching', guardId: null });
    const res = await historial();
    expect(res.body.data).toHaveLength(1);
    expect((res.body.data as { status: string }[])[0]?.status).toBe('searching');
  });

  it('from es inclusivo y to exclusivo (contrato 4.8)', async () => {
    await crearAlerta({ receivedAt: '2026-03-01T00:00:00Z' }); // justo en from: entra
    await crearAlerta({ receivedAt: '2026-03-02T00:00:00Z' }); // justo en to: NO entra
    const res = await historial('?from=2026-03-01T00:00:00Z&to=2026-03-02T00:00:00Z');
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(1);
  });

  it('una fecha sin zona se lee en la zona de los turnos, no en la del servidor', async () => {
    // Las 23:00 UTC del 18 son las 17:00 del 18 en Cuernavaca: dentro del día 18.
    const delDia18 = await crearAlerta({ receivedAt: '2026-11-18T23:00:00Z' });
    // Las 07:00 UTC del 19 son la 01:00 del 19 allá: fuera del día 18.
    await crearAlerta({ receivedAt: '2026-11-19T07:00:00Z' });

    // Así manda el front el día 18 completo: medianoche local a medianoche local del día siguiente.
    const res = await historial('?from=2026-11-18T00:00:00.000&to=2026-11-19T00:00:00.000');
    expect(res.status).toBe(200);
    expect((res.body.data as { id: string }[]).map((a) => a.id)).toEqual([delDia18]);
  });

  it('filtra por guardia, por usuario y por estado, y los combina', async () => {
    const mia = await crearAlerta({ receivedAt: '2026-03-01T12:00:00Z', status: 'escalated' });
    // `searching` es un estado en el que la base SÍ permite que no haya guardia.
    await crearAlerta({ receivedAt: '2026-03-02T12:00:00Z', status: 'searching', guardId: null });
    await crearAlerta({ receivedAt: '2026-03-03T12:00:00Z', status: 'closed' });

    const porGuardia = await historial(`?guardId=${guardiaConZona}`);
    expect(porGuardia.body.data).toHaveLength(2);

    const porEstado = await historial('?status=escalated');
    expect((porEstado.body.data as { id: string }[]).map((a) => a.id)).toEqual([mia]);

    const combinado = await historial(`?guardId=${guardiaConZona}&status=escalated`);
    expect((combinado.body.data as { id: string }[]).map((a) => a.id)).toEqual([mia]);

    const porUsuario = await historial(`?userId=${env.usuarios.guardia.id}`);
    expect(porUsuario.body.data).toEqual([]);
  });

  it('un estado desconocido es 400 INVALID_STATE, no una lista vacía', async () => {
    const res = await historial('?status=inventado');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
    expect(res.body.error.message).toBe('El estado no es válido');
  });

  it('una fecha imposible es 400, no un rango distinto al pedido', async () => {
    const res = await historial('?from=2026-02-31T00:00:00');
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('La fecha no es válida');
  });

  it('el admin ve la alerta completa: teléfono y ubicación incluidos (D23)', async () => {
    await crearAlerta({ receivedAt: '2026-03-01T12:00:00Z' });
    const res = await historial();
    const alerta = (res.body.data as Record<string, unknown>[])[0];
    expect(alerta).toHaveProperty('userPhone', '7771234567');
    expect(Object.keys(alerta ?? {})).toContain('etaSeconds');
  });
});

// ── A-06 · GET /admin/metrics ─────────────────────────────────────────

describe('GET /admin/metrics', () => {
  const CLAVES = [
    'alertsByHour',
    'alertsByZone',
    'avgAcceptanceSeconds',
    'avgArrivalSeconds',
    'confirmedCloseRate',
    'noResponseRate',
    'totalAlerts',
  ];

  it('sin alertas: todo en 0, 24 horas en cero y ninguna zona', async () => {
    const res = await metricas();
    expect(res.status).toBe(200);
    expect(Object.keys(res.body.data as object).sort()).toEqual(CLAVES);
    expect(res.body.data).toMatchObject({
      totalAlerts: 0,
      avgAcceptanceSeconds: 0,
      avgArrivalSeconds: 0,
      noResponseRate: 0,
      confirmedCloseRate: 0,
      alertsByZone: [],
    });
    expect(res.body.data.alertsByHour).toEqual(Array.from({ length: 24 }, () => 0));
  });

  it('cuenta, promedia y agrupa las alertas del periodo', async () => {
    await crearAlerta({
      receivedAt: '2026-03-01T18:00:00Z',
      acceptedAt: '2026-03-01T18:00:30Z',
      arrivedAt: '2026-03-01T18:05:30Z',
      status: 'closed',
    });
    await crearAlerta({
      receivedAt: '2026-03-01T19:00:00Z',
      status: 'escalated',
      escalationReason: 'no_response',
    });

    const res = await metricas();
    expect(res.body.data).toMatchObject({
      totalAlerts: 2,
      avgAcceptanceSeconds: 30, // solo la que fue aceptada
      avgArrivalSeconds: 300,
      noResponseRate: 0.5,
      confirmedCloseRate: 0.5,
      alertsByZone: [{ zone: 'Lomas', count: 2 }],
    });
  });

  it('alertsByHour usa la hora de la zona de los turnos', async () => {
    await crearAlerta({ receivedAt: '2026-01-15T02:00:00Z' }); // 20:00 del día 14 en TZ
    const res = await metricas();
    expect(res.body.data.alertsByHour[20]).toBe(1);
    expect(res.body.data.alertsByHour[2]).toBe(0);
  });

  it('una alerta sin guardia cuenta en "Sin zona asignada"', async () => {
    await crearAlerta({ receivedAt: '2026-03-01T18:00:00Z', status: 'searching', guardId: null });
    const res = await metricas();
    expect(res.body.data.alertsByZone).toEqual([{ zone: 'Sin zona asignada', count: 1 }]);
  });

  it('respeta el periodo: lo de fuera no cuenta', async () => {
    await crearAlerta({ receivedAt: '2026-03-01T18:00:00Z' });
    await crearAlerta({ receivedAt: '2026-04-01T18:00:00Z' });
    const res = await metricas('?from=2026-03-01T00:00:00Z&to=2026-04-01T00:00:00Z');
    expect(res.body.data.totalAlerts).toBe(1);
  });

  it('no acepta los filtros del historial: las métricas son del periodo', async () => {
    const res = await metricas('?status=closed');
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('INVALID_STATE');
  });
});

// ── A-07 · GET /admin/metrics/guards/:id ──────────────────────────────

describe('GET /admin/metrics/guards/:id', () => {
  const porGuardia = (id: string, query = '') =>
    request(env.app.server).get(`${API}/admin/metrics/guards/${id}${query}`).set(conToken());

  it('cuenta solo las alertas de ese guardia', async () => {
    await crearAlerta({
      receivedAt: '2026-03-01T18:00:00Z',
      acceptedAt: '2026-03-01T18:00:20Z',
      arrivedAt: '2026-03-01T18:04:20Z',
    });
    await crearAlerta({ receivedAt: '2026-03-02T18:00:00Z', status: 'searching', guardId: null });

    const res = await porGuardia(guardiaConZona);
    expect(res.status).toBe(200);
    expect(Object.keys(res.body.data as object).sort()).toEqual([
      'attendedCount',
      'avgAcceptanceSeconds',
      'avgArrivalSeconds',
      'escalatedCount',
    ]);
    expect(res.body.data).toMatchObject({
      attendedCount: 1,
      avgAcceptanceSeconds: 20,
      avgArrivalSeconds: 240,
      escalatedCount: 0,
    });
  });

  it('cuenta las escaladas del guardia', async () => {
    await crearAlerta({
      receivedAt: '2026-03-01T18:00:00Z',
      status: 'escalated',
      escalationReason: 'no_confirmation',
    });
    const res = await porGuardia(guardiaConZona);
    expect(res.body.data.escalatedCount).toBe(1);
  });

  it('un id que no es de un guardia es NOT_FOUND, no un guardia con ceros', async () => {
    const res = await porGuardia(env.usuarios.protegido.id);
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('un id que no existe también es NOT_FOUND', async () => {
    const res = await porGuardia('3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11');
    expect(res.status).toBe(404);
  });

  it('un id mal formado es NOT_FOUND (no distingue de "no existe")', async () => {
    const res = await porGuardia('no-es-un-id');
    expect(res.status).toBe(404);
  });
});

// ── A-08 · Usuarios y desbloqueo ──────────────────────────────────────

describe('GET /admin/users', () => {
  it('solo devuelve usuarios protegidos, ordenados por nombre', async () => {
    const res = await request(env.app.server).get(`${API}/admin/users`).set(conToken());
    expect(res.status).toBe(200);
    const usuarios = res.body.data as { id: string; name: string; role: string }[];
    expect(usuarios.every((u) => u.role === 'protected_user')).toBe(true);
    const ids = usuarios.map((u) => u.id);
    expect(ids).not.toContain(env.usuarios.guardia.id);
    expect(ids).not.toContain(env.usuarios.admin.id);
    // El entorno crea protegido, inactivo y bloqueado como protected_user.
    expect(ids).toHaveLength(3);
    expect([...usuarios].map((u) => u.name)).toEqual(
      [...usuarios].map((u) => u.name).sort((a, b) => a.localeCompare(b)),
    );
  });

  it('cada usuario trae exactamente las claves del contrato (sin passwordHash)', async () => {
    const res = await request(env.app.server).get(`${API}/admin/users`).set(conToken());
    const primero = (res.body.data as Record<string, unknown>[])[0];
    expect(Object.keys(primero ?? {}).sort()).toEqual([...USER_KEYS]);
  });
});

describe('GET /admin/users/blocked', () => {
  it('solo los que tienen un bloqueo vigente', async () => {
    const res = await request(env.app.server).get(`${API}/admin/users/blocked`).set(conToken());
    expect(res.status).toBe(200);
    expect((res.body.data as { id: string }[]).map((u) => u.id)).toEqual([
      env.usuarios.bloqueado.id,
    ]);
  });

  it('un bloqueo vencido ya no sale, aunque la fecha siga en la base', async () => {
    await env.prisma.user.update({
      where: { id: env.usuarios.bloqueado.id },
      data: { blockedUntil: new Date('2020-01-01T00:00:00Z') },
    });
    const res = await request(env.app.server).get(`${API}/admin/users/blocked`).set(conToken());
    expect(res.body.data).toEqual([]);
  });
});

describe('DELETE /admin/users/:id/block', () => {
  const desbloquear = (id: string) =>
    request(env.app.server).delete(`${API}/admin/users/${id}/block`).set(conToken());

  it('quita el bloqueo y pone el contador de falsas alarmas en 0', async () => {
    const res = await desbloquear(env.usuarios.bloqueado.id);
    expect(res.status).toBe(200);
    expect(res.body.data).toBeNull();

    const usuario = await env.prisma.user.findUniqueOrThrow({
      where: { id: env.usuarios.bloqueado.id },
    });
    expect(usuario.blockedUntil).toBeNull();
    expect(usuario.falseAlarmCount).toBe(0);
  });

  it('después de desbloquear ya no aparece en la lista de bloqueados', async () => {
    await desbloquear(env.usuarios.bloqueado.id);
    const res = await request(env.app.server).get(`${API}/admin/users/blocked`).set(conToken());
    expect(res.body.data).toEqual([]);
  });

  it('desbloquear a quien no está bloqueado no es error: deja el mismo estado', async () => {
    const res = await desbloquear(env.usuarios.protegido.id);
    expect(res.status).toBe(200);
    const usuario = await env.prisma.user.findUniqueOrThrow({
      where: { id: env.usuarios.protegido.id },
    });
    expect(usuario.blockedUntil).toBeNull();
    expect(usuario.falseAlarmCount).toBe(0);
  });

  it('un id de guardia es NOT_FOUND: el bloqueo es solo de usuarios protegidos', async () => {
    const res = await desbloquear(env.usuarios.guardia.id);
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });

  it('un id que no existe es NOT_FOUND', async () => {
    const res = await desbloquear('3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11');
    expect(res.status).toBe(404);
  });
});

// ── La zona horaria de las métricas es configurable ───────────────────

describe('TZ_SHIFTS distinto', () => {
  it('con TZ_SHIFTS=UTC la misma alerta cae en otra hora', async () => {
    const otro = await crearEntorno({ TZ_SHIFTS: 'UTC' });
    try {
      const token = (await login(otro.app, otro.usuarios.admin.email)).body.data
        .accessToken as string;
      // `searching` para no tener que inventarle guardia ni cierre: lo que mide esta prueba
      // es la HORA en que cae la alerta, no su estado.
      await otro.prisma.alert.create({
        data: {
          userId: otro.usuarios.protegido.id,
          status: 'searching',
          triggerMethod: 'shake',
          triggeredAt: new Date('2026-01-15T02:00:00Z'),
          receivedAt: new Date('2026-01-15T02:00:00Z'),
          statusChangedAt: new Date('2026-01-15T02:00:00Z'),
        },
      });
      const res = await request(otro.app.server)
        .get(`${API}/admin/metrics`)
        .set({ Authorization: `Bearer ${token}` });
      expect(res.body.data.alertsByHour[2]).toBe(1);
      expect(res.body.data.alertsByHour[20]).toBe(0);
    } finally {
      await otro.cerrar();
    }
  }, 120_000);
});

// El nombre de la zona por defecto queda escrito aquí para que un cambio de TZ_SHIFTS
// en la configuración de pruebas no pase desapercibido.
describe('configuración', () => {
  it('las pruebas de arriba suponen TZ_SHIFTS = America/Mexico_City', () => {
    expect(env.app.config.TZ_SHIFTS).toBe(TZ);
  });
});
