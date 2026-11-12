import { randomBytes } from 'node:crypto';
import argon2 from 'argon2';

export interface Argon2Params {
  memoryCost: number;
  timeCost: number;
  parallelism: number;
}

export interface PasswordHasher {
  hash: (plain: string) => Promise<string>;
  /** true solo si la contraseña coincide; un hash ilegible cuenta como no coincidencia. */
  verify: (hash: string, plain: string) => Promise<boolean>;
  /** true si el hash se creó con parámetros distintos a los vigentes. */
  needsRehash: (hash: string) => boolean;
  /**
   * Hash ficticio (mismos parámetros que los reales) para verificar contra algo cuando el
   * correo no existe e igualar los tiempos del login. Se calcula una sola vez.
   */
  dummyHash: () => Promise<string>;
}

/** argon2id con parámetros fijados por configuración (ARGON2_*). */
export function createPasswordHasher(params: Argon2Params): PasswordHasher {
  const options = {
    type: argon2.argon2id,
    memoryCost: params.memoryCost,
    timeCost: params.timeCost,
    parallelism: params.parallelism,
  } as const;
  const hash = (plain: string): Promise<string> => argon2.hash(plain, options);
  let dummy: Promise<string> | undefined;
  return {
    hash,
    async verify(stored, plain) {
      try {
        return await argon2.verify(stored, plain);
      } catch {
        return false;
      }
    },
    needsRehash(stored) {
      try {
        return argon2.needsRehash(stored, params);
      } catch {
        return false;
      }
    },
    dummyHash() {
      dummy ??= hash(randomBytes(32).toString('base64url'));
      return dummy;
    },
  };
}
