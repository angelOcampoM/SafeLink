// Reglas geográficas puras. Equivalen a lib/dominio/regla_geocerca.dart.

export interface GeoPoint {
  lat: number;
  lng: number;
}

const EARTH_RADIUS_METERS = 6_371_000;

const toRadians = (degrees: number): number => (degrees * Math.PI) / 180;

/** Distancia en metros (fórmula de Haversine). */
export function haversineMeters(a: GeoPoint, b: GeoPoint): number {
  const dLat = toRadians(b.lat - a.lat);
  const dLng = toRadians(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(a.lat)) * Math.cos(toRadians(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** ¿El punto cae dentro (o justo en el borde) del radio alrededor del centro? */
export function isWithinRadius(center: GeoPoint, radiusMeters: number, point: GeoPoint): boolean {
  return haversineMeters(center, point) <= radiusMeters;
}

/** Metros que faltan para entrar al radio (0 si ya está dentro). */
export function metersRemaining(from: GeoPoint, target: GeoPoint, radiusMeters: number): number {
  return Math.max(0, haversineMeters(from, target) - radiusMeters);
}
