// Traducción de los errores de Prisma que la API sabe nombrar.
// Se mantiene aquí para que los servicios no dependan del código de error crudo.
import { Prisma } from '../generated/prisma/client.js';

/** `true` si el fallo es una violación de índice único (P2002) sobre [campo]. */
export function esCorreoDuplicado(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') return false;
  const destino = error.meta?.['target'];
  // El destino puede venir como lista de columnas o como el nombre del índice.
  if (Array.isArray(destino)) return destino.some((c) => String(c).includes('email'));
  return typeof destino === 'string' ? destino.includes('email') : true;
}

/**
 * `true` si el fallo es el índice único parcial de D36 (un guardia, una alerta en atención).
 * Dentro de la transacción de `accept` es el único índice único que puede violarse; con el
 * adaptador pg el destino a veces no trae el nombre, por eso solo se descarta si nombra otro.
 * Solo para `accept`: en otro flujo (p. ej. `alert_ignores`, cuya llave incluye `guard_id`)
 * daría falsos positivos.
 */
export function esGuardiaOcupado(error: unknown): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== 'P2002') return false;
  const destino = error.meta?.['target'];
  const texto = Array.isArray(destino) ? destino.join(',') : String(destino ?? '');
  return texto === '' || texto.includes('alerts_one_active_per_guard_idx') || texto.includes('guard_id');
}

/** `true` si el registro que se quería actualizar o borrar no existe (P2025). */
export function esRegistroInexistente(error: unknown): boolean {
  return error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025';
}
