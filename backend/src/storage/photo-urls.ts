// URL firmada de vida corta para ver la foto de una alerta (D2, contrato sección 8).
// La app la abre con Image.network, que no manda el header Authorization; por eso la
// autorización viaja en la propia URL como una firma HMAC con caducidad. NO es el access
// token (que nunca va en el query): solo sirve para esa foto y hasta `exp`.
//
// Quien construye la URL (el serializador de cada rol) ya decidió que ese usuario puede verla.
import { createHmac, timingSafeEqual } from 'node:crypto';

const SIG_PATTERN = /^[0-9a-f]{64}$/;

export interface PhotoUrlSignerOptions {
  /** Secreto del servidor; se deriva una llave propia para no reutilizar la del JWT tal cual. */
  secret: string;
  /** Base pública de la API tal como la ve la app, p. ej. http://192.168.1.10:3000/api/v1 */
  publicApiUrl: string;
  ttlSeconds: number;
  now?: () => Date;
}

export interface PhotoUrlSigner {
  url(alertId: string, photoKey: string): string;
  /** ¿La firma corresponde a esa alerta y foto, y no ha caducado? */
  verify(alertId: string, photoKey: string, exp: number, sig: string): boolean;
}

export function createPhotoUrlSigner(options: PhotoUrlSignerOptions): PhotoUrlSigner {
  const key = createHmac('sha256', options.secret).update('safelink:photo-url:v1').digest();
  const now = options.now ?? (() => new Date());
  const base = options.publicApiUrl.replace(/\/+$/, '');

  // La llave de la foto entra en la firma: si la foto cambia o se borra, la URL deja de servir.
  const firmar = (alertId: string, photoKey: string, exp: number): string =>
    createHmac('sha256', key).update(`${alertId}.${photoKey}.${String(exp)}`).digest('hex');

  return {
    url(alertId, photoKey) {
      const exp = Math.floor(now().getTime() / 1000) + options.ttlSeconds;
      const sig = firmar(alertId, photoKey, exp);
      return `${base}/alerts/${alertId}/photo?exp=${String(exp)}&sig=${sig}`;
    },

    verify(alertId, photoKey, exp, sig) {
      if (!SIG_PATTERN.test(sig) || !Number.isSafeInteger(exp)) return false;
      if (exp < Math.floor(now().getTime() / 1000)) return false;
      const esperada = Buffer.from(firmar(alertId, photoKey, exp), 'hex');
      return timingSafeEqual(esperada, Buffer.from(sig, 'hex'));
    },
  };
}
