import type { FastifyInstance } from 'fastify';
import { createPasswordHasher } from '../../auth/password.js';
import type { PrismaClient } from '../../db/prisma.js';
import { ok } from '../../http/envelope.js';
import { parse, parseIdParam } from '../../http/validate.js';
import { createGuardBodySchema, guardsQuerySchema, updateGuardBodySchema } from './schemas.js';
import { createAdminService } from './service.js';

export interface AdminRoutesOptions {
  prisma: PrismaClient;
}

/**
 * Gestión de guardias (A-01, A-02 · BE-02). El acceso lo decide la política
 * central (src/security/policies.ts): estas rutas son solo para el rol admin.
 * La cobertura (PUT /admin/guards/:id/coverage) es A-03 y toca a BE-06.
 */
export async function adminRoutes(app: FastifyInstance, options: AdminRoutesOptions): Promise<void> {
  const { config } = app;
  const hasher = createPasswordHasher({
    memoryCost: config.ARGON2_MEMORY_KIB,
    timeCost: config.ARGON2_TIME_COST,
    parallelism: config.ARGON2_PARALLELISM,
  });
  const service = createAdminService({ prisma: options.prisma, hasher });

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
}
