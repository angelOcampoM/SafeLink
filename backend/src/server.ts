import { buildApp } from './app.js';
import { ConfigError, loadConfig, type Config } from './config/env.js';

async function main(): Promise<void> {
  let config: Config;
  try {
    config = loadConfig();
  } catch (e) {
    if (e instanceof ConfigError) {
      console.error(e.message);
      process.exit(1);
    }
    throw e;
  }
  if (!config.DATABASE_URL) {
    console.error('Configuración inválida: falta DATABASE_URL (cadena de conexión a PostgreSQL). Defínela en backend/.env.');
    process.exit(1);
  }
  const app = buildApp(config);
  try {
    await app.listen({ host: config.HOST, port: config.PORT });
  } catch (e) {
    app.log.error(e);
    process.exit(1);
  }
  const cerrar = (): void => {
    app.close().then(
      () => process.exit(0),
      (e: unknown) => {
        app.log.error(e);
        process.exit(1);
      },
    );
  };
  process.once('SIGTERM', cerrar);
  process.once('SIGINT', cerrar);
}

void main();
