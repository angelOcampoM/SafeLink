// Bus de eventos en memoria (D3). Avisa "algo cambió en este tema"; cada suscriptor vuelve a
// leer de la base su propio snapshot (los eventos SSE son snapshots completos, no deltas).
// Un solo proceso: si un día hay varias instancias de la API, se cambia por uno compartido
// (p. ej. LISTEN/NOTIFY de Postgres) detrás de esta misma interfaz.
//
// Temas en uso:
//   alertsTopicForUser(userId)  la alerta activa de ese usuario cambió (BE-03 la publica al
//                               crear, mover y confirmar; BE-04 y BE-05 deben publicarla al
//                               aceptar, marcar llegada, escalar y resolver).
//   dispatchTopic               (global) una alerta entró o salió de `searching`, o cambió su
//                               ubicación estando en `searching` (D34).
//   guardTopic(guardId)         cambió algo propio de ese guardia: su ubicación, ignorar una
//                               alerta (BE-06 agrega cobertura y baja).
//   alertTopic(alertId)         cualquier cambio de esa alerta (canal guard/alerts/:id).
//   escalatedTopic              (global) una alerta entró o salió de `escalated` (canal
//                               admin/alerts/escalated). BE-05 lo publica al escalar; BE-06
//                               debe publicarlo al resolver.
import { EventEmitter } from 'node:events';

export type Unsubscribe = () => void;

export interface EventBus {
  publish(topic: string): void;
  subscribe(topic: string, listener: () => void): Unsubscribe;
}

export const alertsTopicForUser = (userId: string): string => `alerts:user:${userId}`;
export const dispatchTopic = 'alerts:dispatch';
export const guardTopic = (guardId: string): string => `guard:${guardId}`;
export const alertTopic = (alertId: string): string => `alert:${alertId}`;
export const escalatedTopic = 'alerts:escalated';

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
