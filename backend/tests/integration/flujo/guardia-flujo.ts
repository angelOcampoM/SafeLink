// Utilidades para pruebas que necesitan al guardia en el flujo real de BE-04 (D46):
// perfil con cobertura y turno, PUT /guard/location, accept y arrive por la API, sin escribir
// estados de alerta directo en la base.
import request from 'supertest';
import { expect } from 'vitest';
import { login, type Entorno } from '../auth/helpers.js';

export const API = '/api/v1';

/** Ubicación de las alertas de estas pruebas (la misma que usan los cuerpos de POST /alerts). */
export const CENTRO_ALERTA = { lat: 18.84, lng: -99.18 };
/** ~22 m del centro: dentro de GEOFENCE_METERS (50 por defecto). */
export const JUNTO_A_ALERTA = { lat: 18.8402, lng: -99.18 };
/** ~1.1 km al norte del centro: en cobertura pero lejos de la geocerca. */
export const LEJOS_DE_ALERTA = { lat: 18.85, lng: -99.18 };

/** Perfil de guardia con cobertura alrededor de CENTRO_ALERTA y turno de 24 h (inicio = fin); sin última ubicación. */
export async function prepararPerfilGuardia(env: Entorno, userId: string): Promise<void> {
  const datos = {
    shiftStart: '00:00',
    shiftEnd: '00:00',
    coverageCenterLat: CENTRO_ALERTA.lat,
    coverageCenterLng: CENTRO_ALERTA.lng,
    coverageRadiusMeters: 2000,
    zone: 'Zona Centro',
    lastLocationLat: null,
    lastLocationLng: null,
    lastLocationAt: null,
  };
  await env.prisma.guardProfile.upsert({ where: { userId }, create: { userId, ...datos }, update: datos });
}

export async function tokenDe(env: Entorno, email: string): Promise<string> {
  const res = await login(env.app, email);
  expect(res.status).toBe(200);
  return res.body.data.accessToken as string;
}

const auth = (t: string) => ({ Authorization: `Bearer ${t}` });

export async function moverGuardia(env: Entorno, tokenGuardia: string, location: { lat: number; lng: number }) {
  const res = await request(env.app.server).put(`${API}/guard/location`).set(auth(tokenGuardia)).send({ location });
  expect(res.status).toBe(200);
  return res;
}

export const aceptarAlerta = (env: Entorno, tokenGuardia: string, alertId: string) =>
  request(env.app.server).post(`${API}/guard/alerts/${alertId}/accept`).set(auth(tokenGuardia));

export const registrarLlegada = (env: Entorno, tokenGuardia: string, alertId: string) =>
  request(env.app.server).post(`${API}/guard/alerts/${alertId}/arrive`).set(auth(tokenGuardia));

/**
 * Lleva una alerta `searching` a `in_progress` o `guard_arrived` solo con rutas del guardia.
 * `ubicacion`: dónde está el guardia al aceptar (define el ETA); para `guard_arrived` se acerca antes de llegar.
 */
export async function asignarGuardia(
  env: Entorno,
  tokenGuardia: string,
  alertId: string,
  status: 'in_progress' | 'guard_arrived',
  ubicacion: { lat: number; lng: number } = JUNTO_A_ALERTA,
): Promise<void> {
  await moverGuardia(env, tokenGuardia, ubicacion);
  const acepto = await aceptarAlerta(env, tokenGuardia, alertId);
  expect(acepto.status, JSON.stringify(acepto.body)).toBe(200);
  if (status === 'in_progress') return;
  await moverGuardia(env, tokenGuardia, JUNTO_A_ALERTA);
  const llego = await registrarLlegada(env, tokenGuardia, alertId);
  expect(llego.status, JSON.stringify(llego.body)).toBe(200);
}
