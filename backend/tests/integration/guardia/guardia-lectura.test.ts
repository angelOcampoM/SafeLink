// BE-04 paso 1 · Vista del guardia contra PostgreSQL real: GET /guard/me, /guard/history,
// /guard/metrics y /guard/alerts/:id (G-01, G-04, D22, D23, D40, D41).
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
// Los turnos son relativos a "ahora" (hora local de TZ_SHIFTS) o de 24 h (inicio = fin, D1):
// nunca horas fijas, para que el resultado no dependa de cuándo corre la prueba.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { guardMetrics } from '../../../src/domain/metrics.js';
import {
  MSG_UNAUTHORIZED,
  PASSWORD,
  USER_KEYS,
  crearEntorno,
  decodificar,
  firmarHmac,
  hasherPrueba,
  login,
  type Entorno,
} from '../auth/helpers.js';
import { crearAlerta, crearUsuario } from '../db/helpers.js';

const API = '/api/v1';
const ZONA = 'America/Mexico_City'; // TZ_SHIFTS por defecto
const MSG_FORBIDDEN = 'No tienes permiso para realizar esta acción.';
const CUERPO_404 = { error: { code: 'NOT_FOUND', message: 'La alerta ya no existe' } };
const UUID_INEXISTENTE = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
const FOTO = '0a1b2c3d-0a1b-4c3d-8a1b-0a1b2c3d4e5f';

const CLAVES_ALERTA = [
  'acceptedAt', 'adminNote', 'arrivedAt', 'closedAt', 'escalationReason', 'etaSeconds', 'evidenceIncomplete',
  'guardId', 'guardName', 'heading', 'id', 'location', 'photoUrl', 'resolution', 'status', 'triggerMethod',
  'triggeredAt', 'userId', 'userName', 'userPhone',
].sort();
const CLAVES_PERFIL = [
  'coverageCenter', 'coverageRadiusMeters', 'lastLocation', 'lastLocationAt', 'shiftEnd', 'shiftStart', 'userId', 'zone',
].sort();

const CENTRO = { lat: 18.84, lng: -99.18 };
const DENTRO = { lat: 18.8405, lng: -99.18 }; // ~55 m del centro
const FUERA = { lat: 18.95, lng: -99.18 }; // ~12 km

let env: Entorno;
let tokenGuardia: string;
let otroGuardiaId: string;
let sinPerfilEmail: string;

/** "HH:mm" local de (ahora + minutos) en la zona de los turnos. */
function horaLocal(minutos: number): string {
  const partes = new Intl.DateTimeFormat('en-US', {
    timeZone: ZONA,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(Date.now() + minutos * 60_000));
  const h = partes.find((p) => p.type === 'hour')?.value ?? '00';
  const m = partes.find((p) => p.type === 'minute')?.value ?? '00';
  return `${h === '24' ? '00' : h}:${m}`;
}
const EN_TURNO = () => ({ shiftStart: horaLocal(-60), shiftEnd: horaLocal(60) });
const FUERA_DE_TURNO = () => ({ shiftStart: horaLocal(120), shiftEnd: horaLocal(180) });

async function token(email: string): Promise<string> {
  const res = await login(env.app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
}

const auth = (t: string) => ({ Authorization: `Bearer ${t}` });
const get = (ruta: string, t: string = tokenGuardia) =>
  request(env.app.server).get(`${API}${ruta}`).set(auth(t));

/**
 * Perfil del guardia de prueba: en turno (24 h), cobertura de 1 km alrededor de CENTRO y sin
 * ubicación reportada (se reinicia para que ninguna prueba herede la de otra).
 */
async function perfil(datos: Partial<{
  shiftStart: string;
  shiftEnd: string;
  coverageCenterLat: number | null;
  coverageCenterLng: number | null;
  coverageRadiusMeters: number | null;
  lastLocationLat: number | null;
  lastLocationLng: number | null;
  lastLocationAt: Date | null;
}> = {}): Promise<void> {
  const base = {
    shiftStart: '00:00',
    shiftEnd: '00:00',
    coverageCenterLat: CENTRO.lat,
    coverageCenterLng: CENTRO.lng,
    coverageRadiusMeters: 1000,
    zone: 'Zona Centro',
    lastLocationLat: null,
    lastLocationLng: null,
    lastLocationAt: null,
    ...datos,
  };
  await env.prisma.guardProfile.upsert({
    where: { userId: env.usuarios.guardia.id },
    create: { userId: env.usuarios.guardia.id, ...base },
    update: base,
  });
}

beforeAll(async () => {
  env = await crearEntorno();
  const passwordHash = await hasherPrueba.hash(PASSWORD);
  const otro = await env.prisma.user.create({
    data: { name: 'Otro guardia', email: 'otro-guardia@prueba.test', phone: '7772223344', passwordHash, role: 'guard' },
  });
  otroGuardiaId = otro.id;
  await env.prisma.guardProfile.create({
    data: { userId: otro.id, shiftStart: '00:00', shiftEnd: '00:00', coverageCenterLat: CENTRO.lat, coverageCenterLng: CENTRO.lng, coverageRadiusMeters: 1000 },
  });
  sinPerfilEmail = 'guardia-sin-perfil@prueba.test';
  await env.prisma.user.create({
    data: { name: 'Sin perfil', email: sinPerfilEmail, phone: '7773334455', passwordHash, role: 'guard' },
  });
}, 120_000);

afterAll(async () => {
  await env.cerrar();
});

beforeEach(async () => {
  await env.prisma.alert.deleteMany(); // alert_ignores e historial caen en cascada
  await env.prisma.user.update({ where: { id: env.usuarios.guardia.id }, data: { isActive: true } });
  await perfil();
  tokenGuardia = await token(env.usuarios.guardia.email);
});

const usuarioId = () => env.usuarios.protegido.id;
const guardiaId = () => env.usuarios.guardia.id;

// ── GET /guard/alerts/:id: visibilidad (G-04, D22, D40) ────────────────

describe('GET /guard/alerts/:id: alertas visibles', () => {
  it.each(['in_progress', 'guard_arrived', 'closed', 'escalated', 'resolved_by_admin'] as const)(
    'G-04: asignada a mí en %s -> 200, aunque esté fuera de turno y de cobertura',
    async (status) => {
      await perfil({ ...FUERA_DE_TURNO(), coverageRadiusMeters: 10 });
      const a = await crearAlerta(env.prisma, usuarioId(), { status, guardId: guardiaId(), lat: FUERA.lat, lng: FUERA.lng });
      const res = await get(`/guard/alerts/${a.id}`);
      expect(res.status).toBe(200);
      expect(res.body.data.id).toBe(a.id);
      expect(res.body.data.status).toBe(status);
      expect(Object.keys(res.body)).toEqual(['data']);
    },
  );

  it('G-04: disponible (searching, en turno, dentro del radio) -> 200 sin teléfono y con ubicación', async () => {
    await perfil(EN_TURNO());
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: DENTRO.lat, lng: DENTRO.lng });
    const res = await get(`/guard/alerts/${a.id}`);
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('searching');
    expect(res.body.data.guardId).toBeNull();
    expect(res.body.data.userPhone).toBeNull(); // D23: aún no es su alerta
    expect(res.body.data.location).toEqual(DENTRO);
    expect(res.body.data.userName).toBe('Nombre protegido');
  });

  it('G-04: disponible con turno de 24 h (inicio = fin, D1) -> 200', async () => {
    await perfil({ shiftStart: '08:00', shiftEnd: '08:00' });
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });
    expect((await get(`/guard/alerts/${a.id}`)).status).toBe(200);
  });

  it('D23: asignada y activa -> el guardia recibe teléfono y ubicación, con las 20 claves', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), {
      status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, heading: 90,
      acceptedAt: new Date(), photoKey: FOTO,
    });
    const res = await get(`/guard/alerts/${a.id}`);
    expect(res.status).toBe(200);
    expect(Object.keys(res.body.data).sort()).toEqual(CLAVES_ALERTA);
    expect(res.body.data.userPhone).toBe('7771234567');
    expect(res.body.data.location).toEqual(CENTRO);
    expect(res.body.data.guardName).toBe('Nombre guardia');
    expect(res.body.data.photoUrl).toContain(`/alerts/${a.id}/photo`);
    expect(res.body.data.etaSeconds).toBeNull(); // el guardia aún no reporta ubicación (D27)
  });

  it('D23: asignada y ya cerrada -> sin teléfono ni ubicación, la foto se conserva', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), {
      status: 'closed', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, photoKey: FOTO,
    });
    const res = await get(`/guard/alerts/${a.id}`);
    expect(res.status).toBe(200);
    expect(res.body.data.userPhone).toBeNull();
    expect(res.body.data.location).toBeNull();
    expect(res.body.data.photoUrl).toContain(`/alerts/${a.id}/photo`);
  });

  it('D27: con última ubicación del guardia el ETA de una alerta in_progress es un entero positivo', async () => {
    await env.prisma.guardProfile.update({
      where: { userId: guardiaId() },
      data: { lastLocationLat: 18.85, lastLocationLng: -99.18, lastLocationAt: new Date() },
    });
    const a = await crearAlerta(env.prisma, usuarioId(), {
      status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, acceptedAt: new Date(),
    });
    const res = await get(`/guard/alerts/${a.id}`);
    expect(Number.isInteger(res.body.data.etaSeconds)).toBe(true);
    expect(res.body.data.etaSeconds).toBeGreaterThan(0);
  });
});

describe('GET /guard/alerts/:id: todo lo demás es 404 con el MISMO cuerpo (D22, D40)', () => {
  /** Cada caso prepara su situación y devuelve el id a consultar. */
  const casos: Array<[string, () => Promise<string>]> = [
    ['fuera de radio', async () => {
      await perfil(EN_TURNO());
      return (await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: FUERA.lat, lng: FUERA.lng })).id;
    }],
    ['fuera de turno', async () => {
      await perfil(FUERA_DE_TURNO());
      return (await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: DENTRO.lat, lng: DENTRO.lng })).id;
    }],
    ['guardia sin cobertura asignada', async () => {
      await perfil({ coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null });
      return (await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: DENTRO.lat, lng: DENTRO.lng })).id;
    }],
    ['ignorada por mí', async () => {
      const a = await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: DENTRO.lat, lng: DENTRO.lng });
      await env.prisma.alertIgnore.create({ data: { guardId: guardiaId(), alertId: a.id } });
      return a.id;
    }],
    ['asignada a otro guardia (in_progress)', async () =>
      (await crearAlerta(env.prisma, usuarioId(), {
        status: 'in_progress', guardId: otroGuardiaId, lat: DENTRO.lat, lng: DENTRO.lng, acceptedAt: new Date(),
      })).id],
    ['asignada a otro guardia (cerrada)', async () =>
      (await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: otroGuardiaId, lat: DENTRO.lat, lng: DENTRO.lng })).id],
    ['pending_location (sin ubicación, no se publica)', async () =>
      (await crearAlerta(env.prisma, usuarioId(), { status: 'pending_location' })).id],
    ['escalada sin guardia (ya no está disponible)', async () =>
      (await crearAlerta(env.prisma, usuarioId(), { status: 'escalated', lat: DENTRO.lat, lng: DENTRO.lng })).id],
    ['no_response sin guardia', async () =>
      (await crearAlerta(env.prisma, usuarioId(), { status: 'no_response', lat: DENTRO.lat, lng: DENTRO.lng })).id],
    ['inexistente (UUID válido)', async () => UUID_INEXISTENTE],
    ['UUID mal formado', async () => 'no-es-un-uuid'],
    ['id con inyección SQL', async () => encodeURIComponent("1' OR '1'='1")],
    ['id numérico', async () => '12345'],
  ];

  it.each(casos)('%s -> 404 y cuerpo idéntico', async (_nombre, preparar) => {
    const id = await preparar();
    const res = await get(`/guard/alerts/${id}`);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('los 404 son byte a byte iguales entre sí: no hay forma de distinguir existente de inexistente', async () => {
    const textos = new Set<string>();
    for (const [, preparar] of casos) {
      await env.prisma.alert.deleteMany();
      await perfil();
      const id = await preparar();
      const res = await get(`/guard/alerts/${id}`);
      expect(res.status).toBe(404);
      textos.add(res.text);
    }
    expect(textos.size).toBe(1);
  });

  it('la alerta de otro guardia no se filtra ni con un token válido de un guardia distinto', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), {
      status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, acceptedAt: new Date(),
    });
    const tokenOtro = await token('otro-guardia@prueba.test');
    // El otro guardia está en turno y con cobertura, pero la alerta ya no está disponible: 404.
    const res = await get(`/guard/alerts/${a.id}`, tokenOtro);
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    expect(res.text).not.toContain('7771234567');
  });

  it('guardia dado de baja: su token vigente deja de servir (401), no ve alertas', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });
    await env.prisma.user.update({ where: { id: guardiaId() }, data: { isActive: false } });
    const res = await get(`/guard/alerts/${a.id}`);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it('un guardia sin perfil que pide una alerta existente recibe 404 sin datos', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });
    const res = await get(`/guard/alerts/${a.id}`, await token(sinPerfilEmail));
    expect(res.status).toBe(404);
    expect(res.body).toEqual(CUERPO_404);
    expect(res.text).not.toContain('7771234567');
  });
});

// ── GET /guard/history ─────────────────────────────────────────────────

describe('GET /guard/history', () => {
  const hace = (minutos: number) => new Date(Date.now() - minutos * 60_000);

  it('sin alertas -> { data: [] }', async () => {
    const res = await get('/guard/history');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: [] });
  });

  it('solo las propias y no activas; excluye activas, ajenas y las sin guardia', async () => {
    const cerrada = await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: guardiaId(), receivedAt: hace(180) });
    const escalada = await crearAlerta(env.prisma, usuarioId(), { status: 'escalated', guardId: guardiaId(), receivedAt: hace(60), escalationReason: 'no_confirmation' });
    const admin = await crearAlerta(env.prisma, usuarioId(), { status: 'resolved_by_admin', guardId: guardiaId(), receivedAt: hace(120), resolution: 'resolved' });
    // Fuera del historial. Cada activa es de un usuario distinto: solo cabe una activa por usuario
    // (alerts_one_active_per_user_idx).
    await crearAlerta(env.prisma, usuarioId(), { status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng });
    await crearAlerta(env.prisma, (await crearUsuario(env.prisma)).id, { status: 'guard_arrived', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng });
    await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: otroGuardiaId });
    await crearAlerta(env.prisma, usuarioId(), { status: 'no_response' });
    await crearAlerta(env.prisma, (await crearUsuario(env.prisma)).id, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng });

    const res = await get('/guard/history');
    expect(res.status).toBe(200);
    // Más recientes primero por receivedAt: escalada (-60), resolved_by_admin (-120), cerrada (-180).
    expect((res.body.data as Array<{ id: string }>).map((x) => x.id)).toEqual([escalada.id, admin.id, cerrada.id]);
    for (const item of res.body.data as Array<Record<string, unknown>>) {
      expect(Object.keys(item).sort()).toEqual(CLAVES_ALERTA);
      expect(item['guardId']).toBe(guardiaId());
    }
  });

  it('desempata por id ascendente cuando receivedAt coincide (orden determinista)', async () => {
    const instante = hace(30);
    const ids: string[] = [];
    for (let i = 0; i < 4; i += 1) {
      ids.push((await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: guardiaId(), receivedAt: instante })).id);
    }
    const res = await get('/guard/history');
    expect((res.body.data as Array<{ id: string }>).map((x) => x.id)).toEqual([...ids].sort());
  });

  it('D23: nada de teléfono ni ubicación en el historial; la foto y los campos nulos van como null', async () => {
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'closed', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, photoKey: FOTO,
    });
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'escalated', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, escalationReason: 'no_response',
    });
    const res = await get('/guard/history');
    const [a, b] = res.body.data as Array<Record<string, unknown>>;
    for (const item of [a, b]) {
      expect(item?.['userPhone']).toBeNull();
      expect(item?.['location']).toBeNull();
      expect(item?.['etaSeconds']).toBeNull();
      expect(item?.['arrivedAt']).toBeNull();
      expect(item?.['resolution']).toBeNull();
      expect(item?.['adminNote']).toBeNull();
    }
    const conFoto = (res.body.data as Array<{ photoUrl: string | null }>).filter((x) => x.photoUrl !== null);
    expect(conFoto).toHaveLength(1);
  });

  it('sin paginación: devuelve todas (120 alertas)', async () => {
    await env.prisma.alert.createMany({
      data: Array.from({ length: 120 }, (_, i) => ({
        userId: usuarioId(), guardId: guardiaId(), status: 'closed' as const, triggerMethod: 'tap' as const,
        triggeredAt: hace(i), receivedAt: hace(i), closedAt: hace(i),
      })),
    });
    const res = await get('/guard/history');
    expect(res.body.data).toHaveLength(120);
  });

  it('un guardia nunca ve el historial de otro: cada quien recibe solo el suyo', async () => {
    await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: otroGuardiaId });
    const mio = await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: guardiaId() });
    const del_otro = await get('/guard/history', await token('otro-guardia@prueba.test'));
    const del_mio = await get('/guard/history');
    expect((del_mio.body.data as Array<{ id: string }>).map((x) => x.id)).toEqual([mio.id]);
    expect(del_otro.body.data).toHaveLength(1);
    expect((del_otro.body.data as Array<{ id: string }>)[0]?.id).not.toBe(mio.id);
  });

  it('ignora cualquier guardId o parámetro del cliente: siempre el guardia de la sesión', async () => {
    await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: otroGuardiaId });
    const res = await request(env.app.server)
      .get(`${API}/guard/history`)
      .query({ guardId: otroGuardiaId, from: '2000-01-01T00:00:00Z' })
      .set(auth(tokenGuardia));
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual([]);
  });
});

// ── GET /guard/metrics ─────────────────────────────────────────────────

describe('GET /guard/metrics (G-01, A-07, D41)', () => {
  it('sin alertas -> todo en 0, sin NaN', async () => {
    const res = await get('/guard/metrics');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      data: { attendedCount: 0, avgAcceptanceSeconds: 0, avgArrivalSeconds: 0, escalatedCount: 0 },
    });
  });

  it('calcula sobre la misma lista que history, con duraciones truncadas por alerta', async () => {
    const R = Date.now() - 3_600_000;
    const en = (ms: number) => new Date(R + ms);
    // Atendida: acepta a los 30.9 s (-> 30) y llega 120.5 s después (-> 120).
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'closed', guardId: guardiaId(), triggeredAt: en(0), receivedAt: en(0),
      acceptedAt: en(30_900), arrivedAt: en(30_900 + 120_500),
    });
    // Escalada tras aceptar a los 10 s, sin llegada.
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'escalated', guardId: guardiaId(), triggeredAt: en(0), receivedAt: en(1000),
      acceptedAt: en(11_000), escalationReason: 'no_confirmation',
    });
    // No cuentan: activa mía, cerrada de otro guardia y alerta sin guardia.
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'guard_arrived', guardId: guardiaId(), acceptedAt: en(5000), arrivedAt: en(900_000),
    });
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'closed', guardId: otroGuardiaId, receivedAt: en(0), acceptedAt: en(500_000), arrivedAt: en(900_000),
      escalationReason: 'no_response',
    });
    await crearAlerta(env.prisma, usuarioId(), { status: 'no_response' });

    const res = await get('/guard/metrics');
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      attendedCount: 1,
      avgAcceptanceSeconds: 20, // (30 + 10) / 2
      avgArrivalSeconds: 120,
      escalatedCount: 1,
    });
    expect(Object.keys(res.body.data).sort()).toEqual(
      ['attendedCount', 'avgAcceptanceSeconds', 'avgArrivalSeconds', 'escalatedCount'],
    );
  });

  it('D41: las métricas son coherentes con lo que devuelve history', async () => {
    const R = Date.now() - 7_200_000;
    for (const [i, status] of (['closed', 'closed', 'escalated', 'resolved_by_admin'] as const).entries()) {
      const inicio = R + i * 60_000;
      await crearAlerta(env.prisma, usuarioId(), {
        status,
        guardId: guardiaId(),
        triggeredAt: new Date(inicio),
        receivedAt: new Date(inicio),
        acceptedAt: new Date(inicio + (i + 1) * 7_300),
        arrivedAt: status === 'closed' ? new Date(inicio + (i + 1) * 7_300 + (i + 2) * 41_100) : null,
        escalationReason: status === 'escalated' ? 'no_response' : null,
      });
    }
    const historial = (await get('/guard/history')).body.data as Array<{
      guardId: string; triggeredAt: string; acceptedAt: string | null; arrivedAt: string | null; escalationReason: 'no_response' | 'no_confirmation' | null;
    }>;
    const esperado = guardMetrics(
      guardiaId(),
      historial.map((h) => ({
        guardId: h.guardId,
        receivedAt: new Date(h.triggeredAt), // en estas alertas triggeredAt = receivedAt
        acceptedAt: h.acceptedAt ? new Date(h.acceptedAt) : null,
        arrivedAt: h.arrivedAt ? new Date(h.arrivedAt) : null,
        escalationReason: h.escalationReason,
      })),
    );
    const res = await get('/guard/metrics');
    expect(res.body.data).toEqual(esperado);
    expect(res.body.data.attendedCount).toBe(historial.filter((h) => h.arrivedAt !== null).length);
    expect(res.body.data.escalatedCount).toBe(historial.filter((h) => h.escalationReason !== null).length);
  });

  it('A-07: usa receivedAt (hora del servidor) y no triggeredAt (hora del teléfono, D24)', async () => {
    const R = Date.now() - 600_000;
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'closed', guardId: guardiaId(),
      triggeredAt: new Date(R - 3_600_000), // reloj del teléfono desfasado una hora
      receivedAt: new Date(R),
      acceptedAt: new Date(R + 12_000), arrivedAt: new Date(R + 72_000),
    });
    const res = await get('/guard/metrics');
    expect(res.body.data.avgAcceptanceSeconds).toBe(12);
    expect(res.body.data.avgArrivalSeconds).toBe(60);
  });

  it('cada guardia ve sus propias métricas, no las de otro', async () => {
    const R = Date.now() - 600_000;
    await crearAlerta(env.prisma, usuarioId(), {
      status: 'closed', guardId: otroGuardiaId, receivedAt: new Date(R), triggeredAt: new Date(R),
      acceptedAt: new Date(R + 5000), arrivedAt: new Date(R + 9000),
    });
    expect((await get('/guard/metrics')).body.data.attendedCount).toBe(0);
    expect((await get('/guard/metrics', await token('otro-guardia@prueba.test'))).body.data.attendedCount).toBe(1);
  });
});

// ── GET /guard/me ──────────────────────────────────────────────────────

describe('GET /guard/me (G-01)', () => {
  it('responde { data: { user, profile } } con la forma GuardiaJson del front', async () => {
    const res = await get('/guard/me');
    expect(res.status).toBe(200);
    expect(Object.keys(res.body)).toEqual(['data']);
    expect(Object.keys(res.body.data).sort()).toEqual(['profile', 'user']);
    expect(Object.keys(res.body.data.user).sort()).toEqual([...USER_KEYS].sort());
    expect(Object.keys(res.body.data.profile).sort()).toEqual(CLAVES_PERFIL);
    expect(res.body.data.user).toMatchObject({ id: guardiaId(), role: 'guard', isActive: true, email: env.usuarios.guardia.email });
    expect(res.body.data.profile).toMatchObject({
      userId: guardiaId(),
      shiftStart: '00:00',
      shiftEnd: '00:00',
      coverageCenter: CENTRO,
      coverageRadiusMeters: 1000,
      zone: 'Zona Centro',
      lastLocation: null,
      lastLocationAt: null,
    });
    expect(res.headers['cache-control']).toBe('no-store');
  });

  it('con cobertura y ubicación vacías devuelve null (no omite las claves)', async () => {
    await perfil({ coverageCenterLat: null, coverageCenterLng: null, coverageRadiusMeters: null });
    const res = await get('/guard/me');
    expect(res.body.data.profile.coverageCenter).toBeNull();
    expect(res.body.data.profile.coverageRadiusMeters).toBeNull();
    expect(Object.keys(res.body.data.profile).sort()).toEqual(CLAVES_PERFIL);
  });

  it('muestra la última ubicación reportada en ISO 8601 UTC', async () => {
    const cuando = new Date('2026-11-16T18:00:00.000Z');
    await env.prisma.guardProfile.update({
      where: { userId: guardiaId() },
      data: { lastLocationLat: 18.85, lastLocationLng: -99.17, lastLocationAt: cuando },
    });
    const res = await get('/guard/me');
    expect(res.body.data.profile.lastLocation).toEqual({ lat: 18.85, lng: -99.17 });
    expect(res.body.data.profile.lastLocationAt).toBe('2026-11-16T18:00:00.000Z');
  });

  it('siempre es el guardia de la sesión: el de otro token ve su propio perfil', async () => {
    const res = await get('/guard/me', await token('otro-guardia@prueba.test'));
    expect(res.body.data.user.id).toBe(otroGuardiaId);
    expect(res.body.data.profile.userId).toBe(otroGuardiaId);
  });

  it('un guardia sin perfil recibe 404 NOT_FOUND (no un 500)', async () => {
    const res = await get('/guard/me', await token(sinPerfilEmail));
    expect(res.status).toBe(404);
    expect(res.body.error.code).toBe('NOT_FOUND');
  });
});

// ── Permisos: rol x ruta ───────────────────────────────────────────────

describe('permisos de las 4 rutas del guardia', () => {
  const RUTAS = [
    '/guard/me',
    '/guard/history',
    '/guard/metrics',
    `/guard/alerts/${UUID_INEXISTENTE}`,
  ];

  it.each(RUTAS)('%s sin token -> 401', async (ruta) => {
    const res = await request(env.app.server).get(`${API}${ruta}`);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it.each(RUTAS)('%s con token vencido -> 401', async (ruta) => {
    const sid = decodificar(tokenGuardia).payload['sid'] as string;
    const ahora = Math.floor(Date.now() / 1000);
    const vencido = firmarHmac({ sub: guardiaId(), role: 'guard', sid, iat: ahora - 2000, exp: ahora - 1000 });
    const res = await get(ruta, vencido);
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: { code: 'UNAUTHORIZED', message: MSG_UNAUTHORIZED } });
  });

  it.each(RUTAS)('%s con token basura -> 401', async (ruta) => {
    expect((await get(ruta, 'a.b.c')).status).toBe(401);
  });

  describe.each([
    ['protected_user', () => env.usuarios.protegido.email],
    ['admin', () => env.usuarios.admin.email],
  ] as const)('rol %s', (_rol, email) => {
    it.each(RUTAS)('GET %s -> 403 FORBIDDEN', async (ruta) => {
      const res = await get(ruta, await token(email()));
      expect(res.status).toBe(403);
      expect(res.body).toEqual({ error: { code: 'FORBIDDEN', message: MSG_FORBIDDEN } });
    });

    it('un 403 no revela si la alerta existe: igual para existente e inexistente', async () => {
      const a = await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: guardiaId() });
      const t = await token(email());
      const existente = await get(`/guard/alerts/${a.id}`, t);
      const inexistente = await get(`/guard/alerts/${UUID_INEXISTENTE}`, t);
      expect(existente.status).toBe(403);
      expect(existente.text).toBe(inexistente.text);
    });
  });

  it.each(RUTAS)('%s con guardia -> nunca 401 ni 403', async (ruta) => {
    const res = await get(ruta);
    expect([200, 404]).toContain(res.status);
  });

  it.each(['post', 'put', 'patch', 'delete'] as const)(
    '%s sobre /guard/history, /guard/metrics y /guard/me -> 404 (solo existe GET)',
    async (metodo) => {
      for (const ruta of ['/guard/history', '/guard/metrics', '/guard/me']) {
        const res = await request(env.app.server)[metodo](`${API}${ruta}`).set(auth(tokenGuardia)).send({});
        expect(res.status, `${metodo} ${ruta}`).toBe(404);
      }
    },
  );
});

// ── Seguridad: passwordHash y secretos (DECISIONES.md:300) ─────────────

describe('ninguna respuesta de las rutas del guardia contiene passwordHash', () => {
  it('ni "passwordHash", ni "password_hash", ni "$argon2" en 200, 404, 401 ni 403', async () => {
    const a = await crearAlerta(env.prisma, usuarioId(), {
      status: 'in_progress', guardId: guardiaId(), lat: CENTRO.lat, lng: CENTRO.lng, photoKey: FOTO, acceptedAt: new Date(),
    });
    await crearAlerta(env.prisma, usuarioId(), { status: 'closed', guardId: guardiaId() });
    const rutas = ['/guard/me', '/guard/history', '/guard/metrics', `/guard/alerts/${a.id}`, `/guard/alerts/${UUID_INEXISTENTE}`];
    const respuestas = [];
    for (const ruta of rutas) {
      respuestas.push(await get(ruta));
      respuestas.push(await get(ruta, await token(env.usuarios.admin.email)));
      respuestas.push(await request(env.app.server).get(`${API}${ruta}`));
    }
    expect(respuestas.length).toBe(rutas.length * 3);
    expect(respuestas.some((r) => r.status === 200)).toBe(true);
    for (const r of respuestas) {
      const texto = r.text + JSON.stringify(r.headers);
      expect(texto).not.toContain('passwordHash');
      expect(texto).not.toContain('password_hash');
      expect(texto).not.toContain('$argon2');
    }
    // La vista del guardia tampoco incluye el correo ni datos del dueño más allá de nombre y teléfono (D23).
    const detalle = (await get(`/guard/alerts/${a.id}`)).text;
    expect(detalle).not.toContain(env.usuarios.protegido.email);
  });
});
