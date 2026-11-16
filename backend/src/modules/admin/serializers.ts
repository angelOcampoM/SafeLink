// Forma `GuardiaJson` del front (nube_mapeadores.dart:86-115). Un guardia viaja
// siempre como { user, profile }. Campo por campo: jamás spread del registro,
// para que un campo nuevo en la base no se filtre a la app sin querer.
import { serializeUser, type UserJson, type UserRecord } from '../auth/serializers.js';

export interface GuardProfileRecord {
  userId: string;
  shiftStart: string;
  shiftEnd: string;
  coverageCenterLat: number | null;
  coverageCenterLng: number | null;
  coverageRadiusMeters: number | null;
  zone: string | null;
  lastLocationLat: number | null;
  lastLocationLng: number | null;
  lastLocationAt: Date | null;
}

export interface PointJson {
  lat: number;
  lng: number;
}

export interface GuardProfileJson {
  userId: string;
  shiftStart: string;
  shiftEnd: string;
  coverageCenter: PointJson | null;
  coverageRadiusMeters: number | null;
  zone: string | null;
  lastLocation: PointJson | null;
  lastLocationAt: string | null;
}

export interface GuardJson {
  user: UserJson;
  profile: GuardProfileJson;
}

/** Un punto solo existe si vienen sus dos coordenadas. */
function point(lat: number | null, lng: number | null): PointJson | null {
  return lat === null || lng === null ? null : { lat, lng };
}

export function serializeGuardProfile(profile: GuardProfileRecord): GuardProfileJson {
  return {
    userId: profile.userId,
    shiftStart: profile.shiftStart,
    shiftEnd: profile.shiftEnd,
    coverageCenter: point(profile.coverageCenterLat, profile.coverageCenterLng),
    coverageRadiusMeters: profile.coverageRadiusMeters,
    zone: profile.zone,
    lastLocation: point(profile.lastLocationLat, profile.lastLocationLng),
    lastLocationAt: profile.lastLocationAt ? profile.lastLocationAt.toISOString() : null,
  };
}

export function serializeGuard(user: UserRecord, profile: GuardProfileRecord): GuardJson {
  return { user: serializeUser(user), profile: serializeGuardProfile(profile) };
}
