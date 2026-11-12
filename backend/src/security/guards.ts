// Mecanismo deny-by-default: un hook onRoute que exige una política central (policies.ts) para
// cada ruta bajo el prefijo de la API y le agrega los hooks de autenticación y de rol.
//
// Debe registrarse en la instancia RAÍZ antes de cualquier ruta (los hooks onRoute solo ven las
// rutas registradas después). Si una ruta no tiene política, o declara una config que contradice
// la central, el arranque falla: una ruta sin política no puede existir.
//
// Los controles van en `onRequest` (no en `preHandler`) para rechazar sin autorización antes de
// leer y validar el cuerpo de la petición.
import type { FastifyInstance, FastifyRequest, onRequestAsyncHookHandler } from 'fastify';
import { forbidden, unauthorized } from '../errors/app-error.js';
import type { Role } from '../generated/prisma/enums.js';
import { getPolicy, policiesEqual, policyKey, type RoutePolicy } from './policies.js';

/** Rutas fuera del prefijo que quedan exentas de forma explícita. */
export const EXEMPT_ROUTES: ReadonlySet<string> = new Set(['GET /health']);

type AsyncRequestHook = (request: FastifyRequest) => Promise<void>;

/** Exige que el rol del usuario ya autenticado (request.user, tomado de la BD) sea uno de `roles`. */
export function requireRole(...roles: readonly Role[]): AsyncRequestHook {
  const allowed = new Set<Role>(roles);
  return async (request) => {
    // Sin request.user, `authenticate` no corrió: se trata como no autenticado.
    if (!request.user) throw unauthorized();
    if (!allowed.has(request.user.role)) throw forbidden();
  };
}

export interface RouteGuardOptions {
  /** Prefijo de la API, p. ej. /api/v1. */
  prefix: string;
}

function toHookArray(value: unknown): unknown[] {
  if (value === undefined) return [];
  return Array.isArray(value) ? [...(value as unknown[])] : [value];
}

function declaredPolicy(
  config: { public?: boolean; roles?: readonly Role[]; auth?: 'custom' } | undefined,
): RoutePolicy | undefined {
  if (!config) return undefined;
  const declared: RoutePolicy[] = [];
  if (config.public) declared.push('public');
  if (config.auth === 'custom') declared.push('custom');
  if (config.roles) declared.push(config.roles);
  if (declared.length > 1) {
    throw new Error('Una ruta declara más de una política de acceso (public/auth/roles)');
  }
  return declared[0];
}

/*
 * Orden de ejecución: cualquier hook onRequest a nivel de instancia que se agregue en el futuro
 * corre ANTES de `authenticate` (que es un hook de ruta); por eso no debe tocar datos ni el
 * cuerpo de la petición.
 */
export function registerRouteGuards(app: FastifyInstance, options: RouteGuardOptions): void {
  const { prefix } = options;
  const authenticateHook: AsyncRequestHook = (request) => app.authenticate(request);
  const roleHooks = new Map<string, AsyncRequestHook>();
  const roleHookFor = (roles: readonly Role[]): AsyncRequestHook => {
    const key = [...roles].sort().join(',');
    let hook = roleHooks.get(key);
    if (!hook) {
      hook = requireRole(...roles);
      roleHooks.set(key, hook);
    }
    return hook;
  };

  app.addHook('onRoute', (routeOptions) => {
    const methods = Array.isArray(routeOptions.method)
      ? routeOptions.method
      : [routeOptions.method];
    const url = routeOptions.url;

    if (!url.startsWith(`${prefix}/`)) {
      const exempt = methods.every((m) =>
        EXEMPT_ROUTES.has(policyKey(m === 'HEAD' ? 'GET' : m, url)),
      );
      if (!exempt) {
        throw new Error(`Ruta sin política de acceso (fuera de ${prefix} y no exenta): ${url}`);
      }
      return;
    }

    const path = url.slice(prefix.length);
    let policy: RoutePolicy | undefined;
    for (const method of methods) {
      // HEAD lo genera Fastify a partir de GET: hereda su política.
      const candidate = getPolicy(method === 'HEAD' ? 'GET' : method, path);
      if (candidate === undefined) {
        throw new Error(`Ruta sin política de acceso (deny-by-default): ${method} ${path}`);
      }
      if (policy !== undefined && !policiesEqual(policy, candidate)) {
        throw new Error(`Métodos con políticas distintas en una misma ruta: ${path}`);
      }
      policy = candidate;
    }
    if (policy === undefined) throw new Error(`Ruta sin métodos: ${path}`);

    const declared = declaredPolicy(routeOptions.config);
    if (declared !== undefined && !policiesEqual(declared, policy)) {
      throw new Error(`La config de la ruta ${path} contradice su política central`);
    }

    if (policy === 'public' || policy === 'custom') return;

    // Falla al arrancar, no con un TypeError 500 en la primera petición.
    if (typeof app.authenticate !== 'function') {
      throw new Error(
        `La ruta ${path} requiere autenticación pero 'authenticate' no está decorado: registra el plugin de auth antes`,
      );
    }
    const toAdd: AsyncRequestHook[] = [authenticateHook, roleHookFor(policy)];
    const existing = toHookArray(routeOptions.onRequest);
    // Idempotente: el HEAD automático puede heredar el arreglo ya modificado del GET.
    const missing = toAdd.filter((hook) => !existing.includes(hook));
    routeOptions.onRequest = [...missing, ...existing] as onRequestAsyncHookHandler[];
  });
}
