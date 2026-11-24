// BE-03 · Alertas del usuario protegido contra la base de pruebas (U-03 a U-09).
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import request from 'supertest';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { etaSeconds, roundEtaUp } from '../../../src/domain/alert-rules.js';
import { snapToGrid } from '../../../src/domain/geo.js';
import { configPrueba, crearEntorno, login, type Entorno } from '../auth/helpers.js';
import {
  CENTRO_ALERTA,
  LEJOS_DE_ALERTA,
  asignarGuardia as asignarGuardiaPorApi,
  prepararPerfilGuardia,
  tokenDe,
} from '../flujo/guardia-flujo.js';

const API = '/api/v1';
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00]);

let env: Entorno;
let tokenUsuario: string;
let tokenGuardia: string;
let dirFotos: string;

beforeAll(async () => {
  dirFotos = await mkdtemp(join(tmpdir(), 'safelink-fotos-'));
  env = await crearEntorno({ PHOTO_DIR: dirFotos, PHOTO_MAX_BYTES: '1024' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
  await rm(dirFotos, { recursive: true, force: true });
});

beforeEach(async () => {
  await env.prisma.alert.deleteMany();
  tokenUsuario = await token(env.usuarios.protegido.email);
  // D46: el guardia real (perfil con cobertura y turno de 24 h) atiende por las rutas de BE-04.
  await prepararPerfilGuardia(env, env.usuarios.guardia.id);
  tokenGuardia = await tokenDe(env, env.usuarios.guardia.email);
});

async function token(email: string): Promise<string> {
  const res = await login(env.app, email);
  return res.body.data.accessToken as string;
}

const conToken = (t: string) => ({ Authorization: `Bearer ${t}` });

const cuerpo = (extra: Record<string, unknown> = {}) => ({
  triggerMethod: 'tap',
  triggeredAt: new Date().toISOString(),
  location: { lat: 18.84, lng: -99.18 },
  heading: 35,
  photoPath: '/data/user/0/mx.safelink/cache/foto.jpg',
  ...extra,
});

const crear = (body: object, t = tokenUsuario) =>
  request(env.app.server).post(`${API}/alerts`).set(conToken(t)).send(body);

/** D46: el guardia acepta (y llega) por POST /guard/alerts/:id/accept y /arrive, con PUT /guard/location. */
const asignarGuardia = (
  alertId: string,
  status: 'in_progress' | 'guard_arrived',
  ubicacion?: { lat: number; lng: number },
) => asignarGuardiaPorApi(env, tokenGuardia, alertId, status, ubicacion);

// ── POST /alerts ──────────────────────────────────────────────────────

describe('POST /alerts', () => {
  it('U-03: crea la alerta buscando guardia y responde 201 con la forma completa', async () => {
    const res = await crear(cuerpo());

    expect(res.status).toBe(201);
    const a = res.body.data;
    expect(a.status).toBe('searching');
    expect(a.triggerMethod).toBe('tap');
    expect(a.userId).toBe(env.usuarios.protegido.id);
    expect(a.userName).toBe('Nombre protegido');
    expect(a.location).toEqual({ lat: 18.84, lng: -99.18 });
    expect(a.heading).toBe(35);
    expect(a.guardId).toBeNull();
    expect(a.etaSeconds).toBeNull();
    expect(Object.keys(a)).toHaveLength(20);
  });

  it('registra cada método de disparo tal cual (U-03 toque, U-04 mantener, U-05 doble clic)', async () => {
    for (const metodo of ['tap', 'hold', 'shake']) {
      await env.prisma.alert.deleteMany();
      const res = await crear(cuerpo({ triggerMethod: metodo }));
      expect(res.status).toBe(201);
      expect(res.body.data.triggerMethod).toBe(metodo);
    }
  });

  it('U-06: sin foto guardada la alerta se envía igual y queda como evidencia incompleta', async () => {
    const res = await crear(cuerpo({ photoPath: null }));
    expect(res.status).toBe(201);
    expect(res.body.data.evidenceIncomplete).toBe(true);
    expect(res.body.data.photoUrl).toBeNull();
  });

  it('U-06: sin coordenadas queda pendiente de ubicación (no se publica a los guardias)', async () => {
    const res = await crear(cuerpo({ location: null }));
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('pending_location');
    expect(res.body.data.location).toBeNull();
  });

  it('D24: guarda la hora del servidor aparte y recorta un triggeredAt desfasado', async () => {
    const res = await crear(cuerpo({ triggeredAt: '2020-01-01T00:00:00.000Z' }));
    expect(res.status).toBe(201);
    const guardada = await env.prisma.alert.findUniqueOrThrow({ where: { id: res.body.data.id as string } });
    expect(guardada.triggeredAt.getTime()).toBe(guardada.receivedAt.getTime());
    expect(res.body.data.triggeredAt).toBe(guardada.receivedAt.toISOString());
  });

  it('deja el primer registro en el historial de estados', async () => {
    const res = await crear(cuerpo());
    const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: res.body.data.id as string } });
    expect(historial).toHaveLength(1);
    expect(historial[0]).toMatchObject({ fromStatus: null, toStatus: 'searching', actorId: env.usuarios.protegido.id });
  });

  it('D15: con otra alerta activa responde 409 y no crea una segunda', async () => {
    await crear(cuerpo());
    const res = await crear(cuerpo());
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'INVALID_STATE', message: 'Ya tienes una alerta activa' });
    expect(await env.prisma.alert.count({ where: { userId: env.usuarios.protegido.id } })).toBe(1);
  });

  it('A-08: un usuario bloqueado recibe USER_BLOCKED y no crea nada', async () => {
    const res = await crear(cuerpo(), await token(env.usuarios.bloqueado.email));
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('USER_BLOCKED');
    expect(await env.prisma.alert.count()).toBe(0);
  });

  it('rechaza un cuerpo inválido con 400 INVALID_STATE', async () => {
    const res = await crear(cuerpo({ heading: 400 }));
    expect(res.status).toBe(400);
    expect(res.body.error).toEqual({ code: 'INVALID_STATE', message: 'El rumbo no es válido' });
  });

  it('solo el usuario protegido puede crear alertas', async () => {
    const res = await crear(cuerpo(), await token(env.usuarios.guardia.email));
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });
});

// ── GET /alerts/mine ──────────────────────────────────────────────────

describe('GET /alerts/mine', () => {
  it('devuelve solo las alertas propias, la más reciente primero', async () => {
    await env.prisma.alert.create({
      data: { userId: env.usuarios.protegido.id, status: 'closed', triggerMethod: 'hold', triggeredAt: new Date('2026-01-01T00:00:00Z'), guardId: env.usuarios.guardia.id, closedAt: new Date('2026-01-01T01:00:00Z') },
    });
    await crear(cuerpo());
    await env.prisma.alert.create({
      data: { userId: env.usuarios.bloqueado.id, status: 'closed', triggerMethod: 'tap', triggeredAt: new Date(), guardId: env.usuarios.guardia.id, closedAt: new Date() },
    });

    const res = await request(env.app.server).get(`${API}/alerts/mine`).set(conToken(tokenUsuario));

    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.data[0].status).toBe('searching');
    expect(res.body.data[1].status).toBe('closed');
    for (const a of res.body.data as Array<{ userId: string }>) expect(a.userId).toBe(env.usuarios.protegido.id);
  });
});

// ── POST /alerts/:id/locations ────────────────────────────────────────

describe('POST /alerts/:id/locations', () => {
  const enviar = (id: string, location: object, t = tokenUsuario) =>
    request(env.app.server).post(`${API}/alerts/${id}/locations`).set(conToken(t)).send({ location });

  it('U-07: actualiza la posición de la alerta activa y responde data null', async () => {
    const creada = await crear(cuerpo());
    const id = creada.body.data.id as string;

    const res = await enviar(id, { lat: 18.85, lng: -99.17 });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ data: null });
    const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
    expect({ lat: a.lat, lng: a.lng, status: a.status }).toEqual({ lat: 18.85, lng: -99.17, status: 'searching' });
  });

  it('U-06: la primera ubicación de una alerta pendiente la publica', async () => {
    const creada = await crear(cuerpo({ location: null }));
    const id = creada.body.data.id as string;

    await enviar(id, { lat: 18.84, lng: -99.18 });

    const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
    expect(a.status).toBe('searching');
    const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: id }, orderBy: { at: 'asc' } });
    expect(historial.map((h) => h.toStatus)).toEqual(['pending_location', 'searching']);
  });

  it('U-07: con la alerta cerrada deja de guardar la ubicación (409)', async () => {
    const creada = await crear(cuerpo());
    const id = creada.body.data.id as string;
    await env.prisma.alert.update({ where: { id }, data: { status: 'escalated', escalationReason: 'no_response' } });

    const res = await enviar(id, { lat: 18.9, lng: -99.1 });

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('INVALID_STATE');
    const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
    expect(a.lat).toBe(18.84);
  });

  it('la alerta de otro usuario no existe para mí (404)', async () => {
    const ajena = await env.prisma.alert.create({
      data: { userId: env.usuarios.bloqueado.id, status: 'searching', triggerMethod: 'tap', triggeredAt: new Date(), lat: 1, lng: 1 },
    });
    const res = await enviar(ajena.id, { lat: 18.85, lng: -99.17 });
    expect(res.status).toBe(404);
    expect(res.body.error).toEqual({ code: 'NOT_FOUND', message: 'La alerta ya no existe' });
  });

  it('un id que no es UUID responde 404', async () => {
    const res = await enviar('alt-101', { lat: 18.85, lng: -99.17 });
    expect(res.status).toBe(404);
  });
});

// ── POST /alerts/:id/confirm ──────────────────────────────────────────

describe('POST /alerts/:id/confirm', () => {
  const confirmar = (id: string) =>
    request(env.app.server).post(`${API}/alerts/${id}/confirm`).set(conToken(tokenUsuario));

  it('U-09: sin que el guardia haya llegado responde 409 con el mensaje del front', async () => {
    const creada = await crear(cuerpo());
    const id = creada.body.data.id as string;

    for (const estado of ['searching', 'in_progress'] as const) {
      if (estado === 'in_progress') await asignarGuardia(id, 'in_progress');
      const res = await confirmar(id);
      expect(res.status).toBe(409);
      expect(res.body.error).toEqual({ code: 'INVALID_STATE', message: 'Solo puedes confirmar cuando el guardia ya llegó' });
    }
  });

  it('U-09: con el guardia en el lugar cierra la alerta y deja de ser la activa', async () => {
    const creada = await crear(cuerpo());
    const id = creada.body.data.id as string;
    await asignarGuardia(id, 'guard_arrived');

    const res = await confirmar(id);

    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('closed');
    expect(res.body.data.closedAt).toEqual(expect.any(String));
    expect(res.body.data.guardName).toBe('Nombre guardia');
    // Ya puede disparar otra alerta.
    expect((await crear(cuerpo())).status).toBe(201);
  });

  it('U-08: con el guardia en camino el dueño ve su nombre y el tiempo estimado', async () => {
    const creada = await crear(cuerpo());
    const id = creada.body.data.id as string;
    await asignarGuardia(id, 'in_progress', LEJOS_DE_ALERTA);

    const res = await request(env.app.server).get(`${API}/alerts/mine`).set(conToken(tokenUsuario));
    const a = res.body.data[0];

    expect(a.guardName).toBe('Nombre guardia');
    expect(a.etaSeconds).toEqual(expect.any(Number));
    expect(a.etaSeconds).toBeGreaterThan(0);
    // D47: la vista del dueño ajusta al guardia a su celda y redondea hacia arriba (valor exacto del contrato).
    const cfg = configPrueba();
    expect(a.etaSeconds).toBe(
      roundEtaUp(
        etaSeconds('in_progress', snapToGrid(LEJOS_DE_ALERTA, cfg.ETA_GUARD_GRID_METERS), CENTRO_ALERTA, cfg.GUARD_METERS_PER_MINUTE),
        cfg.ETA_ROUNDING_SECONDS,
      ),
    );
  });
});

// ── Foto de evidencia (D2) ────────────────────────────────────────────

describe('POST /alerts con foto (multipart) y GET /alerts/:id/photo', () => {
  const conFoto = (foto: Buffer | null, data: object = cuerpo(), t = tokenUsuario) => {
    const r = request(env.app.server)
      .post(`${API}/alerts`)
      .set(conToken(t))
      .field('data', JSON.stringify(data));
    return foto ? r.attach('photo', foto, { filename: 'foto.jpg', contentType: 'image/jpeg' }) : r;
  };

  it('U-06: guarda la foto, la alerta queda completa y la URL firmada la sirve', async () => {
    const res = await conFoto(JPEG);

    expect(res.status).toBe(201);
    expect(res.body.data.evidenceIncomplete).toBe(false);
    const url = new URL(res.body.data.photoUrl as string);
    expect(url.pathname).toBe(`${API}/alerts/${res.body.data.id as string}/photo`);

    const foto = await request(env.app.server).get(`${url.pathname}${url.search}`);
    expect(foto.status).toBe(200);
    expect(foto.headers['content-type']).toBe('image/jpeg');
    expect(foto.headers['x-content-type-options']).toBe('nosniff');
    expect(Buffer.from(foto.body as Buffer)).toEqual(JPEG);
  });

  it('multipart sin foto: se crea con evidencia incompleta', async () => {
    const res = await conFoto(null);
    expect(res.status).toBe(201);
    expect(res.body.data.evidenceIncomplete).toBe(true);
    expect(res.body.data.photoUrl).toBeNull();
  });

  it('rechaza un archivo que no es imagen aunque diga image/jpeg', async () => {
    const res = await conFoto(Buffer.from('<script>alert(1)</script>'));
    expect(res.status).toBe(400);
    expect(res.body.error).toEqual({ code: 'INVALID_STATE', message: 'La foto no es una imagen válida' });
    expect(await env.prisma.alert.count()).toBe(0);
  });

  it('rechaza una foto mayor a PHOTO_MAX_BYTES', async () => {
    const res = await conFoto(Buffer.concat([JPEG, Buffer.alloc(2048)]));
    expect(res.status).toBe(400);
    expect(res.body.error.message).toBe('La foto es demasiado grande');
  });

  it('si la alerta no se crea, la foto no queda guardada', async () => {
    await crear(cuerpo());
    const antes = await readdir(dirFotos);
    const res = await conFoto(JPEG);
    expect(res.status).toBe(409);
    expect(await readdir(dirFotos)).toEqual(antes);
  });

  it('sin firma, con firma alterada o de otra alerta responde 404', async () => {
    const res = await conFoto(JPEG);
    const url = new URL(res.body.data.photoUrl as string);
    const id = res.body.data.id as string;
    const sig = url.searchParams.get('sig') ?? '';
    const exp = url.searchParams.get('exp') ?? '';

    for (const ruta of [
      `${API}/alerts/${id}/photo`,
      `${API}/alerts/${id}/photo?exp=${exp}&sig=${'0'.repeat(64)}`,
      `${API}/alerts/${id}/photo?exp=${String(Number(exp) + 1)}&sig=${sig}`,
      `${API}/alerts/3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11/photo?exp=${exp}&sig=${sig}`,
    ]) {
      const r = await request(env.app.server).get(ruta);
      expect(r.status, ruta).toBe(404);
      expect(r.body.error.code).toBe('NOT_FOUND');
    }
  });
});
