import type { FastifyInstance } from 'fastify';
import { createPasswordHasher } from '../../auth/password.js';
import type { PrismaClient } from '../../db/prisma.js';
import { ok } from '../../http/envelope.js';
import { parse, parseIdParam } from '../../http/validate.js';
import type { SerializeOptions } from '../alerts/serializers.js';
import {
  coverageBodySchema,
  createGuardBodySchema,
  guardsQuerySchema,
  historyQuerySchema,
  periodQuerySchema,
  updateGuardBodySchema,
} from './schemas.js';
import { createAdminService } from './service.js';

export interface AdminRoutesOptions {
  prisma: PrismaClient;
  /** Opciones de serialización de alertas: las mismas que usan los demás módulos (app.ts). */
  serialize: SerializeOptions;
}

/**
 * Gestión de guardias (A-01, A-02 · BE-02) y, además, historial, métricas y desbloqueo
 * (A-05 a A-08 · BE-07). El acceso lo decide la política central
 * (src/security/policies.ts): estas rutas son solo para el rol admin.
 * La cobertura (PUT /admin/guards/:id/coverage, A-03) es BE-06.
 */
export async function adminRoutes(app: FastifyInstance, options: AdminRoutesOptions): Promise<void> {
  const { config } = app;
  const hasher = createPasswordHasher({
    memoryCost: config.ARGON2_MEMORY_KIB,
    timeCost: config.ARGON2_TIME_COST,
    parallelism: config.ARGON2_PARALLELISM,
  });
  const service = createAdminService({
    prisma: options.prisma,
    hasher,
    serialize: options.serialize,
    timeZone: config.TZ_SHIFTS,
    coverageRadius: {
      min: config.COVERAGE_RADIUS_MIN_METERS,
      max: config.COVERAGE_RADIUS_MAX_METERS,
    },
  });

  app.get('/admin/guards', async (request) => {
    const query = parse(guardsQuerySchema, request.query);
    return ok(await service.listGuards(query.search));
  });

  app.post('/admin/guards', async (request, reply) => {
    const body = parse(createGuardBodySchema, request.body);
    const creado = await service.createGuard(body);
    void reply.code(201); // D22: los POST que crean recurso responden 201
    return ok(creado);
  });

  app.get('/admin/guards/:id', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    return ok(await service.getGuard(id));
  });

  app.patch('/admin/guards/:id', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    const body = parse(updateGuardBodySchema, request.body);
    return ok(await service.updateGuard(id, body));
  });

  app.delete('/admin/guards/:id', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    return ok(await service.deactivateGuard(id));
  });

  // A-03 · Cobertura del guardia (turno, centro, radio y zona).
  app.put('/admin/guards/:id/coverage', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    const body = parse(coverageBodySchema, request.body);
    return ok(await service.updateCoverage(id, body));
  });

  // A-05 · Historial con filtros (contrato 4.8). Un filtro inválido es 400 INVALID_STATE.
  app.get('/admin/alerts', async (request) => {
    const query = parse(historyQuerySchema, request.query);
    return ok(await service.listAlerts(query));
  });

  // A-06 · Métricas generales del periodo.
  app.get('/admin/metrics', async (request) => {
    const query = parse(periodQuerySchema, request.query);
    return ok(await service.generalMetrics(query));
  });

  // A-07 · Métricas de un guardia. Id que no es de un guardia: NOT_FOUND.
  app.get('/admin/metrics/guards/:id', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    const query = parse(periodQuerySchema, request.query);
    return ok(await service.guardMetrics(id, query));
  });

  // A-08 · Usuarios protegidos y los bloqueados ahora mismo.
  app.get('/admin/users', async () => ok(await service.listProtectedUsers()));

  app.get('/admin/users/blocked', async () => ok(await service.listBlockedUsers()));

  // A-08 · Desbloqueo a mano: quita el bloqueo y reinicia el contador de falsas alarmas.
  app.delete('/admin/users/:id/block', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    return ok(await service.unblockUser(id));
  });
}
