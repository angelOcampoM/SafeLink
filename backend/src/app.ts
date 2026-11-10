import Fastify, { type FastifyInstance } from 'fastify';
import type { Config } from './config/env.js';
import { healthRoutes } from './routes/health.js';

declare module 'fastify' {
  interface FastifyInstance {
    config: Config;
  }
}

export function buildApp(config: Config): FastifyInstance {
  const app = Fastify({
    logger:
      config.NODE_ENV === 'test'
        ? false
        : {
            level: 'info',
            redact: {
              paths: [
                'req.headers.authorization',
                'req.headers.cookie',
                'req.headers["set-cookie"]',
                'req.headers["x-api-key"]',
                'res.headers["set-cookie"]',
              ],
              censor: '[REDACTADO]',
            },
            serializers: {
              req(req: { method?: string; url?: string; hostname?: string; ip?: string }) {
                return {
                  method: req.method,
                  url: req.url?.split('?')[0],
                  host: req.hostname,
                  remoteAddress: req.ip,
                };
              },
            },
          },
  });
  app.decorate('config', config);
  void app.register(healthRoutes);
  return app;
}
