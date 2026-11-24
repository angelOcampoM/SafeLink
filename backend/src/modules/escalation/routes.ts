import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { ok } from '../../http/envelope.js';
import { parse, parseIdParam, userMsg } from '../../http/validate.js';
import type { EscalationService } from './service.js';

export interface EscalationRoutesOptions {
  service: EscalationService;
}

/** Tope del cuerpo: la regla real (ADMIN_NOTE_MAX_LENGTH, 300) se aplica en el servicio, después del estado. */
const NOTE_BODY_MAX = 2000;

/**
 * El esquema solo exige la forma; vacía o demasiado larga se responde en el servicio, después
 * de revisar el estado (el front valida en ese orden, memoria_admin_repository.dart:120).
 */
const resolveBodySchema = z
  .object({
    resolution: z.enum(['resolved', 'false_alarm', 'service_incident'], userMsg('La resolución no es válida')),
    adminNote: z.string(userMsg('Escribe una nota administrativa para resolver la alerta')).max(
      NOTE_BODY_MAX,
      userMsg('La nota es demasiado larga'),
    ),
  })
  .strict();

/**
 * Bandeja de escaladas (A-04, A-08 · BE-05). El acceso lo decide la política central
 * (src/security/policies.ts): solo el rol admin.
 */
export async function escalationRoutes(app: FastifyInstance, options: EscalationRoutesOptions): Promise<void> {
  const { service } = options;

  app.post('/admin/alerts/:id/resolve', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    const body = parse(resolveBodySchema, request.body);
    return ok(await service.resolve(request.user.id, id, body.resolution, body.adminNote));
  });
}
