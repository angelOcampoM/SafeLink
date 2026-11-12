import type { FastifyInstance } from 'fastify';
import { ok } from '../http/envelope.js';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async () => ok({ status: 'ok' }));
}
