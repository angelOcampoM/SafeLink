// Instancia Fastify propia para probar el manejo de errores con rutas de prueba (/t/*).
// Usa el mismo manejo de errores y los mismos límites que buildApp, pero SIN registerRouteGuards:
// con deny-by-default, buildApp aborta el arranque si hay una ruta sin política central.
import Fastify, { type FastifyInstance } from 'fastify';
import type { Config } from '../../src/config/env.js';
import { createFrameworkErrorHandler, registerErrorHandling } from '../../src/http/error-handler.js';

export function crearAppAislada(
  config: Config,
  registrar: (app: FastifyInstance) => void,
): FastifyInstance {
  const isProduction = config.NODE_ENV === 'production';
  const app = Fastify({
    bodyLimit: config.BODY_LIMIT_BYTES,
    frameworkErrors: createFrameworkErrorHandler(isProduction),
    logger: false,
  });
  registerErrorHandling(app, { isProduction });
  registrar(app);
  return app;
}
