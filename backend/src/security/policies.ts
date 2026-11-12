// Registro CENTRAL de políticas de acceso (deny-by-default). Única fuente de verdad de quién
// puede llamar a cada ruta; guards.ts impide arrancar si una ruta no tiene entrada aquí.
//
// Clave = `MÉTODO /ruta` relativa a /api/v1, con la misma notación de lib/datos/safelink_service.dart
// (`:id`). Valor:
//   - lista de roles: requiere access token válido y uno de esos roles (401 sin token, 403 rol incorrecto);
//   - 'public': sin autenticación;
//   - 'custom': la ruta verifica el token por su cuenta (POST /auth/session, D7/D25).
import { Role } from '../generated/prisma/enums.js';

export type RoutePolicy = 'public' | 'custom' | readonly Role[];

export const ALL_ROLES: readonly Role[] = [Role.protected_user, Role.guard, Role.admin];
const USER: readonly Role[] = [Role.protected_user];
const GUARD: readonly Role[] = [Role.guard];
const ADMIN: readonly Role[] = [Role.admin];

export const ROUTE_POLICIES: Readonly<Record<string, RoutePolicy>> = Object.freeze({
  // Sesión
  'POST /auth/login': 'public',
  'POST /auth/register': 'public',
  'POST /auth/refresh': 'public',
  'POST /auth/logout': ALL_ROLES,
  'GET /auth/me': ALL_ROLES,
  'POST /auth/session': 'custom',
  'PATCH /users/me/settings': USER,

  // Usuario protegido
  'POST /alerts': USER,
  'GET /alerts/mine': USER,
  'POST /alerts/:id/locations': USER,
  'POST /alerts/:id/confirm': USER,

  // Guardia
  'GET /guard/me': GUARD,
  'GET /guard/history': GUARD,
  'GET /guard/metrics': GUARD,
  'PUT /guard/location': GUARD,
  'GET /guard/alerts/:id': GUARD,
  'POST /guard/alerts/:id/accept': GUARD,
  'POST /guard/alerts/:id/ignore': GUARD,
  'POST /guard/alerts/:id/arrive': GUARD,

  // Administración
  'GET /admin/guards': ADMIN,
  'POST /admin/guards': ADMIN,
  'GET /admin/guards/:id': ADMIN,
  'PATCH /admin/guards/:id': ADMIN,
  'DELETE /admin/guards/:id': ADMIN,
  'PUT /admin/guards/:id/coverage': ADMIN,
  'POST /admin/alerts/:id/resolve': ADMIN,
  'GET /admin/alerts': ADMIN,
  'GET /admin/metrics': ADMIN,
  'GET /admin/metrics/guards/:id': ADMIN,
  'GET /admin/users': ADMIN,
  'GET /admin/users/blocked': ADMIN,
  'DELETE /admin/users/:id/block': ADMIN,

  // Tiempo real (SSE, D3/D20): /api/v1/events/<canal del front>
  'GET /events/alerts/active': USER,
  'GET /events/guard/alerts': GUARD,
  'GET /events/guard/alerts/:id': GUARD,
  'GET /events/admin/alerts/escalated': ADMIN,
});

export function policyKey(method: string, path: string): string {
  return `${method.toUpperCase()} ${path}`;
}

/** Política de una ruta (path sin prefijo), o undefined si no existe (= prohibida). */
export function getPolicy(method: string, path: string): RoutePolicy | undefined {
  return Object.hasOwn(ROUTE_POLICIES, policyKey(method, path))
    ? ROUTE_POLICIES[policyKey(method, path)]
    : undefined;
}

/** Dos políticas son equivalentes si son el mismo literal o el mismo conjunto de roles. */
export function policiesEqual(a: RoutePolicy, b: RoutePolicy): boolean {
  if (typeof a === 'string' || typeof b === 'string') return a === b;
  const setA = new Set(a);
  const setB = new Set(b);
  return (
    a.length === setA.size &&
    b.length === setB.size &&
    setA.size === setB.size &&
    [...setA].every((role) => setB.has(role))
  );
}
