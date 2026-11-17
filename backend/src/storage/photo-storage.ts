// Foto de evidencia de la alerta (D2 · BE-03). Interfaz PhotoStorage con una
// implementación en disco local; un bucket podrá entrar después detrás de la misma interfaz.
//
// Reglas de seguridad (contrato, sección 8):
//   - la llave es un UUID que genera el servidor (nunca un nombre o ruta del cliente);
//   - el tipo se decide por la FIRMA DE BYTES, no por el Content-Type que declara el cliente;
//   - hay tamaño máximo (lo aplica quien recibe la subida, antes de llamar a save).
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

export type PhotoMime = 'image/jpeg' | 'image/png' | 'image/webp';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Tipo de imagen según sus primeros bytes, o null si no es JPEG, PNG ni WebP. */
export function detectPhotoMime(bytes: Uint8Array): PhotoMime | null {
  const b = (i: number): number => bytes[i] ?? -1;
  if (b(0) === 0xff && b(1) === 0xd8 && b(2) === 0xff) return 'image/jpeg';
  if (
    b(0) === 0x89 && b(1) === 0x50 && b(2) === 0x4e && b(3) === 0x47 &&
    b(4) === 0x0d && b(5) === 0x0a && b(6) === 0x1a && b(7) === 0x0a
  ) {
    return 'image/png';
  }
  const ascii = (from: number, to: number): string => Buffer.from(bytes.subarray(from, to)).toString('latin1');
  if (bytes.length >= 12 && ascii(0, 4) === 'RIFF' && ascii(8, 12) === 'WEBP') return 'image/webp';
  return null;
}

export function isPhotoKey(key: string): boolean {
  return UUID_PATTERN.test(key);
}

export interface StoredPhoto {
  bytes: Buffer;
  mime: PhotoMime;
}

export interface PhotoStorage {
  /** Guarda una imagen YA validada y devuelve su llave nueva. */
  save(bytes: Buffer): Promise<string>;
  /** La foto de esa llave, o null si no existe. */
  read(key: string): Promise<StoredPhoto | null>;
  /** Borra la foto (si no existe, no hace nada). */
  remove(key: string): Promise<void>;
}

/**
 * Fotos en un directorio local, un archivo por llave y sin extensión: el tipo se vuelve a
 * leer de los bytes al servirla. Ninguna ruta se arma con datos del cliente.
 */
export function createDiskPhotoStorage(directory: string): PhotoStorage {
  const root = resolve(directory);
  const pathOf = (key: string): string => {
    if (!isPhotoKey(key)) throw new Error('Llave de foto inválida');
    return resolve(root, key);
  };

  return {
    async save(bytes) {
      if (detectPhotoMime(bytes) === null) throw new Error('La foto no es una imagen admitida');
      await mkdir(root, { recursive: true });
      const key = randomUUID();
      // flag 'wx': jamás sobrescribe un archivo existente.
      await writeFile(pathOf(key), bytes, { flag: 'wx' });
      return key;
    },

    async read(key) {
      if (!isPhotoKey(key)) return null;
      let bytes: Buffer;
      try {
        bytes = await readFile(pathOf(key));
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') return null;
        throw error;
      }
      const mime = detectPhotoMime(bytes);
      return mime ? { bytes, mime } : null;
    },

    async remove(key) {
      if (!isPhotoKey(key)) return;
      await rm(pathOf(key), { force: true });
    },
  };
}
