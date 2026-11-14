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

/** `true` si el registro que se quería actualizar o borrar no existe (P2025). */
export function esRegistroInexistente(error: unknown): boolean {
  return error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2025';
}
