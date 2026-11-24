// Cliente SSE mínimo para las pruebas: un stream no termina, así que supertest no sirve
// (espera el fin de la respuesta). Abre la conexión, entrega los eventos uno por uno y la corta.
import { request as httpRequest, type IncomingMessage } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { FastifyInstance } from 'fastify';

export interface ConexionSse {
  status: number;
  headers: IncomingMessage['headers'];
  /** Cuerpo completo cuando NO se abrió el stream (401/403 con el envoltorio JSON). */
  json: unknown;
  /** Siguiente evento `data:` ya parseado; falla si no llega en `ms`. */
  siguiente: (ms?: number) => Promise<unknown>;
  /** ¿El servidor cerró el stream? */
  cerrado: () => boolean;
  cerrar: () => void;
}

async function puerto(app: FastifyInstance): Promise<number> {
  const server = app.server;
  if (!server.listening) {
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  }
  return (server.address() as AddressInfo).port;
}

export async function abrirSse(app: FastifyInstance, ruta: string, token?: string): Promise<ConexionSse> {
  const port = await puerto(app);
  return new Promise((resolve, reject) => {
    const req = httpRequest(
      { host: '127.0.0.1', port, path: ruta, method: 'GET', headers: token ? { Authorization: `Bearer ${token}` } : {} },
      (res) => {
        res.setEncoding('utf8');
        const esStream = (res.headers['content-type'] ?? '').startsWith('text/event-stream');
        if (!esStream) {
          let texto = '';
          res.on('data', (c: string) => (texto += c));
          res.on('end', () =>
            resolve({
              status: res.statusCode ?? 0,
              headers: res.headers,
              json: texto ? (JSON.parse(texto) as unknown) : null,
              siguiente: () => Promise.reject(new Error('No se abrió el stream')),
              cerrado: () => true,
              cerrar: () => undefined,
            }),
          );
          return;
        }

        let buffer = '';
        let fin = false;
        const eventos: unknown[] = [];
        const esperando: Array<(e: unknown) => void> = [];
        res.on('data', (c: string) => {
          buffer += c;
          for (let i = buffer.indexOf('\n\n'); i >= 0; i = buffer.indexOf('\n\n')) {
            const bloque = buffer.slice(0, i);
            buffer = buffer.slice(i + 2);
            const linea = bloque.split('\n').find((l) => l.startsWith('data: '));
            if (!linea) continue; // `: ping`
            const evento = JSON.parse(linea.slice('data: '.length)) as unknown;
            const quien = esperando.shift();
            if (quien) quien(evento);
            else eventos.push(evento);
          }
        });
        res.on('close', () => (fin = true));

        resolve({
          status: res.statusCode ?? 0,
          headers: res.headers,
          json: null,
          siguiente: (ms = 5000) =>
            eventos.length > 0
              ? Promise.resolve(eventos.shift())
              : new Promise((ok, mal) => {
                  const t = setTimeout(() => mal(new Error('No llegó ningún evento SSE')), ms);
                  esperando.push((e) => {
                    clearTimeout(t);
                    ok(e);
                  });
                }),
          cerrado: () => fin,
          cerrar: () => {
            fin = true;
            req.destroy();
          },
        });
      },
    );
    req.on('error', (e) => {
      // Cortar la conexión a propósito también dispara 'error' (ECONNRESET): se ignora.
      if ((e as NodeJS.ErrnoException).code !== 'ECONNRESET') reject(e);
    });
    req.end();
  });
}
