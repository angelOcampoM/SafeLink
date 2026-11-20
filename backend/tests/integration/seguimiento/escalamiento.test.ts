// BE-05 · Escalamiento automático (U-09, A-04, D14) y resolución por el admin (A-04, A-08)
// contra la base de pruebas, con las rutas reales del usuario y del guardia.
//
// La revisión automática está apagada en las pruebas (ESCALATION_SWEEP_SECONDS = 0): cada caso
// "envejece" la alerta moviendo `statusChangedAt` hacia atrás y llama a `app.escalation.sweep()`.
//
// NOTA: necesita DATABASE_URL_TEST (docker compose up -d db + npm run db:test:create).
import request from 'supertest';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { crearEntorno, type Entorno } from '../auth/helpers.js';
import {
  API,
  CENTRO_ALERTA,
  asignarGuardia,
  prepararPerfilGuardia,
  tokenDe,
} from '../flujo/guardia-flujo.js';
import { abrirSse, type ConexionSse } from '../sse-helpers.js';

let env: Entorno;
let tokenUsuario: string;
let tokenGuardia: string;
let tokenAdmin: string;
const abiertas: ConexionSse[] = [];

beforeAll(async () => {
  // Límites cortos solo para leerlos; el tiempo se simula moviendo statusChangedAt.
  env = await crearEntorno({ ACCEPT_TIMEOUT_SECONDS: '300', CONFIRM_TIMEOUT_SECONDS: '900', SSE_PING_SECONDS: '60' });
}, 120_000);
afterAll(async () => {
  await env.cerrar();
});
beforeEach(async () => {
  await env.prisma.alert.deleteMany();
  await env.prisma.user.updateMany({ data: { falseAlarmCount: 0 } });
  await env.prisma.user.update({ where: { id: env.usuarios.protegido.id }, data: { blockedUntil: null } });
  await prepararPerfilGuardia(env, env.usuarios.guardia.id);
  tokenUsuario = await tokenDe(env, env.usuarios.protegido.email);
  tokenGuardia = await tokenDe(env, env.usuarios.guardia.email);
  tokenAdmin = await tokenDe(env, env.usuarios.admin.email);
});
afterEach(() => {
  for (const c of abiertas.splice(0)) c.cerrar();
});

const auth = (t: string) => ({ Authorization: `Bearer ${t}` });
const escalation = () => {
  if (!env.app.escalation) throw new Error('La app no expone el escalamiento');
  return env.app.escalation;
};

async function crearAlerta(location: { lat: number; lng: number } | null = CENTRO_ALERTA): Promise<string> {
  const res = await request(env.app.server)
    .post(`${API}/alerts`)
    .set(auth(tokenUsuario))
    .send({ triggerMethod: 'tap', triggeredAt: new Date().toISOString(), location, heading: 35, photoPath: null });
  expect(res.status, JSON.stringify(res.body)).toBe(201);
  return res.body.data.id as string;
}

/** Simula que la alerta lleva `segundos` en su estado actual. */
async function envejecer(alertId: string, segundos: number): Promise<void> {
  await env.prisma.alert.update({
    where: { id: alertId },
    data: { statusChangedAt: new Date(Date.now() - segundos * 1000) },
  });
}

async function abrir(ruta: string, t: string): Promise<ConexionSse> {
  const c = await abrirSse(env.app, `${API}${ruta}`, t);
  abiertas.push(c);
  return c;
}

const resolver = (alertId: string, cuerpo: object, t = tokenAdmin) =>
  request(env.app.server).post(`${API}/admin/alerts/${alertId}/resolve`).set(auth(t)).send(cuerpo);

async function escalada(): Promise<string> {
  const id = await crearAlerta();
  await envejecer(id, 301);
  await escalation().sweep();
  return id;
}

// ── Escalamiento automático ──────────────────────────────────────────

describe('escalamiento automático', () => {
  it('U-09 · A-04: nadie acepta a tiempo -> escalated con motivo "sin respuesta", sin guardia', async () => {
    const id = await crearAlerta();
    await envejecer(id, 301);

    const escaladas = await escalation().sweep();

    expect(escaladas.map((e) => e.alertId)).toEqual([id]);
    const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
    expect(a).toMatchObject({ status: 'escalated', escalationReason: 'no_response', guardId: null, closedAt: null });
    // D14: se guarda directo como escalated (no_response no queda como estado intermedio).
    const historial = await env.prisma.alertStatusHistory.findMany({ where: { alertId: id }, orderBy: { at: 'asc' } });
    expect(historial.map((h) => [h.fromStatus, h.toStatus, h.actorId])).toEqual([
      [null, 'searching', env.usuarios.protegido.id],
      ['searching', 'escalated', null],
    ]);
  });

  it('antes del límite no escala nada', async () => {
    const id = await crearAlerta();
    await envejecer(id, 299);
    expect(await escalation().sweep()).toEqual([]);
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id } })).status).toBe('searching');
  });

  it('el guardia llegó y el usuario no confirma a tiempo -> "sin confirmación", conserva al guardia', async () => {
    const id = await crearAlerta();
    await asignarGuardia(env, tokenGuardia, id, 'guard_arrived');
    await envejecer(id, 901);

    await escalation().sweep();

    const a = await env.prisma.alert.findUniqueOrThrow({ where: { id } });
    expect(a).toMatchObject({ status: 'escalated', escalationReason: 'no_confirmation', guardId: env.usuarios.guardia.id });
  });

  it('D23: el guardia que atendió ve la escalada sin teléfono ni ubicación del usuario', async () => {
    const id = await crearAlerta();
    await asignarGuardia(env, tokenGuardia, id, 'guard_arrived');
    await envejecer(id, 901);
    await escalation().sweep();

    const res = await request(env.app.server).get(`${API}/guard/alerts/${id}`).set(auth(tokenGuardia));

    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({ status: 'escalated', userPhone: null, location: null });
  });

  it('nunca escala una alerta en atención ni una pendiente de ubicación (D14)', async () => {
    const enAtencion = await crearAlerta();
    await asignarGuardia(env, tokenGuardia, enAtencion, 'in_progress');
    await envejecer(enAtencion, 86_400);
    await env.prisma.alert.update({ where: { id: enAtencion }, data: { status: 'closed', closedAt: new Date() } });
    // Una alerta por usuario (D15): la pendiente se crea después de cerrar la otra.
    const pendiente = await crearAlerta(null);
    await envejecer(pendiente, 86_400);

    expect(await escalation().sweep()).toEqual([]);
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id: pendiente } })).status).toBe('pending_location');
  });

  it('in_progress vencida no escala (el guardia sigue en camino)', async () => {
    const id = await crearAlerta();
    await asignarGuardia(env, tokenGuardia, id, 'in_progress');
    await envejecer(id, 86_400);
    expect(await escalation().sweep()).toEqual([]);
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id } })).status).toBe('in_progress');
  });

  it('si el guardia acepta antes de la revisión, gana la aceptación', async () => {
    const id = await crearAlerta();
    await envejecer(id, 301);
    await asignarGuardia(env, tokenGuardia, id, 'in_progress');
    expect(await escalation().sweep()).toEqual([]);
    expect((await env.prisma.alert.findUniqueOrThrow({ where: { id } })).status).toBe('in_progress');
  });

  it('el usuario puede pedir ayuda otra vez: la escalada ya no es su alerta activa', async () => {
    await escalada();
    expect((await request(env.app.server).get(`${API}/alerts/mine`).set(auth(tokenUsuario))).body.data[0].status).toBe(
      'escalated',
    );
    await crearAlerta();
  });

  it('una segunda revisión no la vuelve a escalar', async () => {
    await escalada();
    expect(await escalation().sweep()).toEqual([]);
  });
});

// ── Avisos en tiempo real ────────────────────────────────────────────

describe('avisos en tiempo real al escalar', () => {
  it('alerts/active del usuario pasa a null (vuelve el botón de alerta)', async () => {
    const id = await crearAlerta();
    const c = await abrir('/events/alerts/active', tokenUsuario);
    expect(((await c.siguiente()) as { data: { id: string } }).data.id).toBe(id);

    await envejecer(id, 301);
    await escalation().sweep();

    expect(await c.siguiente()).toEqual({ data: null });
  });

  it('la alerta sale del listado de los guardias', async () => {
    const id = await crearAlerta();
    const c = await abrir('/events/guard/alerts', tokenGuardia);
    const inicial = (await c.siguiente()) as { data: Array<{ alert: { id: string } }> };
    expect(inicial.data.map((p) => p.alert.id)).toContain(id);

    await envejecer(id, 301);
    await escalation().sweep();

    const despues = (await c.siguiente()) as { data: Array<{ alert: { id: string } }> };
    expect(despues.data.map((p) => p.alert.id)).not.toContain(id);
  });

  it('A-04: la bandeja del admin la recibe con su motivo, completa, y la pierde al resolverse', async () => {
    const c = await abrir('/events/admin/alerts/escalated', tokenAdmin);
    expect(await c.siguiente()).toEqual({ data: [] });

    const id = await crearAlerta();
    await envejecer(id, 301);
    await escalation().sweep();

    const bandeja = (await c.siguiente()) as { data: Array<Record<string, unknown>> };
    expect(bandeja.data).toHaveLength(1);
    expect(bandeja.data[0]).toMatchObject({
      id,
      status: 'escalated',
      escalationReason: 'no_response',
      userPhone: '7771234567',
      location: CENTRO_ALERTA,
    });

    await resolver(id, { resolution: 'resolved', adminNote: 'Se contactó al usuario' });
    expect(await c.siguiente()).toEqual({ data: [] });
  });

  it('solo el admin abre la bandeja', async () => {
    const c = await abrir('/events/admin/alerts/escalated', tokenGuardia);
    expect(c.status).toBe(403);
  });
});

// ── POST /admin/alerts/:id/resolve ───────────────────────────────────

describe('POST /admin/alerts/:id/resolve', () => {
  it('A-04: resuelve la escalada con su resolución y nota, y le pone hora de cierre', async () => {
    const id = await escalada();

    const res = await resolver(id, { resolution: 'service_incident', adminNote: '  El guardia no llegó a tiempo  ' });

    expect(res.status).toBe(200);
    expect(res.body.data).toMatchObject({
      id,
      status: 'resolved_by_admin',
      resolution: 'service_incident',
      adminNote: 'El guardia no llegó a tiempo',
      escalationReason: 'no_response', // se conserva después de resolver
    });
    expect(res.body.data.closedAt).toEqual(expect.any(String));
    const ultimo = await env.prisma.alertStatusHistory.findFirstOrThrow({ where: { alertId: id }, orderBy: { at: 'desc' } });
    expect(ultimo).toMatchObject({ fromStatus: 'escalated', toStatus: 'resolved_by_admin', actorId: env.usuarios.admin.id });
  });

  it('primero el estado y luego la nota: una no escalada responde 409 aunque la nota esté vacía', async () => {
    const id = await crearAlerta();
    const res = await resolver(id, { resolution: 'resolved', adminNote: '' });
    expect(res.status).toBe(409);
    expect(res.body.error).toEqual({ code: 'INVALID_STATE', message: 'Esta alerta ya no está escalada' });
  });

  it('exige una nota de 1 a ADMIN_NOTE_MAX_LENGTH caracteres', async () => {
    const id = await escalada();
    const vacia = await resolver(id, { resolution: 'resolved', adminNote: '   ' });
    expect(vacia.status).toBe(400);
    expect(vacia.body.error.message).toBe('Escribe una nota administrativa para resolver la alerta');
    const larga = await resolver(id, { resolution: 'resolved', adminNote: 'a'.repeat(301) });
    expect(larga.status).toBe(400);
    expect(larga.body.error.message).toBe('La nota no puede pasar de 300 caracteres');
  });

  it('no se resuelve dos veces', async () => {
    const id = await escalada();
    expect((await resolver(id, { resolution: 'resolved', adminNote: 'Listo' })).status).toBe(200);
    const otra = await resolver(id, { resolution: 'false_alarm', adminNote: 'Otra vez' });
    expect(otra.status).toBe(409);
    const u = await env.prisma.user.findUniqueOrThrow({ where: { id: env.usuarios.protegido.id } });
    expect(u.falseAlarmCount).toBe(0);
  });

  it('una alerta que no existe responde 404; una resolución inventada, 400', async () => {
    const res = await resolver('3f2b8c1e-9a4d-4e6b-8f10-2c7d5a9b0e11', { resolution: 'resolved', adminNote: 'x' });
    expect(res.status).toBe(404);
    expect(res.body.error.message).toBe('La alerta ya no existe');
    const id = await escalada();
    expect((await resolver(id, { resolution: 'closed', adminNote: 'x' })).status).toBe(400);
  });

  it('A-08: cada falsa alarma suma; a la tercera el usuario queda bloqueado BLOCK_DAYS días', async () => {
    for (let i = 1; i <= 3; i++) {
      const id = await escalada();
      const res = await resolver(id, { resolution: 'false_alarm', adminNote: `Falsa alarma ${String(i)}` });
      expect(res.status).toBe(200);
      const u = await env.prisma.user.findUniqueOrThrow({ where: { id: env.usuarios.protegido.id } });
      expect(u.falseAlarmCount).toBe(i);
      if (i < 3) {
        expect(u.blockedUntil).toBeNull();
      } else {
        const dias = ((u.blockedUntil?.getTime() ?? 0) - Date.now()) / 86_400_000;
        expect(dias).toBeGreaterThan(6.99);
        expect(dias).toBeLessThanOrEqual(7);
      }
    }
    // El bloqueado ya no puede pedir ayuda (U-03 · A-08).
    const bloqueado = await request(env.app.server)
      .post(`${API}/alerts`)
      .set(auth(tokenUsuario))
      .send({ triggerMethod: 'tap', triggeredAt: new Date().toISOString(), location: CENTRO_ALERTA, heading: 1, photoPath: null });
    expect(bloqueado.status).toBe(403);
    expect(bloqueado.body.error.code).toBe('USER_BLOCKED');
  });

  it('resolver como resuelta o incidencia no cuenta como falsa alarma', async () => {
    for (const resolution of ['resolved', 'service_incident']) {
      const id = await escalada();
      await resolver(id, { resolution, adminNote: 'Atendida' });
    }
    const u = await env.prisma.user.findUniqueOrThrow({ where: { id: env.usuarios.protegido.id } });
    expect(u.falseAlarmCount).toBe(0);
  });

  it('solo el admin resuelve', async () => {
    const id = await escalada();
    const res = await resolver(id, { resolution: 'resolved', adminNote: 'x' }, tokenGuardia);
    expect(res.status).toBe(403);
  });
});
