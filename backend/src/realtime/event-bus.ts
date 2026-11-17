// Bus de eventos en memoria (D3). Avisa "algo cambió en este tema"; cada suscriptor vuelve a
// leer de la base su propio snapshot (los eventos SSE son snapshots completos, no deltas).
// Un solo proceso: si un día hay varias instancias de la API, se cambia por uno compartido
// (p. ej. LISTEN/NOTIFY de Postgres) detrás de esta misma interfaz.
//
// Temas en uso:
//   alertsTopicForUser(userId)  la alerta activa de ese usuario cambió (BE-03 la publica al
//                               crear, mover y confirmar; BE-04 y BE-05 deben publicarla al
//                               aceptar, marcar llegada, escalar y resolver).
import { EventEmitter } from 'node:events';

export type Unsubscribe = () => void;

export interface EventBus {
  publish(topic: string): void;
  subscribe(topic: string, listener: () => void): Unsubscribe;
}

export const alertsTopicForUser = (userId: string): string => `alerts:user:${userId}`;

export function createMemoryEventBus(): EventBus {
  const emitter = new EventEmitter();
  // Cada stream abierto es un suscriptor: no es una fuga, el máximo lo controla el SSE.
  emitter.setMaxListeners(0);
  return {
    publish(topic) {
      emitter.emit(topic);
    },
    subscribe(topic, listener) {
      emitter.on(topic, listener);
      return () => {
        emitter.off(topic, listener);
      };
    },
  };
}
