// Transporte SSE de los canales del front (D3, contrato sección 6). Común a todos los canales:
// cada uno solo aporta cómo leer su snapshot y a qué tema del bus escuchar.
//
//   - al conectar se manda el snapshot actual; después, uno nuevo con cada aviso del bus;
//   - `: ping` periódico, que además revisa que la sesión siga viva (logout o baja, D25);
//   - al llegar el `exp` del access token se avisa UNAUTHORIZED y se cierra (D26);
//   - máximo de conexiones por (usuario, canal): al pasarse se cierra la MÁS ANTIGUA (D26, D34);
//   - un error ya abierto el stream viaja como `data: {"error":...}` y se cierra.
// El 401/403 se resuelve ANTES de abrir el stream (hooks de security/guards.ts).
import type { FastifyReply, FastifyRequest } from 'fastify';
import { AppError, MESSAGES, internalError } from '../errors/app-error.js';
import { errorBody } from '../http/envelope.js';
import type { EventBus } from './event-bus.js';

export interface SseOptions {
  pingSeconds: number;
  maxConnectionsPerUser: number;
}

export interface SseChannel<T> {
  /**
   * Nombre fijo del canal (no por recurso: guard/alerts/:id usa uno solo); el límite de
   * conexiones se cuenta por (usuario, nombre). Obligatorio para que dos canales no compartan cupo.
   */
  name: string;
  /** Tema del bus que dispara un snapshot nuevo (un solo tema). */
  topic?: string;
  /** Varios temas del bus (D34); se combinan con `topic` si se dan los dos. */
  topics?: readonly string[];
  /** Manda un snapshot nuevo en cada ping (refleja el paso del tiempo, D34). */
  refreshOnPing?: boolean;
  /** Snapshot completo del canal para este usuario. */
  snapshot: () => Promise<T>;
  /** ¿Sigue viva la sesión? (usuario activo y familia `sid` sin revocar). */
  sessionAlive: () => Promise<boolean>;
  /** Fin de la vigencia del access token, en milisegundos desde epoch. */
  tokenExpiresAtMs: number;
}

interface OpenStream {
  channelName: string;
  close: (error?: AppError) => void;
}

export interface SseHub {
  open<T>(request: FastifyRequest, reply: FastifyReply, channel: SseChannel<T>): void;
  /** Cierra todos los streams (al apagar la API). */
  closeAll(): void;
  /** Streams abiertos de un usuario (para las pruebas). */
  countFor(userId: string): number;
}

const unauthorizedError = (): AppError => new AppError('UNAUTHORIZED', MESSAGES.UNAUTHORIZED, 401);

export function createSseHub(bus: EventBus, options: SseOptions): SseHub {
  /** Streams abiertos por usuario, del más antiguo al más nuevo. */
  const porUsuario = new Map<string, OpenStream[]>();

  return {
    countFor: (userId) => porUsuario.get(userId)?.length ?? 0,

    closeAll() {
      for (const lista of [...porUsuario.values()]) for (const s of [...lista]) s.close();
    },

    open(request, reply, channel) {
      const userId = request.user.id;
      const raw = reply.raw;
      let cerrado = false;
      let enviando = Promise.resolve();
      // Dos avisos seguidos generan un solo snapshot extra, no una cola de consultas.
      let pendiente = false;

      reply.hijack();
      raw.writeHead(200, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-store',
        connection: 'keep-alive',
        // Sin buffer en proxies (nginx): cada evento debe llegar de inmediato.
        'x-accel-buffering': 'no',
      });

      const escribir = (texto: string): void => {
        if (!cerrado) raw.write(texto);
      };
      const evento = (cuerpo: unknown): void => escribir(`data: ${JSON.stringify(cuerpo)}\n\n`);

      const channelName = channel.name;
      const stream: OpenStream = {
        channelName,
        close(error) {
          if (cerrado) return;
          if (error) evento(errorBody(error));
          cerrado = true;
          clearInterval(ping);
          clearTimeout(vencimiento);
          dejarDeEscuchar();
          const lista = porUsuario.get(userId)?.filter((s) => s !== stream) ?? [];
          if (lista.length > 0) porUsuario.set(userId, lista);
          else porUsuario.delete(userId);
          raw.end();
        },
      };

      const mandarSnapshot = (): void => {
        if (pendiente || cerrado) return;
        pendiente = true;
        enviando = enviando.then(async () => {
          pendiente = false;
          if (cerrado) return;
          try {
            evento({ data: await channel.snapshot() });
          } catch (error) {
            // Un AppError (p. ej. NOT_FOUND porque la alerta ya no es visible) es esperado.
            if (error instanceof AppError) request.log.info({ code: error.code }, 'SSE: snapshot rechazado');
            else request.log.error({ err: error }, 'SSE: no se pudo leer el snapshot');
            stream.close(error instanceof AppError ? error : internalError());
          }
        });
      };

      const temas = new Set([...(channel.topic ? [channel.topic] : []), ...(channel.topics ?? [])]);
      const bajas = [...temas].map((tema) => bus.subscribe(tema, mandarSnapshot));
      const dejarDeEscuchar = (): void => {
        for (const baja of bajas) baja();
      };

      const ping = setInterval(() => {
        void channel
          .sessionAlive()
          .then((viva) => {
            if (!viva) return stream.close(unauthorizedError());
            escribir(': ping\n\n');
            if (channel.refreshOnPing) mandarSnapshot();
          })
          .catch(() => stream.close(internalError()));
      }, options.pingSeconds * 1000);
      ping.unref();

      const vencimiento = setTimeout(
        () => stream.close(unauthorizedError()),
        Math.max(0, channel.tokenExpiresAtMs - Date.now()),
      );
      vencimiento.unref();

      raw.on('close', () => stream.close());

      // D26/D34: al pasarse del máximo del canal se cierra la conexión más antigua de ese
      // canal, no se rechaza la nueva ni se tocan los otros canales del usuario.
      porUsuario.set(userId, [...(porUsuario.get(userId) ?? []), stream]);
      // close() reemplaza la lista del usuario: se vuelve a leer en cada vuelta.
      const delCanal = (): OpenStream[] =>
        (porUsuario.get(userId) ?? []).filter((s) => s.channelName === channelName);
      for (let abiertos = delCanal(); abiertos.length > options.maxConnectionsPerUser; abiertos = delCanal()) {
        abiertos[0]?.close();
      }

      mandarSnapshot();
    },
  };
}
