// BE-04 paso 11 (D44): aviso push al publicarse una alerta. PostgreSQL real; el notificador es el
// doble de grabación (createRecordingNotifier). El envío es asíncrono (fire-and-forget): para esperar
// se sondea hasta que cambie el número de llamadas (con tope); para afirmar "no se envió" se deja
// asentar un lapso acotado, porque no hay un evento que marque el fin del despacho.
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../../src/app.js';
import { createDevicesService } from '../../../src/modules/devices/service.js';
import { createAlertDispatcher } from '../../../src/notifications/dispatcher.js';
import type { PushAlertInput, PushNotifier, PushResult } from '../../../src/notifications/push-notifier.js';
import { createRecordingNotifier, type RecordingNotifier } from '../../helpers/recording-notifier.js';
import { PASSWORD, configPrueba, decodificar, hasherPrueba, login } from '../auth/helpers.js';
import { abrirDb, correoUnico, crearAlerta, crearUsuario, type ContextoDb } from '../db/helpers.js';

const API = '/api/v1';
const ZONA = 'America/Mexico_City';
const CENTRO = { lat: 18.84, lng: -99.18 };
const FUERA = { lat: 18.95, lng: -99.18 };

let db: ContextoDb;
let passwordHash: string;
let notifier: RecordingNotifier;
let app: ReturnType<typeof buildApp>;
let seq = 0;

function horaLocal(minutos: number): string {
  const partes = new Intl.DateTimeFormat('en-US', { timeZone: ZONA, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(new Date(Date.now() + minutos * 60_000));
  const h = partes.find((p) => p.type === 'hour')?.value ?? '00';
  const m = partes.find((p) => p.type === 'minute')?.value ?? '00';
  return `${h === '24' ? '00' : h}:${m}`;
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Espera a que la condición se cumpla (sondeo corto) o falla al vencer el tope. */
async function esperar(cond: () => boolean, tope = 5000): Promise<void> {
  const fin = Date.now() + tope;
  while (!cond()) {
    if (Date.now() > fin) throw new Error('Tiempo agotado esperando el envío');
    await sleep(5);
  }
}
const esperarLlamadas = (rec: { calls: unknown[] }, n: number) => esperar(() => rec.calls.length >= n);
/** Para afirmar ausencia: deja asentar el despacho asíncrono un lapso acotado. */
const asentar = () => sleep(250);

interface Guardia { id: string; email: string; token: string; access: string }

async function crearGuardia(
  opciones: { centro?: { lat: number; lng: number }; radio?: number; turno?: [string, string]; sinPerfil?: boolean;
    ultima?: { lat: number; lng: number }; conToken?: boolean; role?: 'guard' | 'admin' | 'protected_user' } = {},
): Promise<Guardia> {
  const email = correoUnico('push');
  seq += 1;
  const role = opciones.role ?? 'guard';
  const u = await crearUsuario(db.prisma, { role, email, passwordHash });
  if (role === 'guard' && !opciones.sinPerfil) {
    const centro = opciones.centro ?? CENTRO;
    await db.prisma.guardProfile.create({
      data: {
        userId: u.id,
        shiftStart: opciones.turno?.[0] ?? '00:00', shiftEnd: opciones.turno?.[1] ?? '00:00',
        coverageCenterLat: centro.lat, coverageCenterLng: centro.lng, coverageRadiusMeters: opciones.radio ?? 2000,
        ...(opciones.ultima ? { lastLocationLat: opciones.ultima.lat, lastLocationLng: opciones.ultima.lng, lastLocationAt: new Date() } : {}),
      },
    });
  }
  const res = await login(app, email);
  expect(res.status).toBe(200);
  const access = res.body.data.accessToken as string;
  const token = `fcm-token-${String(seq)}-${'t'.repeat(40)}`;
  if (opciones.conToken !== false && role !== 'guard') {
    // La ruta solo admite guardias (403 para otros roles): el token se inserta directo con una
    // sesión viva, para probar que el rol, y no el token, es lo que excluye al destinatario.
    const sid = decodificar(access).payload['sid'] as string;
    await db.prisma.deviceToken.create({ data: { userId: u.id, token, familyId: sid } });
  } else if (opciones.conToken !== false) {
    const put = await request(app.server).put(`${API}/users/me/device-token`).set('Authorization', `Bearer ${access}`).send({ token });
    expect(put.status).toBe(200);
  }
  return { id: u.id, email, token, access };
}

async function crearDueno(): Promise<{ id: string; access: string }> {
  const email = correoUnico('dueno');
  const u = await crearUsuario(db.prisma, { email, passwordHash });
  const res = await login(app, email);
  return { id: u.id, access: res.body.data.accessToken as string };
}

const cuerpo = (extra: Record<string, unknown> = {}) => ({
  triggerMethod: 'tap',
  triggeredAt: new Date().toISOString(),
  location: CENTRO,
  heading: 35,
  ...extra,
});
const crear = (access: string, body: object) =>
  request(app.server).post(`${API}/alerts`).set('Authorization', `Bearer ${access}`).send(body);

function armarApp(push: PushNotifier, extra: Record<string, string> = {}) {
  return buildApp(configPrueba(extra), { prisma: db.prisma, push });
}

interface LogEntry { nivel: 'info' | 'warn'; obj: Record<string, unknown>; msg: string }
function espiaLogger() {
  const entradas: LogEntry[] = [];
  return {
    entradas,
    info: (obj: Record<string, unknown>, msg: string) => void entradas.push({ nivel: 'info', obj, msg }),
    warn: (obj: Record<string, unknown>, msg: string) => void entradas.push({ nivel: 'warn', obj, msg }),
  };
}

function despachadorDirecto(push: PushNotifier, extra: { max?: number; enabled?: boolean; logger?: ReturnType<typeof espiaLogger> } = {}) {
  const logger = extra.logger ?? espiaLogger();
  const dispatcher = createAlertDispatcher({
    prisma: db.prisma, push, devices: createDevicesService({ prisma: db.prisma }), logger,
    timeZone: ZONA, maxTokensPerAlert: extra.max ?? 500, enabled: extra.enabled ?? true,
  });
  return { dispatcher, logger };
}

async function alertaBuscando(extra: Record<string, unknown> = {}) {
  const d = await crearUsuario(db.prisma, { passwordHash });
  return crearAlerta(db.prisma, d.id, { status: 'searching', lat: CENTRO.lat, lng: CENTRO.lng, ...extra });
}

beforeAll(async () => {
  db = await abrirDb();
  passwordHash = await hasherPrueba.hash(PASSWORD);
}, 120_000);
afterAll(async () => {
  await app?.close();
  await db.cerrar();
});
beforeEach(async () => {
  await app?.close();
  await db.limpiar();
  notifier = createRecordingNotifier();
  app = armarApp(notifier);
  await app.ready();
});

describe('push al crear la alerta (D44)', () => {
  it('alerta con ubicación: un push a la guardia en radio/turno con payload {tokens, alertId, urgent:false} (tap)', async () => {
    const g = await crearGuardia();
    const d = await crearDueno();
    const res = await crear(d.access, cuerpo());
    expect(res.status).toBe(201);
    await esperarLlamadas(notifier, 1);
    expect(notifier.calls).toEqual([{ tokens: [g.token], alertId: res.body.data.id, urgent: false }]);
  });

  it.each([
    ['hold', false],
    ['tap', false],
    ['shake', true],
  ])('urgent según el disparo %s -> %s', async (metodo, urgente) => {
    await crearGuardia();
    const d = await crearDueno();
    const res = await crear(d.access, cuerpo({ triggerMethod: metodo }));
    expect(res.status).toBe(201);
    await esperarLlamadas(notifier, 1);
    expect(notifier.calls[0]?.urgent).toBe(urgente);
  });

  it('sin ubicación no hay push; la primera ubicación envía uno; la segunda (movimiento) ninguno más', async () => {
    const g = await crearGuardia();
    const d = await crearDueno();
    const res = await crear(d.access, cuerpo({ location: null }));
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('pending_location');
    await asentar();
    expect(notifier.calls).toHaveLength(0);

    const id = res.body.data.id as string;
    const loc = (location: object) =>
      request(app.server).post(`${API}/alerts/${id}/locations`).set('Authorization', `Bearer ${d.access}`).send({ location });
    expect((await loc(CENTRO)).status).toBe(200);
    await esperarLlamadas(notifier, 1);
    expect(notifier.calls).toEqual([{ tokens: [g.token], alertId: id, urgent: false }]);

    expect((await loc({ lat: 18.8402, lng: -99.1801 })).status).toBe(200);
    await asentar();
    expect(notifier.calls).toHaveLength(1);
  });

  it('un solo sendAlert con tokens de varios guardias y de varios dispositivos, sin repetidos', async () => {
    const a = await crearGuardia();
    const b = await crearGuardia();
    // Segundo dispositivo del guardia A (otra sesión).
    const r2 = await login(app, a.email);
    const extra = `fcm-segundo-${'z'.repeat(40)}`;
    expect((await request(app.server).put(`${API}/users/me/device-token`)
      .set('Authorization', `Bearer ${r2.body.data.accessToken as string}`).send({ token: extra })).status).toBe(200);
    const d = await crearDueno();
    expect((await crear(d.access, cuerpo())).status).toBe(201);
    await esperarLlamadas(notifier, 1);
    await asentar();
    expect(notifier.calls).toHaveLength(1);
    const tokens = notifier.calls[0]?.tokens ?? [];
    expect([...tokens].sort()).toEqual([a.token, b.token, extra].sort());
    expect(new Set(tokens).size).toBe(tokens.length);
  });

  it('sin guardias con token no se llama al notificador', async () => {
    await crearGuardia({ conToken: false });
    const d = await crearDueno();
    expect((await crear(d.access, cuerpo())).status).toBe(201);
    await asentar();
    expect(notifier.calls).toHaveLength(0);
  });
});

describe('destinatarios (D44, D22, D42)', () => {
  it('solo recibe la guardia elegible; no reciben fuera de radio, fuera de turno, inactiva, sin perfil, sesión revocada o vencida, ni otros roles', async () => {
    const ok = await crearGuardia();
    const fueraRadio = await crearGuardia({ centro: FUERA, radio: 1000 });
    const fueraTurno = await crearGuardia({ turno: [horaLocal(120), horaLocal(180)] });
    const inactiva = await crearGuardia();
    const sinPerfil = await crearGuardia({ sinPerfil: true });
    const revocada = await crearGuardia();
    const vencida = await crearGuardia();
    const protegido = await crearGuardia({ role: 'protected_user' });
    const admin = await crearGuardia({ role: 'admin' });
    await db.prisma.user.update({ where: { id: inactiva.id }, data: { isActive: false } });
    await db.prisma.refreshToken.updateMany({ where: { userId: revocada.id }, data: { revokedAt: new Date() } });
    await db.prisma.refreshToken.updateMany({ where: { userId: vencida.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    // Los tokens de los demás sí existen en la base: solo la elegibilidad los excluye.
    for (const x of [protegido, admin, sinPerfil, fueraRadio, fueraTurno, inactiva, revocada, vencida]) {
      expect(await db.prisma.deviceToken.count({ where: { userId: x.id } })).toBe(1);
    }
    const d = await crearDueno();
    expect((await crear(d.access, cuerpo())).status).toBe(201);
    await esperarLlamadas(notifier, 1);
    await asentar();
    expect(notifier.calls).toHaveLength(1);
    expect(notifier.calls[0]?.tokens).toEqual([ok.token]);
  });

  it('logout borra el token del dispositivo y esa guardia ya no recibe', async () => {
    const g = await crearGuardia();
    const otra = await crearGuardia();
    expect((await request(app.server).post(`${API}/auth/logout`).set('Authorization', `Bearer ${g.access}`)).status).toBe(200);
    const d = await crearDueno();
    expect((await crear(d.access, cuerpo())).status).toBe(201);
    await esperarLlamadas(notifier, 1);
    expect(notifier.calls[0]?.tokens).toEqual([otra.token]);
  });

  it('la guardia que ignoró la alerta no recibe (dispatchAlert directo)', async () => {
    const quien = await crearGuardia();
    const ignora = await crearGuardia();
    const a = await alertaBuscando();
    await db.prisma.alertIgnore.create({ data: { guardId: ignora.id, alertId: a.id } });
    const { dispatcher } = despachadorDirecto(notifier);
    await dispatcher.dispatchAlert(a.id);
    expect(notifier.calls).toEqual([{ tokens: [quien.token], alertId: a.id, urgent: false }]);
  });

  it('si todas ignoraron no se envía', async () => {
    const g = await crearGuardia();
    const a = await alertaBuscando();
    await db.prisma.alertIgnore.create({ data: { guardId: g.id, alertId: a.id } });
    const { dispatcher } = despachadorDirecto(notifier);
    await dispatcher.dispatchAlert(a.id);
    expect(notifier.calls).toHaveLength(0);
  });
});

describe('estado de la alerta al despachar (dispatchAlert directo)', () => {
  it.each(['in_progress', 'guard_arrived', 'closed', 'escalated', 'no_response', 'resolved_by_admin', 'pending_location'])(
    'alerta en %s no envía',
    async (status) => {
      await crearGuardia();
      const extra: Record<string, unknown> = { status };
      if (status === 'escalated') extra['escalationReason'] = 'no_response';
      if (status === 'pending_location') Object.assign(extra, { lat: null, lng: null });
      const a = await alertaBuscando(extra);
      const { dispatcher } = despachadorDirecto(notifier);
      await dispatcher.dispatchAlert(a.id);
      expect(notifier.calls).toHaveLength(0);
    },
  );

  it('alerta aceptada entre la publicación y el despacho no envía', async () => {
    const g = await crearGuardia();
    const a = await alertaBuscando();
    await db.prisma.alert.update({ where: { id: a.id }, data: { status: 'in_progress', guardId: g.id, acceptedAt: new Date() } });
    const { dispatcher } = despachadorDirecto(notifier);
    await dispatcher.dispatchAlert(a.id);
    expect(notifier.calls).toHaveLength(0);
  });

  it('alerta inexistente no envía ni lanza', async () => {
    await crearGuardia();
    const { dispatcher } = despachadorDirecto(notifier);
    await expect(dispatcher.dispatchAlert('3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11')).resolves.toBeUndefined();
    expect(notifier.calls).toHaveLength(0);
  });

  it('el despacho directo sirve para una alerta que vuelve a searching (BE-06), con la urgencia del disparo', async () => {
    const g = await crearGuardia();
    const a = await alertaBuscando({ triggerMethod: 'shake' });
    const { dispatcher } = despachadorDirecto(notifier);
    await dispatcher.dispatchAlert(a.id);
    expect(notifier.calls).toEqual([{ tokens: [g.token], alertId: a.id, urgent: true }]);
  });
});

describe('tope de tokens por alerta (PUSH_MAX_TOKENS_PER_ALERT)', () => {
  it('con tope 2 se envían los más cercanos (última ubicación o, si no hay, centro de cobertura) y hay warn con conteos', async () => {
    const cerca = await crearGuardia({ ultima: { lat: 18.8401, lng: -99.18 } });
    const medio = await crearGuardia({ ultima: { lat: 18.845, lng: -99.18 } });
    const lejos = await crearGuardia({ ultima: { lat: 18.855, lng: -99.18 }, radio: 5000 });
    // Sin última ubicación: parte del centro de cobertura, que coincide con la alerta (distancia 0).
    const sinUltima = await crearGuardia();
    const a = await alertaBuscando();
    const { dispatcher, logger } = despachadorDirecto(notifier, { max: 2 });
    await dispatcher.dispatchAlert(a.id);
    expect(notifier.calls).toHaveLength(1);
    expect(notifier.calls[0]?.tokens).toEqual([sinUltima.token, cerca.token]);
    expect(notifier.calls[0]?.tokens).not.toContain(medio.token);
    expect(notifier.calls[0]?.tokens).not.toContain(lejos.token);
    expect(logger.entradas.filter((e) => e.nivel === 'warn')).toEqual([
      expect.objectContaining({ obj: { alertId: a.id, total: 4, cap: 2 } }),
    ]);
  });

  it('sin rebasar el tope no hay warn', async () => {
    await crearGuardia();
    await crearGuardia();
    const a = await alertaBuscando();
    const { dispatcher, logger } = despachadorDirecto(notifier, { max: 2 });
    await dispatcher.dispatchAlert(a.id);
    expect(notifier.calls[0]?.tokens).toHaveLength(2);
    expect(logger.entradas.filter((e) => e.nivel === 'warn')).toHaveLength(0);
  });

  it('el tope llega de la configuración al armar la app', async () => {
    await app.close();
    notifier = createRecordingNotifier();
    app = armarApp(notifier, { PUSH_MAX_TOKENS_PER_ALERT: '1' });
    await app.ready();
    await crearGuardia();
    await crearGuardia();
    const d = await crearDueno();
    expect((await crear(d.access, cuerpo())).status).toBe(201);
    await esperarLlamadas(notifier, 1);
    expect(notifier.calls[0]?.tokens).toHaveLength(1);
  });
});

describe('tokens inválidos', () => {
  it('se borran los inválidos de destinatarios; uno inválido que no se envió (otra guardia fuera de radio) NO se borra', async () => {
    const a = await crearGuardia();
    const b = await crearGuardia();
    const lejana = await crearGuardia({ centro: FUERA, radio: 1000 });
    const rec = createRecordingNotifier((i): PushResult => ({
      sent: i.tokens.length - 1, failed: 1, invalidTokens: [a.token, lejana.token, 'token-que-no-existe'],
    }));
    const al = await alertaBuscando();
    const { dispatcher } = despachadorDirecto(rec);
    await dispatcher.dispatchAlert(al.id);
    const quedan = (await db.prisma.deviceToken.findMany()).map((t) => t.token).sort();
    expect(quedan).toEqual([b.token, lejana.token].sort());
  });

  it('deleteTokensOf solo borra tokens de los usuarios dados', async () => {
    const a = await crearGuardia();
    const b = await crearGuardia();
    const svc = createDevicesService({ prisma: db.prisma });
    expect(await svc.deleteTokensOf([a.token, b.token], [a.id])).toBe(1);
    expect((await db.prisma.deviceToken.findMany()).map((t) => t.token)).toEqual([b.token]);
    expect(await svc.deleteTokensOf([], [a.id])).toBe(0);
    expect(await svc.deleteTokensOf([b.token], [])).toBe(0);
    expect(await db.prisma.deviceToken.count()).toBe(1);
  });

  it('un notificador que repite el mismo token inválido no falla y se cuenta una vez', async () => {
    const a = await crearGuardia();
    const rec = createRecordingNotifier(() => ({ sent: 0, failed: 1, invalidTokens: [a.token, a.token] }));
    const al = await alertaBuscando();
    const { dispatcher, logger } = despachadorDirecto(rec);
    await dispatcher.dispatchAlert(al.id);
    expect(await db.prisma.deviceToken.count()).toBe(0);
    expect(logger.entradas.some((e) => e.nivel === 'warn' && e.obj['invalid'] === 1)).toBe(true);
  });
});

describe('findLiveDevices', () => {
  it('devuelve token y dueño solo de sesiones vivas y usuarios activos; lista vacía devuelve vacío', async () => {
    const viva = await crearGuardia();
    const revocada = await crearGuardia();
    const vencida = await crearGuardia();
    const inactiva = await crearGuardia();
    await db.prisma.refreshToken.updateMany({ where: { userId: revocada.id }, data: { revokedAt: new Date() } });
    await db.prisma.refreshToken.updateMany({ where: { userId: vencida.id }, data: { expiresAt: new Date(0) } });
    await db.prisma.user.update({ where: { id: inactiva.id }, data: { isActive: false } });
    const svc = createDevicesService({ prisma: db.prisma });
    const ids = [viva.id, revocada.id, vencida.id, inactiva.id];
    expect(await svc.findLiveDevices(ids)).toEqual([{ token: viva.token, userId: viva.id }]);
    expect(await svc.findLiveTokens(ids)).toEqual([viva.token]);
    expect(await svc.findLiveDevices([])).toEqual([]);
    // Reloj inyectado: en el futuro lejano la sesión ya venció.
    expect(await svc.findLiveDevices([viva.id], new Date('2999-01-01T00:00:00Z'))).toEqual([]);
  });
});

describe('el push no afecta a la respuesta HTTP', () => {
  it('un notificador que no resuelve no retrasa el 201', async () => {
    await app.close();
    let liberar: (r: PushResult) => void = () => undefined;
    const llamadas: PushAlertInput[] = [];
    const lento: PushNotifier = {
      sendAlert: (i) => {
        llamadas.push(i);
        return new Promise<PushResult>((r) => { liberar = r; });
      },
    };
    app = armarApp(lento);
    await app.ready();
    await crearGuardia();
    const d = await crearDueno();
    const res = await crear(d.access, cuerpo());
    expect(res.status).toBe(201);
    await esperar(() => llamadas.length === 1);
    liberar({ sent: 1, failed: 0, invalidTokens: [] });
  });

  it('un notificador que lanza no rompe la respuesta ni deja promesas rechazadas sin manejar', async () => {
    await app.close();
    const sin: unknown[] = [];
    const alRechazar = (r: unknown) => void sin.push(r);
    process.on('unhandledRejection', alRechazar);
    try {
      let intentos = 0;
      const roto: PushNotifier = {
        sendAlert: () => { intentos += 1; return Promise.reject(new Error('TOKEN-SECRETO falló')); },
      };
      app = armarApp(roto);
      await app.ready();
      await crearGuardia();
      const d = await crearDueno();
      const res = await crear(d.access, cuerpo());
      expect(res.status).toBe(201);
      expect(res.body.data.status).toBe('searching');
      await esperar(() => intentos === 1);
      await asentar();
      expect(sin).toEqual([]);
    } finally {
      process.off('unhandledRejection', alRechazar);
    }
  });

  it('notifyPublished no lanza ni espera; el fallo deja solo {alertId, errorType}', async () => {
    const g = await crearGuardia();
    const a = await alertaBuscando();
    class FalloRaro extends Error { override name = 'FalloRaro'; }
    const roto: PushNotifier = { sendAlert: () => Promise.reject(new FalloRaro(`secreto ${g.token} 18.84 7770000000`)) };
    const { dispatcher, logger } = despachadorDirecto(roto);
    expect(dispatcher.notifyPublished(a.id)).toBeUndefined();
    await esperar(() => logger.entradas.length > 0);
    expect(logger.entradas).toEqual([
      expect.objectContaining({ nivel: 'warn', obj: { alertId: a.id, errorType: 'FalloRaro' } }),
    ]);
    expect(JSON.stringify(logger.entradas)).not.toContain(g.token);
  });

  it('un valor no-Error rechazado se registra por su typeof', async () => {
    await crearGuardia();
    const a = await alertaBuscando();
    const roto: PushNotifier = { sendAlert: () => Promise.reject('texto-secreto') };
    const { dispatcher, logger } = despachadorDirecto(roto);
    dispatcher.notifyPublished(a.id);
    await esperar(() => logger.entradas.length > 0);
    expect(logger.entradas[0]?.obj).toEqual({ alertId: a.id, errorType: 'string' });
  });

  it('un fallo de base de datos al despachar también se absorbe', async () => {
    const logger = espiaLogger();
    const prismaRoto = { alert: { findUnique: () => Promise.reject(new TypeError('boom')) } } as never;
    const dispatcher = createAlertDispatcher({
      prisma: prismaRoto, push: notifier, devices: createDevicesService({ prisma: db.prisma }), logger,
      timeZone: ZONA, maxTokensPerAlert: 10, enabled: true,
    });
    const id = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
    dispatcher.notifyPublished(id);
    await esperar(() => logger.entradas.length > 0);
    expect(logger.entradas[0]?.obj).toEqual({ alertId: id, errorType: 'TypeError' });
  });
});

describe('logs del despachador', () => {
  it('solo llevan ids y conteos: sin tokens, coordenadas ni teléfonos', async () => {
    const a = await crearGuardia({ ultima: { lat: 18.8433, lng: -99.1811 } });
    const b = await crearGuardia();
    const dueno = await crearUsuario(db.prisma, { passwordHash, phone: '7779998888' });
    const al = await crearAlerta(db.prisma, dueno.id, { status: 'searching', lat: 18.8412, lng: -99.1777 });
    const rec = createRecordingNotifier((i) => ({ sent: 1, failed: 1, invalidTokens: [i.tokens[0] ?? ''] }));
    const { dispatcher, logger } = despachadorDirecto(rec, { max: 1 });
    await dispatcher.dispatchAlert(al.id);
    expect(logger.entradas.length).toBeGreaterThanOrEqual(2);
    const texto = JSON.stringify(logger.entradas);
    for (const prohibido of [a.token, b.token, '7779998888', '18.8412', '-99.1777', '18.8433', '-99.1811']) {
      expect(texto).not.toContain(prohibido);
    }
    const info = logger.entradas.find((e) => e.nivel === 'info');
    expect(info?.obj).toEqual({ alertId: al.id, recipients: 1, sent: 1, failed: 1 });
  });
});

describe('despachador desactivado', () => {
  it('enabled=false no consulta la base ni envía', async () => {
    const push = createRecordingNotifier();
    const prohibido = new Proxy({}, { get() { throw new Error('no debe consultar'); } }) as never;
    const devices = { findLiveDevices: vi.fn(), deleteTokensOf: vi.fn() };
    const dispatcher = createAlertDispatcher({
      prisma: prohibido, push, devices, logger: espiaLogger(), timeZone: ZONA, maxTokensPerAlert: 5, enabled: false,
    });
    const id = '3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11';
    await expect(dispatcher.dispatchAlert(id)).resolves.toBeUndefined();
    dispatcher.notifyPublished(id);
    await asentar();
    expect(devices.findLiveDevices).not.toHaveBeenCalled();
    expect(push.calls).toHaveLength(0);
  });

  it('sin push inyectado y PUSH_PROVIDER=none la API crea alertas con normalidad y no consulta tokens', async () => {
    const espia = vi.spyOn(db.prisma.deviceToken, 'findMany');
    const sinPush = buildApp(configPrueba(), { prisma: db.prisma });
    await sinPush.ready();
    try {
      await crearGuardia();
      const d = await crearDueno();
      await db.prisma.deviceToken.findMany();
      expect(espia).toHaveBeenCalled(); // el espía sí observa las consultas
      espia.mockClear();
      const res = await request(sinPush.server).post(`${API}/alerts`).set('Authorization', `Bearer ${d.access}`).send(cuerpo());
      expect(res.status).toBe(201);
      await asentar();
      expect(espia).not.toHaveBeenCalled();
    } finally {
      espia.mockRestore();
      await sinPush.close();
    }
  });
});
