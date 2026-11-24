// Adaptador de PushNotifier para FCM HTTP v1, sin dependencias (D43): fetch nativo y node:crypto.
//
// *** No verificado contra FCM real (D43). *** Se probó solo con un fetch simulado; hace falta
// una cuenta de servicio real del proyecto Firebase para comprobar la entrega.
//
// Flujo:
//   1. La cuenta de servicio (JSON fuera del repo) se lee y valida UNA vez al construir.
//   2. Se firma un JWT RS256 con su llave privada y se canjea en token_uri por un access token
//      OAuth2 (se guarda hasta exp - 60 s; una sola renovación en vuelo).
//   3. FCM v1 no tiene multicast: se manda un POST por token, con concurrencia acotada.
//
// Reglas de errores de FCM:
//   - token_uri solo puede ser https en un host de Google permitido (la aserción JWT firmada se
//     envía ahí); si no, falla al construir nombrando el campo, nunca su valor.
//   - Un token es "inválido" (quien llama lo borra) solo si FCM lo señala con certeza:
//       404 con errorCode UNREGISTERED, o 400 cuyo detalle google.rpc.BadRequest trae un
//       fieldViolation con field === 'message.token'. Cualquier otro 400 (p. ej. un payload mal
//       formado) cuenta como `failed`: no se borra nada.
//   - Salvaguarda: si en un envío con >= 2 destinatarios TODOS salen inválidos, se tratan como
//     `failed` (invalidTokens vacío) y se registra un warn con conteos: probable error del mensaje.
//   - Las peticiones usan redirect 'error' y todo cuerpo de respuesta no leído se cancela.
//
// Seguridad: ni el contenido del JSON, ni la llave, ni los access tokens, ni los tokens de
// dispositivo, ni los cuerpos de respuesta de Google se escriben en logs ni en mensajes de error.
import { createPrivateKey, createSign, type KeyObject } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { z } from 'zod';
import {
  buildPushData,
  type PushAlertInput,
  type PushLogger,
  type PushNotifier,
  type PushResult,
} from './push-notifier.js';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const DEFAULT_TOKEN_URI = 'https://oauth2.googleapis.com/token';
// Hosts permitidos para token_uri (www.googleapis.com aparece en JSON antiguos).
const ALLOWED_TOKEN_URI_HOSTS: ReadonlySet<string> = new Set(['oauth2.googleapis.com', 'www.googleapis.com']);
const FCM_HOST = 'https://fcm.googleapis.com';
const JWT_LIFETIME_SECONDS = 3600;
// Margen para no usar un access token a punto de vencer.
const TOKEN_SAFETY_MARGIN_MS = 60_000;
// Espera sin Retry-After (se multiplica por el número de intento) y tope del Retry-After del proveedor.
const DEFAULT_BACKOFF_MS = 500;
const DEFAULT_MAX_RETRY_AFTER_MS = 10_000;
const DEFAULT_CONCURRENCY = 5;
const DEFAULT_TIMEOUT_MS = 10_000;

const serviceAccountSchema = z.object({
  client_email: z.string().min(1),
  private_key: z.string().min(1),
  token_uri: z.string().min(1).optional(),
});

const oauthResponseSchema = z.object({
  access_token: z.string().min(1),
  expires_in: z.number().positive(),
});

const fcmErrorSchema = z.object({
  error: z
    .object({
      status: z.string().optional(),
      details: z
        .array(
          z.looseObject({
            errorCode: z.string().optional(),
            fieldViolations: z.array(z.looseObject({ field: z.string().optional() })).optional(),
          }),
        )
        .optional(),
    })
    .optional(),
});

export interface FcmNotifierOptions {
  projectId: string;
  /** Ruta al JSON de la cuenta de servicio (fuera del repo). */
  serviceAccountFile: string;
  /** Intentos totales por token ante 429, 5xx o error de red (PUSH_MAX_ATTEMPTS). */
  maxAttempts: number;
  /** Vida del mensaje en FCM, en segundos (ACCEPT_TIMEOUT_SECONDS). */
  ttlSeconds: number;
  logger?: PushLogger;
  /** Inyectables para pruebas. */
  fetch?: typeof fetch;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  concurrency?: number;
  timeoutMs?: number;
  maxRetryAfterMs?: number;
}

interface ServiceAccount {
  clientEmail: string;
  privateKey: KeyObject;
  tokenUri: string;
}

/** Lee y valida la cuenta de servicio. Los errores nombran campos, nunca valores ni contenido. */
function loadServiceAccount(file: string): ServiceAccount {
  let raw: string;
  try {
    raw = readFileSync(file, 'utf8');
  } catch {
    throw new Error(
      'FCM_SERVICE_ACCOUNT_FILE: no se pudo leer el archivo de la cuenta de servicio (revisa la ruta y los permisos)',
    );
  }
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new Error('FCM_SERVICE_ACCOUNT_FILE: el archivo no es un JSON válido');
  }
  const parsed = serviceAccountSchema.safeParse(json);
  if (!parsed.success) {
    const campos = [...new Set(parsed.error.issues.map((i) => i.path.join('.') || '(raíz)'))];
    throw new Error(
      `FCM_SERVICE_ACCOUNT_FILE: faltan o son inválidos estos campos de la cuenta de servicio: ${campos.join(', ')}`,
    );
  }
  let privateKey: KeyObject;
  try {
    privateKey = createPrivateKey(parsed.data.private_key);
  } catch {
    throw new Error('FCM_SERVICE_ACCOUNT_FILE: private_key no es una llave privada válida');
  }
  if (privateKey.asymmetricKeyType !== 'rsa') {
    throw new Error('FCM_SERVICE_ACCOUNT_FILE: private_key debe ser una llave RSA');
  }
  const tokenUri = parsed.data.token_uri ?? DEFAULT_TOKEN_URI;
  if (!isAllowedTokenUri(tokenUri)) {
    throw new Error('FCM_SERVICE_ACCOUNT_FILE: token_uri debe ser https y de un host de Google permitido');
  }
  return { clientEmail: parsed.data.client_email, privateKey, tokenUri };
}

function isAllowedTokenUri(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.protocol === 'https:' &&
      ALLOWED_TOKEN_URI_HOSTS.has(url.hostname) &&
      url.port === '' &&
      url.username === '' &&
      url.password === ''
    );
  } catch {
    return false;
  }
}

const b64url = (value: string | Buffer): string => Buffer.from(value).toString('base64url');

/** JWT RS256 de la cuenta de servicio (aserción para el grant jwt-bearer). */
export function signServiceAccountJwt(account: ServiceAccount, nowSeconds: number): string {
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(
    JSON.stringify({
      iss: account.clientEmail,
      scope: FCM_SCOPE,
      aud: account.tokenUri,
      iat: nowSeconds,
      exp: nowSeconds + JWT_LIFETIME_SECONDS,
    }),
  );
  const input = `${header}.${claims}`;
  const signature = createSign('RSA-SHA256').update(input).sign(account.privateKey);
  return `${input}.${b64url(signature)}`;
}

/** Retry-After en milisegundos (segundos o fecha HTTP), o null si falta o no se entiende. */
function parseRetryAfterMs(header: string | null, nowMs: number): number | null {
  if (!header) return null;
  const trimmed = header.trim();
  if (/^\d+$/.test(trimmed)) return Number(trimmed) * 1000;
  const date = Date.parse(trimmed);
  return Number.isNaN(date) ? null : Math.max(0, date - nowMs);
}

type Outcome = 'sent' | 'failed' | 'invalid';

/** Descarta el cuerpo de una respuesta que no se va a leer (libera la conexión). */
async function discardBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // Nada que hacer: solo se libera el recurso.
  }
}

export function createFcmNotifier(options: FcmNotifierOptions): PushNotifier {
  const account = loadServiceAccount(options.serviceAccountFile);
  const doFetch = options.fetch ?? fetch;
  const now = options.now ?? Date.now;
  const sleep = options.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const concurrency = Math.max(1, options.concurrency ?? DEFAULT_CONCURRENCY);
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxRetryAfterMs = options.maxRetryAfterMs ?? DEFAULT_MAX_RETRY_AFTER_MS;
  const sendUrl = `${FCM_HOST}/v1/projects/${encodeURIComponent(options.projectId)}/messages:send`;

  let cached: { value: string; expiresAtMs: number } | null = null;
  let renewing: Promise<string> | null = null;

  async function requestAccessToken(): Promise<string> {
    const assertion = signServiceAccountJwt(account, Math.floor(now() / 1000));
    const response = await doFetch(account.tokenUri, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }).toString(),
      signal: AbortSignal.timeout(timeoutMs),
      redirect: 'error',
    });
    if (!response.ok) {
      // Solo el código: el cuerpo de Google podría repetir datos de la cuenta.
      await discardBody(response);
      options.logger?.warn({ status: response.status }, 'OAuth de Google rechazó la solicitud');
      throw new Error(`OAuth de Google respondió ${String(response.status)}`);
    }
    const body = oauthResponseSchema.safeParse(await response.json());
    if (!body.success) throw new Error('OAuth de Google respondió con un formato inesperado');
    cached = {
      value: body.data.access_token,
      expiresAtMs: now() + body.data.expires_in * 1000,
    };
    return body.data.access_token;
  }

  async function getAccessToken(): Promise<string> {
    if (cached && now() < cached.expiresAtMs - TOKEN_SAFETY_MARGIN_MS) return cached.value;
    // Una sola renovación en vuelo: los envíos concurrentes esperan la misma promesa.
    renewing ??= requestAccessToken().finally(() => {
      renewing = null;
    });
    return renewing;
  }

  /** Descarta el access token solo si sigue siendo el que falló (otro envío pudo renovarlo ya). */
  function invalidateAccessToken(used: string): void {
    if (cached?.value === used) cached = null;
  }

  /** Lee el error de FCM v1; ante cualquier duda devuelve valores neutros (no inválido). */
  async function readFcmError(
    response: Response,
  ): Promise<{ errorCode: string | null; tokenViolation: boolean }> {
    try {
      const parsed = fcmErrorSchema.safeParse(await response.json());
      if (!parsed.success) return { errorCode: null, tokenViolation: false };
      const details = parsed.data.error?.details ?? [];
      return {
        errorCode: details.find((d) => d.errorCode !== undefined)?.errorCode ?? null,
        tokenViolation: details.some((d) =>
          d.fieldViolations?.some((v) => v.field === 'message.token'),
        ),
      };
    } catch {
      return { errorCode: null, tokenViolation: false };
    }
  }

  async function sendOne(token: string, data: Record<string, string>): Promise<Outcome> {
    const body = JSON.stringify({
      message: {
        token,
        data,
        // Android solo datos: la app arma la notificación (canal de alarma, D45).
        android: { priority: 'HIGH', ttl: `${String(options.ttlSeconds)}s` },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: {
            aps: { alert: { title: 'SafeLink', body: 'Nueva alerta cerca de ti' }, sound: 'default' },
          },
        },
      },
    });
    let attempt = 0;
    let renewedAfter401 = false;
    for (;;) {
      attempt += 1;
      const canRetry = attempt < options.maxAttempts;
      let waitMs: number;
      try {
        const accessToken = await getAccessToken();
        const response = await doFetch(sendUrl, {
          method: 'POST',
          headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' },
          body,
          signal: AbortSignal.timeout(timeoutMs),
          redirect: 'error',
        });
        if (response.ok) {
          await discardBody(response);
          return 'sent';
        }
        const status = response.status;
        if (status === 401 && !renewedAfter401) {
          // El access token ya no vale: se renueva una sola vez y no gasta un intento.
          renewedAfter401 = true;
          await discardBody(response);
          invalidateAccessToken(accessToken);
          attempt -= 1;
          continue;
        }
        if (status === 404 || status === 400) {
          const error = await readFcmError(response);
          const invalid =
            (status === 404 && error.errorCode === 'UNREGISTERED') ||
            (status === 400 && error.tokenViolation);
          return invalid ? 'invalid' : 'failed';
        }
        await discardBody(response);
        if (status !== 429 && status < 500) return 'failed';
        if (!canRetry) return 'failed';
        const asked = parseRetryAfterMs(response.headers.get('retry-after'), now());
        waitMs = Math.min(asked ?? DEFAULT_BACKOFF_MS * attempt, maxRetryAfterMs);
      } catch {
        // Red, timeout o falla al obtener el access token: reintento acotado.
        if (!canRetry) return 'failed';
        waitMs = DEFAULT_BACKOFF_MS * attempt;
      }
      await sleep(waitMs);
    }
  }

  return {
    async sendAlert({ tokens, alertId, urgent }: PushAlertInput): Promise<PushResult> {
      const unique = [...new Set(tokens)];
      const data = buildPushData(alertId, urgent);
      const result: PushResult = { sent: 0, failed: 0, invalidTokens: [] };
      let next = 0;
      const worker = async (): Promise<void> => {
        while (next < unique.length) {
          const token = unique[next++];
          if (token === undefined) return;
          let outcome: Outcome;
          try {
            outcome = await sendOne(token, data);
          } catch {
            outcome = 'failed';
          }
          if (outcome === 'sent') result.sent += 1;
          else {
            result.failed += 1;
            if (outcome === 'invalid') result.invalidTokens.push(token);
          }
        }
      };
      await Promise.all(Array.from({ length: Math.min(concurrency, unique.length) }, worker));
      if (unique.length >= 2 && result.invalidTokens.length === unique.length) {
        // Todos inválidos a la vez: lo más probable es un error del mensaje, no de los tokens.
        options.logger?.warn(
          { alertId, total: unique.length, invalid: result.invalidTokens.length },
          'Push FCM: todos los tokens salieron inválidos; se tratan como fallidos y no se borran',
        );
        result.invalidTokens = [];
      } else {
        const counts = {
          alertId,
          sent: result.sent,
          failed: result.failed,
          invalid: result.invalidTokens.length,
        };
        if (result.failed > 0) options.logger?.warn(counts, 'Push FCM procesado con fallas');
        else options.logger?.info(counts, 'Push FCM procesado');
      }
      return result;
    },
  };
}
