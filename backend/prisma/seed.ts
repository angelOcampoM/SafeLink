// Semilla de desarrollo (D13). Equivale a lib/datos/datos_semilla.dart:
// mismas cuentas, perfiles de guardia y alertas activas en cada estado.
// SIN historial sintético (va con las métricas, BE-07).
// Idempotente: todo se upserta con UUID fijos; las alertas sembradas se
// reinician (estado, fechas e historial) en cada corrida, relativas a "ahora".
// Solo corre con NODE_ENV development o test.

import { createHash } from 'node:crypto';
import argon2 from 'argon2';
import { envSchema } from '../src/config/env.js';
import { createPrisma } from '../src/db/prisma.js';
import { AlertStatus, Role, TriggerMethod } from '../src/generated/prisma/enums.js';
import type { EscalationReason, Resolution } from '../src/generated/prisma/enums.js';

// --- Utilidades --------------------------------------------------------------

/** UUID v5 (SHA-1) con un espacio de nombres fijo: ids estables entre corridas (D10). */
const NAMESPACE = '5afe11c0-0000-4000-8000-000000000001';

function uuidV5(name: string, namespace: string = NAMESPACE): string {
  const ns = Buffer.from(namespace.replaceAll('-', ''), 'hex');
  const h = createHash('sha1').update(ns).update(name, 'utf8').digest();
  h[6] = ((h[6] ?? 0) & 0x0f) | 0x50;
  h[8] = ((h[8] ?? 0) & 0x3f) | 0x80;
  const x = h.subarray(0, 16).toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20)}`;
}

interface Punto {
  lat: number;
  lng: number;
}

/** Punto a `metros` de `desde` con rumbo `grados` (aproximación plana, igual que el front). */
function aDistancia(desde: Punto, metros: number, grados: number): Punto {
  const r = (grados * Math.PI) / 180;
  return {
    lat: desde.lat + (metros * Math.cos(r)) / 111320,
    lng: desde.lng + (metros * Math.sin(r)) / (111320 * Math.cos((desde.lat * Math.PI) / 180)),
  };
}

/** "HH:mm" de un instante en la zona horaria de los turnos. */
function hhmm(t: Date, timeZone: string): string {
  const partes = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(t);
  const hh = partes.find((p) => p.type === 'hour')?.value ?? '00';
  const mm = partes.find((p) => p.type === 'minute')?.value ?? '00';
  return `${hh}:${mm}`;
}

// --- Datos -------------------------------------------------------------------

const PASSWORD = 'SafeLink1';

const centroEmilianoZapata: Punto = { lat: 18.84, lng: -99.18 };
const centroCuernavaca: Punto = { lat: 18.9186, lng: -99.2342 };
const centroYautepec: Punto = { lat: 18.8833, lng: -99.0667 };
const centroCuautla: Punto = { lat: 18.8122, lng: -98.9548 };
const centroTepoztlan: Punto = { lat: 18.985, lng: -99.099 };
const centroXochitepec: Punto = { lat: 18.78, lng: -99.23 };
const centroJojutla: Punto = { lat: 18.615, lng: -99.18 };

const ubicacionGrd1: Punto = { lat: 18.8385, lng: -99.1835 };
const ubicacionGrd2: Punto = { lat: 18.915, lng: -99.23 };
const ubicacionGrd3 = aDistancia(centroYautepec, 600, 225);
const ubicacionGrd4 = aDistancia(centroCuautla, 500, 45);
const ubicacionGrd6 = aDistancia(centroTepoztlan, 300, 180);

interface CuentaSemilla {
  key: string; // id del front (adm-1, grd-1, usr-1): origen del UUID
  name: string;
  email: string;
  phone: string;
  role: Role;
  isActive?: boolean;
  volumeDoubleClickEnabled?: boolean;
  falseAlarmCount?: number;
  blockedDays?: number; // días hacia el futuro
}

const guardias: CuentaSemilla[] = [
  { key: 'grd-1', name: 'Carlos Hernández López', email: 'guardia@safelink.mx', phone: '7772345610' },
  { key: 'grd-2', name: 'Daniela Salgado Pérez', email: 'daniela.salgado@safelink.mx', phone: '7773456721' },
  { key: 'grd-3', name: 'Jorge Ocampo Bahena', email: 'jorge.ocampo@safelink.mx', phone: '7774567832' },
  { key: 'grd-4', name: 'Ramiro Villalobos Cruz', email: 'guardia.noche@safelink.mx', phone: '7775678943' },
  { key: 'grd-5', name: 'Luis Arturo Nava Díaz', email: 'luis.nava@safelink.mx', phone: '7776789054', isActive: false },
  { key: 'grd-6', name: 'Paola Estrada Mena', email: 'paola.estrada@safelink.mx', phone: '7777890165' },
  { key: 'grd-7', name: 'Andrés Figueroa Ávila', email: 'andres.figueroa@safelink.mx', phone: '7778901276' },
  { key: 'grd-8', name: 'Sofía Rendón Campos', email: 'sofia.rendon@safelink.mx', phone: '7779012387' },
].map((g) => ({ ...g, role: Role.guard }));

const protegidos: CuentaSemilla[] = [
  { key: 'usr-1', name: 'Fernanda Morales Gil', email: 'usuario@safelink.mx', phone: '7771234567', volumeDoubleClickEnabled: true },
  { key: 'usr-2', name: 'Rosa María Díaz Toledo', email: 'rosa.diaz@mail.com', phone: '7772233445', falseAlarmCount: 2 },
  { key: 'usr-3', name: 'Héctor Jaimes Rosales', email: 'hector.jaimes@mail.com', phone: '7773344556' },
  { key: 'usr-4', name: 'Iván Castañeda Soto', email: 'bloqueado@safelink.mx', phone: '7774455667', falseAlarmCount: 3, blockedDays: 5 },
  { key: 'usr-5', name: 'Guadalupe Benítez Arce', email: 'lupita.benitez@mail.com', phone: '7775566778' },
  { key: 'usr-6', name: 'Miguel Ángel Tapia Ruiz', email: 'miguel.tapia@mail.com', phone: '7776677889', falseAlarmCount: 1 },
  { key: 'usr-7', name: 'Valeria Campos Ocampo', email: 'valeria.campos@mail.com', phone: '7777788990', volumeDoubleClickEnabled: true },
  { key: 'usr-8', name: 'Ernesto Salazar Pliego', email: 'ernesto.salazar@mail.com', phone: '7778899001' },
].map((u) => ({ ...u, role: Role.protected_user }));

const masProtegidos: [string, string][] = [
  ['Alejandra Rojas Medina', 'alejandra.rojas@mail.com'],
  ['Bruno Galindo Ortiz', 'bruno.galindo@mail.com'],
  ['Claudia Pineda Luna', 'claudia.pineda@mail.com'],
  ['Diego Sámano Reyes', 'diego.samano@mail.com'],
  ['Elena Bustamante Cruz', 'elena.bustamante@mail.com'],
  ['Fabián Olivares Mora', 'fabian.olivares@mail.com'],
  ['Gabriela Quintero Salas', 'gabriela.quintero@mail.com'],
  ['Hugo Montiel Vega', 'hugo.montiel@mail.com'],
  ['Irene Zúñiga Barrera', 'irene.zuniga@mail.com'],
  ['Javier Peralta Núñez', 'javier.peralta@mail.com'],
  ['Karla Bahena Flores', 'karla.bahena@mail.com'],
  ['Leonardo Avilés Ríos', 'leonardo.aviles@mail.com'],
  ['Mónica Trujillo Sosa', 'monica.trujillo@mail.com'],
  ['Norberto Cázares León', 'norberto.cazares@mail.com'],
  ['Olivia Mendoza Garduño', 'olivia.mendoza@mail.com'],
  ['Pablo Ayala Jiménez', 'pablo.ayala@mail.com'],
  ['Regina Carrillo Paz', 'regina.carrillo@mail.com'],
  ['Samuel Lira Arriaga', 'samuel.lira@mail.com'],
  ['Teresa Uribe Domínguez', 'teresa.uribe@mail.com'],
  ['Ulises Navarrete Gil', 'ulises.navarrete@mail.com'],
  ['Verónica Saldaña Ruiz', 'veronica.saldana@mail.com'],
  ['Wenceslao Ortega Díaz', 'wenceslao.ortega@mail.com'],
  ['Ximena Arellano Toledo', 'ximena.arellano@mail.com'],
  ['Yolanda Ferrer Campos', 'yolanda.ferrer@mail.com'],
  ['Zacarías Lozano Brito', 'zacarias.lozano@mail.com'],
  ['Adriana Villegas Soto', 'adriana.villegas@mail.com'],
  ['Bernardo Cuevas Nava', 'bernardo.cuevas@mail.com'],
];

const cuentas: CuentaSemilla[] = [
  { key: 'adm-1', name: 'Mariana Ortega Ruiz', email: 'admin@safelink.mx', phone: '7771002030', role: Role.admin },
  ...guardias,
  ...protegidos,
  ...masProtegidos.map(([name, email], i) => ({
    key: `usr-${i + 9}`,
    name,
    email,
    phone: `77730${String(i + 9).padStart(5, '0')}`,
    role: Role.protected_user,
  })),
];

// --- Alertas ------------------------------------------------------------------

interface AlertaSemilla {
  key: string;
  user: string;
  status: AlertStatus;
  method: TriggerMethod;
  minutesAgo: number;
  point?: Punto;
  heading?: number;
  guard?: string;
  acceptedMinAgo?: number;
  arrivedMinAgo?: number;
  closedMinAgo?: number;
  reason?: EscalationReason;
  resolution?: Resolution;
  noPhoto?: boolean;
}

const M = { toque: TriggerMethod.tap, mantener: TriggerMethod.hold, volumen: TriggerMethod.shake };

function buscando(
  key: string,
  user: string,
  method: TriggerMethod,
  minutesAgo: number,
  base: Punto,
  metros: number,
  grados: number,
  noPhoto = false,
): AlertaSemilla {
  return {
    key,
    user,
    status: AlertStatus.searching,
    method,
    minutesAgo,
    point: aDistancia(base, metros, grados),
    heading: (grados * 7) % 360,
    noPhoto,
  };
}

const alertas: AlertaSemilla[] = [
  // grd-1 · Emiliano Zapata
  buscando('alt-101', 'usr-3', M.volumen, 1, ubicacionGrd1, 850, 20),
  buscando('alt-102', 'usr-2', M.toque, 2, ubicacionGrd1, 3300, 60),
  buscando('alt-103', 'usr-5', M.mantener, 4, ubicacionGrd1, 2200, 300, true),
  buscando('alt-104', 'usr-6', M.toque, 0, ubicacionGrd1, 350, 110),
  // grd-2 · Cuernavaca
  buscando('alt-105', 'usr-7', M.volumen, 3, ubicacionGrd2, 450, 200),
  buscando('alt-111', 'usr-11', M.toque, 1, ubicacionGrd2, 900, 80),
  buscando('alt-112', 'usr-12', M.mantener, 5, ubicacionGrd2, 2500, 250, true),
  buscando('alt-113', 'usr-13', M.toque, 2, ubicacionGrd2, 3600, 315),
  // grd-3 · Yautepec
  buscando('alt-114', 'usr-14', M.volumen, 2, ubicacionGrd3, 300, 150),
  buscando('alt-115', 'usr-15', M.toque, 0, ubicacionGrd3, 950, 300),
  buscando('alt-116', 'usr-16', M.mantener, 6, ubicacionGrd3, 1800, 10, true),
  buscando('alt-117', 'usr-17', M.toque, 3, ubicacionGrd3, 3300, 45),
  // grd-4 · Cuautla (turno nocturno)
  buscando('alt-118', 'usr-18', M.volumen, 1, ubicacionGrd4, 400, 270),
  buscando('alt-119', 'usr-19', M.mantener, 4, ubicacionGrd4, 900, 120, true),
  buscando('alt-120', 'usr-20', M.toque, 2, ubicacionGrd4, 2600, 200),
  buscando('alt-121', 'usr-21', M.toque, 7, ubicacionGrd4, 3400, 225),
  // grd-6 · Tepoztlán
  buscando('alt-122', 'usr-22', M.volumen, 2, ubicacionGrd6, 250, 60),
  buscando('alt-123', 'usr-23', M.toque, 1, ubicacionGrd6, 700, 330),
  buscando('alt-124', 'usr-24', M.mantener, 3, ubicacionGrd6, 2100, 100, true),
  buscando('alt-125', 'usr-25', M.toque, 5, ubicacionGrd6, 3150, 0),
  // grd-7 · Xochitepec (fuera de turno)
  buscando('alt-126', 'usr-26', M.volumen, 2, centroXochitepec, 700, 45),
  buscando('alt-127', 'usr-27', M.mantener, 6, centroXochitepec, 1500, 250, true),
  // Resto de estados activos
  { key: 'alt-201', user: 'usr-8', status: AlertStatus.pending_location, method: M.toque, minutesAgo: 1 },
  {
    key: 'alt-202', user: 'usr-9', status: AlertStatus.in_progress, method: M.mantener, minutesAgo: 9,
    guard: 'grd-2', acceptedMinAgo: 8, point: aDistancia(ubicacionGrd2, 1600, 320), heading: 120,
  },
  {
    key: 'alt-203', user: 'usr-10', status: AlertStatus.guard_arrived, method: M.toque, minutesAgo: 14,
    guard: 'grd-3', acceptedMinAgo: 13, arrivedMinAgo: 3, point: aDistancia(ubicacionGrd3, 25, 90), heading: 15,
  },
  {
    key: 'alt-204', user: 'usr-5', status: AlertStatus.no_response, method: M.toque, minutesAgo: 6,
    point: aDistancia(centroYautepec, 2500, 300), heading: 220,
  },
  // Escaladas y una resuelta por el admin
  {
    key: 'alt-301', user: 'usr-3', status: AlertStatus.escalated, method: M.volumen, minutesAgo: 22,
    reason: 'no_response', point: aDistancia(centroEmilianoZapata, 2500, 40), heading: 75,
  },
  {
    key: 'alt-302', user: 'usr-2', status: AlertStatus.escalated, method: M.toque, minutesAgo: 48,
    guard: 'grd-1', acceptedMinAgo: 47, arrivedMinAgo: 38, reason: 'no_confirmation',
    point: aDistancia(centroEmilianoZapata, 1100, 130), heading: 260,
  },
  {
    key: 'alt-303', user: 'usr-6', status: AlertStatus.escalated, method: M.mantener, minutesAgo: 75,
    guard: 'grd-6', acceptedMinAgo: 73, arrivedMinAgo: 60, reason: 'no_confirmation',
    point: aDistancia(centroTepoztlan, 1200, 250), heading: 330,
  },
  {
    key: 'alt-304', user: 'usr-4', status: AlertStatus.resolved_by_admin, method: M.toque, minutesAgo: 60 * 26,
    guard: 'grd-1', acceptedMinAgo: 60 * 26 - 1, arrivedMinAgo: 60 * 26 - 9, closedMinAgo: 60 * 25,
    reason: 'no_confirmation', resolution: 'false_alarm',
    point: aDistancia(centroEmilianoZapata, 400, 300), heading: 0,
  },
];

// --- Ejecución ------------------------------------------------------------------

interface Cambio {
  from: AlertStatus | null;
  to: AlertStatus;
  at: Date;
  actor: string | null; // key del front; null = sistema
}

async function main(): Promise<void> {
  const entorno = process.env['NODE_ENV'];
  if (entorno !== 'development' && entorno !== 'test') {
    console.error(
      'La semilla exige NODE_ENV=development o NODE_ENV=test definido de forma explícita (en backend/.env o en el entorno). No se hizo ningún cambio.',
    );
    process.exit(1);
  }
  const url = process.env['DATABASE_URL'];
  if (!url) {
    console.error('Falta DATABASE_URL: define la variable en backend/.env.');
    process.exit(1);
  }
  // Mismos valores y defaults que la API (src/config/env.ts).
  const cfg = envSchema
    .pick({ TZ_SHIFTS: true, ACCEPT_TIMEOUT_SECONDS: true, CONFIRM_TIMEOUT_SECONDS: true })
    .safeParse(process.env);
  if (!cfg.success) {
    console.error(
      `Configuración inválida para la semilla en: ${cfg.error.issues.map((i) => i.path.join('.')).join(', ')}.`,
    );
    process.exit(1);
  }
  const tz = cfg.data.TZ_SHIFTS;
  const aceptacionMs = cfg.data.ACCEPT_TIMEOUT_SECONDS * 1000;
  const confirmacionMs = cfg.data.CONFIRM_TIMEOUT_SECONDS * 1000;

  const ahora = new Date();
  const min = (m: number): Date => new Date(ahora.getTime() - m * 60_000);
  const antesDeAhora = (t: number): Date => new Date(Math.min(t, ahora.getTime()));
  const id = (key: string): string => uuidV5(key);

  const prisma = createPrisma(url);
  try {
    // Usuarios
    const creado = new Date(ahora.getTime() - 90 * 86_400_000);
    const passwordHash = await argon2.hash(PASSWORD, { type: argon2.argon2id });
    for (const c of cuentas) {
      const data = {
        name: c.name,
        email: c.email.trim().toLowerCase(),
        phone: c.phone,
        passwordHash,
        role: c.role,
        isActive: c.isActive ?? true,
        volumeDoubleClickEnabled: c.volumeDoubleClickEnabled ?? false,
        falseAlarmCount: c.falseAlarmCount ?? 0,
        blockedUntil: c.blockedDays === undefined ? null : new Date(ahora.getTime() + c.blockedDays * 86_400_000),
      };
      await prisma.user.upsert({
        where: { id: id(c.key) },
        create: { id: id(c.key), createdAt: creado, ...data },
        update: data,
      });
    }

    // Perfiles de guardia: turnos relativos a "ahora", evaluados en TZ_SHIFTS.
    const enInicio = hhmm(min(2 * 60), tz);
    const enFin = hhmm(new Date(ahora.getTime() + 6 * 3_600_000), tz);
    const fueraInicio = hhmm(new Date(ahora.getTime() + 3 * 3_600_000), tz);
    const fueraFin = hhmm(new Date(ahora.getTime() + 11 * 3_600_000), tz);
    const conUbicacion = (p: Punto, en: Date | null) => ({
      lastLocationLat: p.lat,
      lastLocationLng: p.lng,
      lastLocationAt: en,
    });
    const sinUbicacion = { lastLocationLat: null, lastLocationLng: null, lastLocationAt: null };
    const perfiles = [
      ['grd-1', enInicio, enFin, centroEmilianoZapata, 4000, 'Emiliano Zapata', conUbicacion(ubicacionGrd1, ahora)],
      ['grd-2', enInicio, enFin, centroCuernavaca, 5000, 'Cuernavaca', conUbicacion(ubicacionGrd2, ahora)],
      ['grd-3', enInicio, enFin, centroYautepec, 4000, 'Yautepec', conUbicacion(ubicacionGrd3, ahora)],
      ['grd-4', '22:00', '06:00', centroCuautla, 4000, 'Cuautla', conUbicacion(ubicacionGrd4, null)],
      ['grd-5', fueraInicio, fueraFin, centroJojutla, 2000, 'Jojutla', sinUbicacion],
      ['grd-6', enInicio, enFin, centroTepoztlan, 3500, 'Tepoztlán', conUbicacion(ubicacionGrd6, ahora)],
      ['grd-7', fueraInicio, fueraFin, centroXochitepec, 2500, 'Xochitepec', sinUbicacion],
    ] as const;
    for (const [key, shiftStart, shiftEnd, centro, radio, zone, ubic] of perfiles) {
      const data = {
        shiftStart,
        shiftEnd,
        coverageCenterLat: centro.lat,
        coverageCenterLng: centro.lng,
        coverageRadiusMeters: radio,
        zone,
        ...ubic,
      };
      await prisma.guardProfile.upsert({
        where: { userId: id(key) },
        create: { userId: id(key), ...data },
        update: data,
      });
    }
    // grd-8: recién dado de alta, sin cobertura ni zona.
    const grd8 = {
      shiftStart: '08:00',
      shiftEnd: '16:00',
      coverageCenterLat: null,
      coverageCenterLng: null,
      coverageRadiusMeters: null,
      zone: null,
      ...sinUbicacion,
    };
    await prisma.guardProfile.upsert({
      where: { userId: id('grd-8') },
      create: { userId: id('grd-8'), ...grd8 },
      update: grd8,
    });

    // Alertas e historial de estados (todo en una transacción por alerta).
    for (const a of alertas) {
      const disparada = min(a.minutesAgo);
      const aceptada = a.acceptedMinAgo === undefined ? null : min(a.acceptedMinAgo);
      const llegada = a.arrivedMinAgo === undefined ? null : min(a.arrivedMinAgo);
      const cerrada = a.closedMinAgo === undefined ? null : min(a.closedMinAgo);

      const inicial = a.status === AlertStatus.pending_location ? AlertStatus.pending_location : AlertStatus.searching;
      const cambios: Cambio[] = [{ from: null, to: inicial, at: disparada, actor: a.user }];
      if (a.status !== AlertStatus.pending_location) {
        if (aceptada) cambios.push({ from: AlertStatus.searching, to: AlertStatus.in_progress, at: aceptada, actor: a.guard ?? null });
        if (llegada) cambios.push({ from: AlertStatus.in_progress, to: AlertStatus.guard_arrived, at: llegada, actor: a.guard ?? null });
        if (a.status === AlertStatus.no_response) {
          cambios.push({ from: AlertStatus.searching, to: AlertStatus.no_response, at: antesDeAhora(disparada.getTime() + aceptacionMs), actor: null });
        }
        if (a.status === AlertStatus.escalated || a.status === AlertStatus.resolved_by_admin) {
          const desde = llegada ? AlertStatus.guard_arrived : AlertStatus.searching;
          const base = llegada ? llegada.getTime() + confirmacionMs : disparada.getTime() + aceptacionMs;
          cambios.push({ from: desde, to: AlertStatus.escalated, at: antesDeAhora(base), actor: null });
        }
        if (a.status === AlertStatus.resolved_by_admin) {
          cambios.push({ from: AlertStatus.escalated, to: AlertStatus.resolved_by_admin, at: cerrada ?? ahora, actor: 'adm-1' });
        }
      }
      const ultimo = cambios[cambios.length - 1];
      const cambioEstado = ultimo ? ultimo.at : disparada;

      const data = {
        userId: id(a.user),
        guardId: a.guard ? id(a.guard) : null,
        status: a.status,
        triggerMethod: a.method,
        photoKey: a.noPhoto ? null : uuidV5(`photo:${a.key}`),
        evidenceIncomplete: a.noPhoto ?? false,
        lat: a.point?.lat ?? null,
        lng: a.point?.lng ?? null,
        heading: a.heading ?? null,
        triggeredAt: disparada,
        receivedAt: disparada,
        statusChangedAt: cambioEstado,
        acceptedAt: aceptada,
        arrivedAt: llegada,
        closedAt: cerrada,
        escalationReason: a.reason ?? null,
        resolution: a.resolution ?? null,
        adminNote: a.resolution ? 'Resuelta por el administrador (dato de ejemplo).' : null,
      };
      await prisma.$transaction([
        prisma.alert.upsert({
          where: { id: id(a.key) },
          create: { id: id(a.key), createdAt: disparada, ...data },
          update: data,
        }),
        prisma.alertStatusHistory.deleteMany({ where: { alertId: id(a.key) } }),
        prisma.alertStatusHistory.createMany({
          data: cambios.map((c, i) => ({
            id: uuidV5(`history:${a.key}:${i}`),
            alertId: id(a.key),
            fromStatus: c.from,
            toStatus: c.to,
            actorId: c.actor ? id(c.actor) : null,
            at: c.at,
          })),
        }),
      ]);
    }

    console.log(
      `Semilla lista: ${cuentas.length} cuentas, ${perfiles.length + 1} perfiles de guardia, ${alertas.length} alertas.`,
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e: unknown) => {
  console.error('La semilla falló:', e instanceof Error ? e.message : e);
  process.exit(1);
});
