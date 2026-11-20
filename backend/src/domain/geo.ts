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

const METERS_PER_DEGREE_LAT = 111_320;

/**
 * Ajusta un punto al CENTRO de su celda de una cuadrícula de ~`cellMeters` (D47). Regla determinista:
 * - Filas: paso en latitud = cellMeters / 111 320 grados; fila = floor((lat + 90) / paso).
 * - Columnas: paso en longitud = paso de latitud / cos(latitud del CENTRO de la fila) (tope 360°),
 *   así todos los puntos de una fila usan el mismo paso; columna = floor((lng + 180) / paso).
 * - El centro es el punto medio de la celda, recortado a [-90, 90] y [-180, 180].
 * Misma celda, mismo centro. Si el punto no es finito o `cellMeters` no es positivo se devuelve igual.
 */
export function snapToGrid(point: GeoPoint, cellMeters: number): GeoPoint {
  if (!Number.isFinite(point.lat) || !Number.isFinite(point.lng) || !(cellMeters > 0)) {
    return point;
  }
  const latStep = cellMeters / METERS_PER_DEGREE_LAT;
  const lat = Math.min(90, Math.max(-90, point.lat));
  const lng = Math.min(180, Math.max(-180, point.lng));
  const row = Math.floor((lat + 90) / latStep);
  const centerLat = Math.min(90, Math.max(-90, -90 + (row + 0.5) * latStep));
  const lngStep = Math.min(360, latStep / Math.max(Math.cos(toRadians(centerLat)), 1e-9));
  const col = Math.floor((lng + 180) / lngStep);
  const centerLng = Math.min(180, Math.max(-180, -180 + (col + 0.5) * lngStep));
  return { lat: centerLat, lng: centerLng };
}

/** ¿El punto cae dentro (o justo en el borde) del radio alrededor del centro? */
export function isWithinRadius(center: GeoPoint, radiusMeters: number, point: GeoPoint): boolean {
  return haversineMeters(center, point) <= radiusMeters;
}

/** Metros que faltan para entrar al radio (0 si ya está dentro). */
export function metersRemaining(from: GeoPoint, target: GeoPoint, radiusMeters: number): number {
  return Math.max(0, haversineMeters(from, target) - radiusMeters);
}
