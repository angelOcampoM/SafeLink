// BE-04 paso 10 (D43): notificador push (interfaz, no-op, doble y adaptador FCM HTTP v1).
// Nunca se llama a Google: todo pasa por un fetch inyectado. Las llaves RSA son efímeras y el
// JSON de la cuenta de servicio se escribe en un directorio temporal que se borra al final.
import { generateKeyPairSync, verify, type KeyObject } from 'node:crypto';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../src/app.js';
import { ConfigError, loadConfig, type Config } from '../../src/config/env.js';
import { createFcmNotifier, signServiceAccountJwt } from '../../src/notifications/fcm-notifier.js';
import { createNoopNotifier } from '../../src/notifications/noop-notifier.js';
import { buildPushData, type PushLogger } from '../../src/notifications/push-notifier.js';
import { createRecordingNotifier } from '../helpers/recording-notifier.js';

const SECRETO = 'x'.repeat(32);
const PROJECT = 'proyecto-prueba';
const SEND_URL = `https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`;
const DEFAULT_TOKEN_URI = 'https://oauth2.googleapis.com/token';
const CLIENT_EMAIL = 'cuenta@proyecto-prueba.iam.gserviceaccount.com';
const ACCESS_TOKEN_PREFIX = 'ya29.access-secreto-';
const TTL = 30;

let dir: string;
let publicKey: KeyObject;
let privatePem: string;
let accountFile: string;

function writeAccount(name: string, content: unknown): string {
  const file = join(dir, name);
  writeFileSync(file, typeof content === 'string' ? content : JSON.stringify(content));
  return file;
}

/** Mensaje del error al construir el notificador con ese archivo (falla si no lanza). */
function constructError(file: string): string {
  try {
    createFcmNotifier({ projectId: PROJECT, serviceAccountFile: file, maxAttempts: 2, ttlSeconds: TTL });
  } catch (e) {
    return (e as Error).message;
  }
  throw new Error('Se esperaba un error al construir');
}

const TOKEN_URI_ERROR = 'FCM_SERVICE_ACCOUNT_FILE: token_uri debe ser https y de un host de Google permitido';

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), 'safelink-fcm-test-'));
  const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
  publicKey = pair.publicKey;
  privatePem = pair.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  accountFile = writeAccount('cuenta.json', { client_email: CLIENT_EMAIL, private_key: privatePem });
});

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

// ---------- fetch simulado ----------
interface Call {
  url: string;
  init: RequestInit;
  body: string;
}
type Handler = (call: Call, n: number) => Response | Promise<Response>;

const json = (status: number, body: unknown, headers: Record<string, string> = {}): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...headers },
  });

function oauthOk(counter: { n: number }, expiresIn = 3600): Response {
  counter.n += 1;
  return json(200, { access_token: `${ACCESS_TOKEN_PREFIX}${String(counter.n)}`, expires_in: expiresIn });
}

interface Harness {
  calls: Call[];
  oauthCalls: Call[];
  sendCalls: Call[];
  sleeps: number[];
  clock: { ms: number };
  oauthCount: { n: number };
  fetchFn: typeof fetch;
  logs: { level: string; obj: unknown; msg: string }[];
  logger: PushLogger;
}

function harness(onSend: Handler, onOauth?: Handler): Harness {
  const h: Harness = {
    calls: [],
    oauthCalls: [],
    sendCalls: [],
    sleeps: [],
    clock: { ms: 1_700_000_000_000 },
    oauthCount: { n: 0 },
    fetchFn: undefined as unknown as typeof fetch,
    logs: [],
    logger: {
      info: (obj, msg) => h.logs.push({ level: 'info', obj, msg }),
      warn: (obj, msg) => h.logs.push({ level: 'warn', obj, msg }),
    },
  };
  h.fetchFn = (async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    const call: Call = { url, init: init ?? {}, body: String(init?.body ?? '') };
    h.calls.push(call);
    if (url !== SEND_URL) {
      h.oauthCalls.push(call);
      return onOauth ? onOauth(call, h.oauthCalls.length) : oauthOk(h.oauthCount);
    }
    h.sendCalls.push(call);
    return onSend(call, h.sendCalls.length);
  }) as typeof fetch;
  return h;
}

function notifier(h: Harness, extra: Partial<Parameters<typeof createFcmNotifier>[0]> = {}) {
  return createFcmNotifier({
    projectId: PROJECT,
    serviceAccountFile: accountFile,
    maxAttempts: 2,
    ttlSeconds: TTL,
    logger: h.logger,
    fetch: h.fetchFn,
    now: () => h.clock.ms,
    sleep: (ms) => {
      h.sleeps.push(ms);
      return Promise.resolve();
    },
    ...extra,
  });
}

const input = (tokens: string[], urgent = false) => ({ tokens, alertId: 'alerta-1', urgent });
const tokenOf = (c: Call): string => (JSON.parse(c.body) as { message: { token: string } }).message.token;

// ---------- firma ----------
describe('signServiceAccountJwt (D43)', () => {
  const account = () => ({ clientEmail: CLIENT_EMAIL, privateKey: undefined as unknown as KeyObject, tokenUri: DEFAULT_TOKEN_URI });

  it('produce header, claims y firma RS256 verificable', async () => {
    const { createPrivateKey } = await import('node:crypto');
    const acc = { ...account(), privateKey: createPrivateKey(privatePem) };
    const jwt = signServiceAccountJwt(acc, 1_700_000_000);
    const [h, p, s] = jwt.split('.') as [string, string, string];
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'RS256', typ: 'JWT' });
    expect(JSON.parse(Buffer.from(p, 'base64url').toString())).toEqual({
      iss: CLIENT_EMAIL,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: DEFAULT_TOKEN_URI,
      iat: 1_700_000_000,
      exp: 1_700_003_600,
    });
    expect(verify('RSA-SHA256', Buffer.from(`${h}.${p}`), publicKey, Buffer.from(s, 'base64url'))).toBe(true);
    // Alterar el payload invalida la firma.
    expect(verify('RSA-SHA256', Buffer.from(`${h}.${p}x`), publicKey, Buffer.from(s, 'base64url'))).toBe(false);
  });

  it('el aud es el token_uri del JSON cuando existe y es un host de Google permitido (aserción enviada al OAuth)', async () => {
    const uri = 'https://www.googleapis.com/oauth2/v4/token';
    const file = writeAccount('uri.json', {
      client_email: CLIENT_EMAIL,
      private_key: privatePem,
      token_uri: uri,
    });
    const h = harness(() => json(200, {}));
    await notifier(h, { serviceAccountFile: file }).sendAlert(input(['t1']));
    expect(h.oauthCalls[0]?.url).toBe(uri);
    const assertion = new URLSearchParams(h.oauthCalls[0]?.body).get('assertion') ?? '';
    const claims = JSON.parse(Buffer.from(assertion.split('.')[1] ?? '', 'base64url').toString()) as {
      aud: string;
    };
    expect(claims.aud).toBe(uri);
  });

  it.each([
    'http://oauth2.googleapis.com/token',
    'https://evil.example/token',
    'https://oauth2.googleapis.com:8443/token',
    'https://user:pass@oauth2.googleapis.com/token',
    'https://oauth2.googleapis.com.evil.example/token',
    'https://evil.example/oauth2.googleapis.com/token',
  ])('token_uri %s se rechaza al construir, sin mostrar el valor', (uri) => {
    const m = constructError(
      writeAccount('uri-rechazada.json', { client_email: CLIENT_EMAIL, private_key: privatePem, token_uri: uri }),
    );
    expect(m).toBe(TOKEN_URI_ERROR);
    for (const parte of ['evil', 'pass', 'user', '8443', 'http:']) expect(m).not.toContain(parte);
  });
});

// ---------- OAuth ----------
describe('FCM - OAuth', () => {
  it('POST al token_uri con grant_type jwt-bearer y assertion RS256 verificable; iat usa el reloj inyectado', async () => {
    const h = harness(() => json(200, {}));
    await notifier(h).sendAlert(input(['t1']));
    expect(h.oauthCalls).toHaveLength(1);
    const c = h.oauthCalls[0] as Call;
    expect(c.url).toBe(DEFAULT_TOKEN_URI);
    expect(c.init.method).toBe('POST');
    const form = new URLSearchParams(c.body);
    expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    const [hd, pl, sg] = (form.get('assertion') ?? '').split('.') as [string, string, string];
    expect(verify('RSA-SHA256', Buffer.from(`${hd}.${pl}`), publicKey, Buffer.from(sg, 'base64url'))).toBe(true);
    const claims = JSON.parse(Buffer.from(pl, 'base64url').toString()) as { iat: number; exp: number };
    expect(claims.iat).toBe(Math.floor(h.clock.ms / 1000));
    expect(claims.exp).toBe(claims.iat + 3600);
  });

  it('un solo token OAuth para N envíos', async () => {
    const h = harness(() => json(200, {}));
    const r = await notifier(h).sendAlert(input(['a', 'b', 'c', 'd']));
    expect(r.sent).toBe(4);
    expect(h.oauthCalls).toHaveLength(1);
    for (const c of h.sendCalls) {
      expect((c.init.headers as Record<string, string>).authorization).toBe(`Bearer ${ACCESS_TOKEN_PREFIX}1`);
    }
  });

  it('se renueva con now avanzado a exp - 60 s, pero no un segundo antes', async () => {
    const h = harness(() => json(200, {}));
    const n = notifier(h);
    await n.sendAlert(input(['a']));
    h.clock.ms += (3600 - 61) * 1000;
    await n.sendAlert(input(['b']));
    expect(h.oauthCalls).toHaveLength(1);
    h.clock.ms += 1000; // ahora = exp - 60 s
    await n.sendAlert(input(['c']));
    expect(h.oauthCalls).toHaveLength(2);
    expect((h.sendCalls[2]?.init.headers as Record<string, string>).authorization).toBe(
      `Bearer ${ACCESS_TOKEN_PREFIX}2`,
    );
  });

  it('sendAlert concurrentes comparten una sola renovación en vuelo', async () => {
    let release: () => void = () => undefined;
    const gate = new Promise<void>((r) => (release = r));
    const h = harness(
      () => json(200, {}),
      async () => {
        await gate;
        return oauthOk(h.oauthCount);
      },
    );
    const n = notifier(h);
    const all = Promise.all([n.sendAlert(input(['a'])), n.sendAlert(input(['b'])), n.sendAlert(input(['c']))]);
    await new Promise((r) => setImmediate(r));
    release();
    const results = await all;
    expect(results.map((r) => r.sent)).toEqual([1, 1, 1]);
    expect(h.oauthCalls).toHaveLength(1);
  });

  it('fallo de OAuth: no lanza y cuenta todos como fallidos', async () => {
    const h = harness(
      () => json(200, {}),
      () => json(500, { error: 'boom' }),
    );
    const r = await notifier(h, { maxAttempts: 1 }).sendAlert(input(['a', 'b', 'c']));
    expect(r).toEqual({ sent: 0, failed: 3, invalidTokens: [] });
    expect(h.sendCalls).toHaveLength(0);
  });

  it('OAuth con formato inesperado: no lanza y todos fallan', async () => {
    const h = harness(
      () => json(200, {}),
      () => json(200, { nada: true }),
    );
    const r = await notifier(h, { maxAttempts: 1 }).sendAlert(input(['a', 'b']));
    expect(r).toEqual({ sent: 0, failed: 2, invalidTokens: [] });
  });
});

// ---------- envío ----------
describe('FCM - envío', () => {
  it('un POST por token a la URL del proyecto con Bearer y cuerpo exacto', async () => {
    const h = harness(() => json(200, { name: 'ok' }));
    const r = await notifier(h).sendAlert({ tokens: ['tok-A', 'tok-B'], alertId: 'alerta-9', urgent: true });
    expect(r).toEqual({ sent: 2, failed: 0, invalidTokens: [] });
    expect(h.sendCalls).toHaveLength(2);
    for (const c of h.sendCalls) {
      expect(c.url).toBe(SEND_URL);
      expect(c.init.method).toBe('POST');
      expect((c.init.headers as Record<string, string>).authorization).toBe(`Bearer ${ACCESS_TOKEN_PREFIX}1`);
    }
    const body = JSON.parse((h.sendCalls[0] as Call).body) as unknown;
    expect(body).toEqual({
      message: {
        token: 'tok-A',
        data: { type: 'alert', alertId: 'alerta-9', urgent: 'true' },
        android: { priority: 'HIGH', ttl: `${String(TTL)}s` },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: {
            aps: { alert: { title: 'SafeLink', body: 'Nueva alerta cerca de ti' }, sound: 'default' },
          },
        },
      },
    });
    expect(tokenOf(h.sendCalls[1] as Call)).toBe('tok-B');
  });

  it('urgent=false viaja como "false"; buildPushData solo tiene tipo, alertId y urgencia', () => {
    expect(buildPushData('x', false)).toEqual({ type: 'alert', alertId: 'x', urgent: 'false' });
    expect(buildPushData('x', true).urgent).toBe('true');
  });

  it('el payload no contiene teléfono, ubicación, nombre ni foto', async () => {
    const h = harness(() => json(200, {}));
    await notifier(h).sendAlert(input(['t1'], true));
    const text = ((h.sendCalls[0] as Call).body).toLowerCase();
    for (const prohibido of ['phone', 'telefono', 'teléfono', 'lat', 'lng', 'location', 'name', 'nombre', 'photo', 'foto']) {
      expect(text).not.toContain(prohibido);
    }
    const data = (JSON.parse((h.sendCalls[0] as Call).body) as { message: { data: object } }).message.data;
    expect(Object.keys(data).sort()).toEqual(['alertId', 'type', 'urgent']);
  });

  it('tokens duplicados se envían una vez', async () => {
    const h = harness(() => json(200, {}));
    const r = await notifier(h).sendAlert(input(['a', 'b', 'a', 'a', 'b']));
    expect(h.sendCalls).toHaveLength(2);
    expect(r.sent).toBe(2);
  });

  it('lista vacía: sin llamadas y resultado en cero', async () => {
    const h = harness(() => json(200, {}));
    const r = await notifier(h).sendAlert(input([]));
    expect(r).toEqual({ sent: 0, failed: 0, invalidTokens: [] });
    expect(h.calls).toHaveLength(0);
  });

  it('la concurrencia nunca supera la configurada', async () => {
    let active = 0;
    let max = 0;
    const h = harness(async () => {
      active += 1;
      max = Math.max(max, active);
      await new Promise((r) => setTimeout(r, 1));
      active -= 1;
      return json(200, {});
    });
    const tokens = Array.from({ length: 12 }, (_, i) => `t${String(i)}`);
    const r = await notifier(h, { concurrency: 3 }).sendAlert(input(tokens));
    expect(r.sent).toBe(12);
    expect(max).toBeLessThanOrEqual(3);
    expect(max).toBeGreaterThan(1);
  });
});

// ---------- errores ----------
describe('FCM - errores por token', () => {
  const fcmErr = (status: number, code: string, headers?: Record<string, string>) =>
    json(status, { error: { code: status, status: code, details: [{ '@type': 'x', errorCode: code }] } }, headers);

  const tokenViolation = (field = 'message.token') =>
    json(400, {
      error: {
        code: 400,
        status: 'INVALID_ARGUMENT',
        details: [
          {
            '@type': 'type.googleapis.com/google.rpc.BadRequest',
            fieldViolations: [{ field, description: 'x' }],
          },
        ],
      },
    });

  it('404 UNREGISTERED -> invalidTokens (con un token bueno en el lote)', async () => {
    const h = harness((c) => (tokenOf(c) === 'muerto' ? fcmErr(404, 'UNREGISTERED') : json(200, {})));
    const r = await notifier(h).sendAlert(input(['bueno', 'muerto']));
    expect(r).toEqual({ sent: 1, failed: 1, invalidTokens: ['muerto'] });
    expect(h.sleeps).toEqual([]);
  });

  it('400 genérico (INVALID_ARGUMENT sin fieldViolations) -> failed y NO invalidTokens', async () => {
    const h = harness((c) => (tokenOf(c) === 'malo' ? fcmErr(400, 'INVALID_ARGUMENT') : json(200, {})));
    const r = await notifier(h).sendAlert(input(['bueno', 'malo']));
    expect(r).toEqual({ sent: 1, failed: 1, invalidTokens: [] });
    expect(h.sleeps).toEqual([]);
  });

  it('400 con fieldViolation de otro campo (no message.token) -> failed y NO invalidTokens', async () => {
    const h = harness((c) => (tokenOf(c) === 'malo' ? tokenViolation('message.data') : json(200, {})));
    const r = await notifier(h).sendAlert(input(['bueno', 'malo']));
    expect(r).toEqual({ sent: 1, failed: 1, invalidTokens: [] });
  });

  it('400 con fieldViolations message.token -> invalidTokens', async () => {
    const h = harness((c) => (tokenOf(c) === 'malo' ? tokenViolation() : json(200, {})));
    const r = await notifier(h).sendAlert(input(['bueno', 'malo']));
    expect(r).toEqual({ sent: 1, failed: 1, invalidTokens: ['malo'] });
  });

  it('mezcla: 404 UNREGISTERED y 400 message.token inválidos junto a uno bueno', async () => {
    const h = harness((c) => {
      const t = tokenOf(c);
      if (t === 'muerto') return fcmErr(404, 'UNREGISTERED');
      if (t === 'malo') return tokenViolation();
      return json(200, {});
    });
    const r = await notifier(h).sendAlert(input(['bueno', 'muerto', 'malo']));
    expect(r.sent).toBe(1);
    expect(r.failed).toBe(2);
    expect([...r.invalidTokens].sort()).toEqual(['malo', 'muerto']);
  });

  it('400 con cuerpo no JSON: failed, no inválido', async () => {
    const h = harness(() => new Response('<html>', { status: 400 }));
    const r = await notifier(h).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  describe('salvaguarda: todos inválidos a la vez (>= 2 destinatarios)', () => {
    const cases: [string, string[], (t: string) => Response][] = [
      ['2 UNREGISTERED', ['a', 'b'], () => fcmErr(404, 'UNREGISTERED')],
      ['2 message.token', ['a', 'b'], () => tokenViolation()],
      [
        '3 mezcla UNREGISTERED y message.token',
        ['a', 'b', 'c'],
        (t) => (t === 'b' ? tokenViolation() : fcmErr(404, 'UNREGISTERED')),
      ],
    ];
    it.each(cases)('%s -> invalidTokens vacío, failed = n y un warn con conteos', async (_n, tokens, mk) => {
      const h = harness((c) => mk(tokenOf(c)));
      const r = await notifier(h).sendAlert(input(tokens));
      expect(r).toEqual({ sent: 0, failed: tokens.length, invalidTokens: [] });
      expect(h.logs).toHaveLength(1);
      expect(h.logs[0]?.level).toBe('warn');
      const obj = h.logs[0]?.obj as Record<string, unknown>;
      expect(obj.alertId).toBe('alerta-1');
      expect(obj.total).toBe(tokens.length);
      expect(obj.invalid).toBe(tokens.length);
      for (const t of tokens) expect(JSON.stringify(h.logs)).not.toContain(`"${t}"`);
    });

    it('1 solo token inválido -> sí va a invalidTokens (la salvaguarda no aplica)', async () => {
      const h = harness(() => fcmErr(404, 'UNREGISTERED'));
      const r = await notifier(h).sendAlert(input(['solo']));
      expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: ['solo'] });
    });

    it('tokens duplicados que se reducen a 1 inválido -> sí va a invalidTokens', async () => {
      const h = harness(() => fcmErr(404, 'UNREGISTERED'));
      const r = await notifier(h).sendAlert(input(['solo', 'solo']));
      expect(r.invalidTokens).toEqual(['solo']);
    });

    it('2 tokens, solo 1 inválido (el otro falla con 403) -> invalidTokens conserva el inválido', async () => {
      const h = harness((c) => (tokenOf(c) === 'a' ? fcmErr(404, 'UNREGISTERED') : json(403, {})));
      const r = await notifier(h).sendAlert(input(['a', 'b']));
      expect(r).toEqual({ sent: 0, failed: 2, invalidTokens: ['a'] });
    });
  });

  describe('redirect y cancelación de cuerpos', () => {
    it('el init de cada fetch (OAuth y FCM) lleva redirect "error"', async () => {
      const h = harness(() => json(200, {}));
      await notifier(h).sendAlert(input(['a', 'b']));
      expect(h.oauthCalls.length).toBeGreaterThan(0);
      expect(h.sendCalls).toHaveLength(2);
      for (const c of h.calls) expect(c.init.redirect).toBe('error');
    });

    it('fetch de FCM que lanza por redirección cuenta como fallo de red (reintento acotado) y no lanza', async () => {
      const h = harness(() => {
        throw new TypeError('redirect mode is set to error');
      });
      const r = await notifier(h, { maxAttempts: 3 }).sendAlert(input(['a']));
      expect(h.sendCalls).toHaveLength(3);
      expect(h.sleeps).toEqual([500, 1000]);
      expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
    });

    it('fetch de OAuth que lanza por redirección: reintento acotado, no se envía nada y no lanza', async () => {
      const h = harness(
        () => json(200, {}),
        () => {
          throw new TypeError('redirect mode is set to error');
        },
      );
      const r = await notifier(h, { maxAttempts: 3 }).sendAlert(input(['a']));
      expect(h.oauthCalls).toHaveLength(3);
      expect(h.sendCalls).toHaveLength(0);
      expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
    });

    /** Respuesta cuyo body espía la llamada a cancel(). */
    function spied(status: number, headers: Record<string, string> = {}): { res: Response; cancel: ReturnType<typeof vi.fn> } {
      const res = json(status, {}, headers);
      const body = res.body as ReadableStream;
      const original = body.cancel.bind(body);
      const cancel = vi.fn(() => original());
      Object.defineProperty(res, 'body', { value: { cancel } });
      return { res, cancel };
    }

    it.each([
      ['éxito 200', 200, 1, 1],
      ['429 con reintento', 429, 2, 2],
      ['5xx con reintento', 503, 2, 2],
      ['403 sin reintento', 403, 1, 1],
    ])('%s: cada cuerpo no leído se cancela', async (_n, status, expectedCalls, expectedCancels) => {
      const spies: ReturnType<typeof vi.fn>[] = [];
      const h = harness(() => {
        const s = spied(status);
        spies.push(s.cancel);
        return s.res;
      });
      await notifier(h, { maxAttempts: 2 }).sendAlert(input(['a']));
      expect(h.sendCalls).toHaveLength(expectedCalls);
      expect(spies).toHaveLength(expectedCalls);
      expect(spies.reduce((n, c) => n + c.mock.calls.length, 0)).toBe(expectedCancels);
    });

    it('401: el cuerpo del 401 se cancela antes de renovar el access token', async () => {
      const spies: ReturnType<typeof vi.fn>[] = [];
      const h = harness((c) => {
        if ((c.init.headers as Record<string, string>).authorization === `Bearer ${ACCESS_TOKEN_PREFIX}1`) {
          const s = spied(401);
          spies.push(s.cancel);
          return s.res;
        }
        return json(200, {});
      });
      const r = await notifier(h, { maxAttempts: 1 }).sendAlert(input(['a']));
      expect(r.sent).toBe(1);
      expect(spies).toHaveLength(1);
      expect(spies[0]).toHaveBeenCalledTimes(1);
    });

    it('OAuth rechazado: se cancela el cuerpo', async () => {
      const spies: ReturnType<typeof vi.fn>[] = [];
      const h = harness(
        () => json(200, {}),
        () => {
          const s = spied(500);
          spies.push(s.cancel);
          return s.res;
        },
      );
      await notifier(h, { maxAttempts: 1 }).sendAlert(input(['a']));
      expect(spies).toHaveLength(1);
      expect(spies[0]).toHaveBeenCalledTimes(1);
    });

    it('un cancel() que lanza no rompe el envío', async () => {
      const h = harness(() => {
        const res = json(200, {});
        Object.defineProperty(res, 'body', {
          value: { cancel: () => Promise.reject(new Error('ya cerrado')) },
        });
        return res;
      });
      const r = await notifier(h).sendAlert(input(['a']));
      expect(r).toEqual({ sent: 1, failed: 0, invalidTokens: [] });
    });
  });

  it('404 sin UNREGISTERED: fallido y no inválido', async () => {
    const h = harness(() => json(404, { error: { status: 'NOT_FOUND' } }));
    const r = await notifier(h).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  it('404 con cuerpo no JSON: fallido, no inválido', async () => {
    const h = harness(() => new Response('<html>', { status: 404 }));
    const r = await notifier(h).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  it('400 con otro estado: fallido, no inválido', async () => {
    const h = harness(() => fcmErr(400, 'FAILED_PRECONDITION'));
    const r = await notifier(h).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  it('429 reintenta hasta PUSH_MAX_ATTEMPTS respetando Retry-After en segundos', async () => {
    const h = harness(() => json(429, {}, { 'retry-after': '3' }));
    const r = await notifier(h, { maxAttempts: 3 }).sendAlert(input(['a']));
    expect(h.sendCalls).toHaveLength(3);
    expect(h.sleeps).toEqual([3000, 3000]);
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  it('503 con Retry-After como fecha HTTP', async () => {
    const h = harness(() => json(503, {}, { 'retry-after': new Date(h.clock.ms + 4000).toUTCString() }));
    await notifier(h, { maxAttempts: 2 }).sendAlert(input(['a']));
    expect(h.sendCalls).toHaveLength(2);
    expect(h.sleeps).toHaveLength(1);
    // toUTCString trunca milisegundos: la espera queda entre 3 y 4 s.
    expect(h.sleeps[0]).toBeGreaterThan(2999);
    expect(h.sleeps[0]).toBeLessThanOrEqual(4000);
  });

  it('Retry-After con fecha pasada no espera de más (0 ms)', async () => {
    const h = harness(() => json(503, {}, { 'retry-after': new Date(h.clock.ms - 60_000).toUTCString() }));
    await notifier(h).sendAlert(input(['a']));
    expect(h.sleeps).toEqual([0]);
  });

  it('Retry-After se topa en maxRetryAfterMs', async () => {
    const h = harness(() => json(429, {}, { 'retry-after': '3600' }));
    await notifier(h, { maxRetryAfterMs: 5000 }).sendAlert(input(['a']));
    expect(h.sleeps).toEqual([5000]);
  });

  it('Retry-After ilegible se trata como ausente', async () => {
    const h = harness(() => json(429, {}, { 'retry-after': 'pronto' }));
    await notifier(h).sendAlert(input(['a']));
    expect(h.sleeps).toEqual([500]);
  });

  it('sin Retry-After la espera es incremental', async () => {
    const h = harness(() => json(500, {}));
    await notifier(h, { maxAttempts: 4 }).sendAlert(input(['a']));
    expect(h.sendCalls).toHaveLength(4);
    expect(h.sleeps).toEqual([500, 1000, 1500]);
  });

  it('un 5xx seguido de éxito cuenta como enviado', async () => {
    const h = harness((_c, n) => (n === 1 ? json(502, {}) : json(200, {})));
    const r = await notifier(h).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 1, failed: 0, invalidTokens: [] });
    expect(h.sendCalls).toHaveLength(2);
  });

  it('PUSH_MAX_ATTEMPTS=1 no reintenta', async () => {
    const h = harness(() => json(500, {}));
    const r = await notifier(h, { maxAttempts: 1 }).sendAlert(input(['a']));
    expect(h.sendCalls).toHaveLength(1);
    expect(h.sleeps).toEqual([]);
    expect(r.failed).toBe(1);
  });

  it('otros 4xx no se reintentan', async () => {
    for (const status of [403, 405, 413]) {
      const h = harness(() => json(status, {}));
      const r = await notifier(h, { maxAttempts: 5 }).sendAlert(input(['a']));
      expect(h.sendCalls).toHaveLength(1);
      expect(h.sleeps).toEqual([]);
      expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
    }
  });

  it('401: renueva el access token una vez y reintenta sin gastar intento', async () => {
    const h = harness((c) =>
      (c.init.headers as Record<string, string>).authorization === `Bearer ${ACCESS_TOKEN_PREFIX}1`
        ? json(401, {})
        : json(200, {}),
    );
    // maxAttempts 1: si el 401 gastara intento, fallaría.
    const r = await notifier(h, { maxAttempts: 1 }).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 1, failed: 0, invalidTokens: [] });
    expect(h.oauthCalls).toHaveLength(2);
    expect(h.sendCalls).toHaveLength(2);
    expect(h.sleeps).toEqual([]);
  });

  it('segundo 401 -> fallido (sin bucle)', async () => {
    const h = harness(() => json(401, {}));
    const r = await notifier(h, { maxAttempts: 3 }).sendAlert(input(['a']));
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
    expect(h.oauthCalls).toHaveLength(2);
    expect(h.sendCalls).toHaveLength(2);
  });

  it('error de red: reintento acotado y no lanza', async () => {
    const h = harness(() => {
      throw new TypeError('fetch failed');
    });
    const r = await notifier(h, { maxAttempts: 3 }).sendAlert(input(['a']));
    expect(h.sendCalls).toHaveLength(3);
    expect(h.sleeps).toEqual([500, 1000]);
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  it('timeout (AbortSignal): fetch que respeta la señal aborta y se reintenta de forma acotada', async () => {
    const h = harness((c) =>
      new Promise<Response>((_res, rej) => {
        const sig = c.init.signal as AbortSignal;
        sig.addEventListener('abort', () => rej(sig.reason as Error));
      }),
    );
    const r = await notifier(h, { maxAttempts: 2, timeoutMs: 5 }).sendAlert(input(['a']));
    expect(h.sendCalls).toHaveLength(2);
    expect(r).toEqual({ sent: 0, failed: 1, invalidTokens: [] });
  });

  it('el resultado agrega sent/failed/invalidTokens de una mezcla', async () => {
    const h = harness((c) => {
      const t = tokenOf(c);
      if (t === 'ok1' || t === 'ok2') return json(200, {});
      if (t === 'inv') return fcmErr(404, 'UNREGISTERED');
      return json(403, {});
    });
    const r = await notifier(h).sendAlert(input(['ok1', 'inv', 'ok2', 'x']));
    expect(r.sent).toBe(2);
    expect(r.failed).toBe(2);
    expect(r.invalidTokens).toEqual(['inv']);
  });
});

// ---------- cuenta de servicio ----------
describe('FCM - cuenta de servicio inválida', () => {
  const SECRET_MARK = 'CONTENIDO-SECRETO-NO-FILTRAR';
  const opts = (file: string) => ({
    projectId: PROJECT,
    serviceAccountFile: file,
    maxAttempts: 2,
    ttlSeconds: TTL,
  });

  function message(file: string): string {
    try {
      createFcmNotifier(opts(file));
    } catch (e) {
      return (e as Error).message;
    }
    throw new Error('Se esperaba un error al construir');
  }

  it('archivo inexistente', () => {
    const m = message(join(dir, 'no-existe.json'));
    expect(m).toContain('FCM_SERVICE_ACCOUNT_FILE');
    expect(m).toContain('no se pudo leer');
  });

  it('JSON inválido, sin filtrar el contenido', () => {
    const m = message(writeAccount('malo.json', `{ ${SECRET_MARK}`));
    expect(m).toContain('JSON válido');
    expect(m).not.toContain(SECRET_MARK);
  });

  it('sin client_email nombra el campo', () => {
    const m = message(writeAccount('sin-email.json', { private_key: privatePem }));
    expect(m).toContain('client_email');
    expect(m).not.toContain('BEGIN PRIVATE KEY');
    expect(m).not.toContain(privatePem.slice(40, 80));
  });

  it('sin private_key nombra el campo', () => {
    const m = message(writeAccount('sin-llave.json', { client_email: SECRET_MARK }));
    expect(m).toContain('private_key');
    expect(m).not.toContain(SECRET_MARK);
  });

  it('private_key inválida, sin filtrar su valor', () => {
    const m = message(
      writeAccount('llave-mala.json', { client_email: CLIENT_EMAIL, private_key: SECRET_MARK }),
    );
    expect(m).toContain('private_key');
    expect(m).not.toContain(SECRET_MARK);
  });

  it('token_uri con esquema ftp se rechaza con el mensaje de host de Google permitido', () => {
    const m = message(
      writeAccount('uri-mala.json', { client_email: CLIENT_EMAIL, private_key: privatePem, token_uri: 'ftp://x' }),
    );
    expect(m).toBe(TOKEN_URI_ERROR);
    expect(m).not.toContain('ftp');
  });

  it('token_uri que ni es URL se rechaza con el mismo mensaje', () => {
    const m = message(
      writeAccount('uri-basura.json', { client_email: CLIENT_EMAIL, private_key: privatePem, token_uri: 'no es url' }),
    );
    expect(m).toBe(TOKEN_URI_ERROR);
  });

  const noRsa: [string, () => KeyObject][] = [
    ['EC P-256', () => generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey],
    ['Ed25519', () => generateKeyPairSync('ed25519').privateKey],
  ];
  it.each(noRsa)('private_key %s (no RSA) falla al construir sin mostrar la llave', (_n, gen) => {
    const pem = gen().export({ type: 'pkcs8', format: 'pem' }).toString();
    const m = message(writeAccount('llave-no-rsa.json', { client_email: CLIENT_EMAIL, private_key: pem }));
    expect(m).toBe('FCM_SERVICE_ACCOUNT_FILE: private_key debe ser una llave RSA');
    expect(m).not.toContain('BEGIN');
    expect(m).not.toContain(pem.split('\n')[1] ?? 'ausente');
  });
});

// ---------- logs ----------
describe('Logs sin datos sensibles', () => {
  const fcmErrEco = (status: number, code: string, eco: string): Response =>
    json(status, { error: { code: status, status: code, details: [{ errorCode: code }] }, eco });

  it('ni mensajes ni objetos contienen tokens, access token, llave ni JSON; solo conteos y alertId', async () => {
    const tokens = ['TOKEN-DISP-AAA', 'TOKEN-DISP-BBB', 'TOKEN-DISP-CCC', 'TOKEN-DISP-DDD'];
    const h = harness((c) => {
      const t = tokenOf(c);
      if (t === 'TOKEN-DISP-BBB') return fcmErrEco(404, 'UNREGISTERED', t);
      if (t === 'TOKEN-DISP-CCC') return json(500, { eco: t });
      return json(200, {});
    });
    await notifier(h, { maxAttempts: 2 }).sendAlert({ tokens, alertId: 'alerta-log', urgent: true });
    // Fallo de OAuth también.
    const h2 = harness(
      () => json(200, {}),
      () => json(500, { private_key: privatePem }),
    );
    await notifier(h2, { maxAttempts: 1 }).sendAlert({ tokens, alertId: 'alerta-log2', urgent: false });

    const prohibidos = [
      ...tokens,
      ACCESS_TOKEN_PREFIX,
      privatePem,
      privatePem.slice(40, 90),
      'BEGIN PRIVATE KEY',
      CLIENT_EMAIL,
      'private_key',
    ];
    const all = [...h.logs, ...h2.logs];
    expect(all.length).toBeGreaterThan(0);
    for (const l of all) {
      const text = `${l.msg} ${JSON.stringify(l.obj)}`;
      for (const p of prohibidos) expect(text).not.toContain(p);
    }
    // Con failed > 0 el nivel es warn y solo lleva alertId y conteos.
    expect(h.logs).toHaveLength(1);
    expect(h.logs[0]?.level).toBe('warn');
    expect(h.logs[0]?.obj).toEqual({ alertId: 'alerta-log', sent: 2, failed: 2, invalid: 1 });
    // Fallo de OAuth: warn con solo {status}, y luego el resumen en warn.
    expect(h2.logs[0]).toMatchObject({ level: 'warn', obj: { status: 500 } });
    expect(h2.logs[0]?.obj).toEqual({ status: 500 });
    expect(h2.logs.every((l) => l.level === 'warn')).toBe(true);
  });

  it('todo bien: un solo info con alertId y conteos, sin datos sensibles', async () => {
    const tokens = ['TOKEN-DISP-AAA', 'TOKEN-DISP-BBB'];
    const h = harness(() => json(200, { eco: 'TOKEN-DISP-AAA' }));
    await notifier(h).sendAlert({ tokens, alertId: 'alerta-ok', urgent: false });
    expect(h.logs).toHaveLength(1);
    expect(h.logs[0]?.level).toBe('info');
    expect(h.logs[0]?.obj).toEqual({ alertId: 'alerta-ok', sent: 2, failed: 0, invalid: 0 });
    const text = JSON.stringify(h.logs);
    for (const p of [...tokens, ACCESS_TOKEN_PREFIX, 'BEGIN PRIVATE KEY', CLIENT_EMAIL, 'private_key']) {
      expect(text).not.toContain(p);
    }
  });

  it('failed > 0 (aunque haya enviados): nivel warn, nunca info', async () => {
    const h = harness((c) => (tokenOf(c) === 'b' ? json(403, {}) : json(200, {})));
    await notifier(h).sendAlert(input(['a', 'b']));
    expect(h.logs.map((l) => l.level)).toEqual(['warn']);
    expect(h.logs[0]?.obj).toEqual({ alertId: 'alerta-1', sent: 1, failed: 1, invalid: 0 });
  });

  it('fallo de OAuth: warn {status} sin cuerpo de Google, sin llave, JSON ni client_email', async () => {
    const h = harness(
      () => json(200, {}),
      () => json(401, { error: 'invalid_grant', detail: privatePem, client_email: CLIENT_EMAIL }),
    );
    await notifier(h, { maxAttempts: 1 }).sendAlert(input(['TOKEN-X']));
    const oauthWarns = h.logs.filter((l) => l.level === 'warn' && JSON.stringify(l.obj) === '{"status":401}');
    expect(oauthWarns).toHaveLength(1);
    const text = JSON.stringify(h.logs);
    for (const p of ['TOKEN-X', 'invalid_grant', 'BEGIN PRIVATE KEY', CLIENT_EMAIL, privatePem.slice(40, 90)]) {
      expect(text).not.toContain(p);
    }
  });
});

// ---------- no-op y doble ----------
describe('No-op y doble de pruebas', () => {
  it('createNoopNotifier no llama fetch y registra solo conteos', async () => {
    const original = globalThis.fetch;
    let called = 0;
    globalThis.fetch = (() => {
      called += 1;
      return Promise.resolve(new Response('{}'));
    }) as typeof fetch;
    try {
      const logs: { obj: unknown; msg: string }[] = [];
      const n = createNoopNotifier({
        info: (obj, msg) => logs.push({ obj, msg }),
        warn: (obj, msg) => logs.push({ obj, msg }),
      });
      const r = await n.sendAlert({ tokens: ['SECRETO-1', 'SECRETO-2'], alertId: 'a1', urgent: true });
      expect(r).toEqual({ sent: 0, failed: 0, invalidTokens: [] });
      expect(called).toBe(0);
      expect(logs).toHaveLength(1);
      expect(logs[0]?.obj).toEqual({ alertId: 'a1', urgent: true, recipients: 2 });
      expect(JSON.stringify(logs)).not.toContain('SECRETO');
    } finally {
      globalThis.fetch = original;
    }
  });

  it('createNoopNotifier funciona sin logger', async () => {
    const r = await createNoopNotifier().sendAlert({ tokens: [], alertId: 'a', urgent: false });
    expect(r).toEqual({ sent: 0, failed: 0, invalidTokens: [] });
  });

  it('createRecordingNotifier guarda copias de las llamadas y responde por defecto todo enviado', async () => {
    const n = createRecordingNotifier();
    const tokens = ['a', 'b'];
    const r = await n.sendAlert({ tokens, alertId: 'x', urgent: false });
    tokens.push('c');
    expect(r).toEqual({ sent: 2, failed: 0, invalidTokens: [] });
    expect(n.calls).toEqual([{ tokens: ['a', 'b'], alertId: 'x', urgent: false }]);
  });

  it('createRecordingNotifier devuelve la respuesta configurada', async () => {
    const n = createRecordingNotifier((i) => ({ sent: 0, failed: i.tokens.length, invalidTokens: [i.tokens[0] ?? ''] }));
    const r = await n.sendAlert({ tokens: ['z', 'y'], alertId: 'x', urgent: true });
    expect(r).toEqual({ sent: 0, failed: 2, invalidTokens: ['z'] });
    expect(n.calls).toHaveLength(1);
  });
});

// ---------- config ----------
describe('loadConfig - push (D43)', () => {
  const base = (extra: Record<string, string> = {}): NodeJS.ProcessEnv => ({ JWT_SECRET: SECRETO, ...extra });
  const msg = (env: NodeJS.ProcessEnv): string => {
    try {
      loadConfig(env);
    } catch (e) {
      expect(e).toBeInstanceOf(ConfigError);
      return (e as ConfigError).message;
    }
    throw new Error('Se esperaba ConfigError');
  };

  it('por defecto PUSH_PROVIDER none y PUSH_MAX_ATTEMPTS 2', () => {
    const c = loadConfig(base());
    expect(c.PUSH_PROVIDER).toBe('none');
    expect(c.PUSH_MAX_ATTEMPTS).toBe(2);
    expect(c.FCM_PROJECT_ID).toBeUndefined();
    expect(c.FCM_SERVICE_ACCOUNT_FILE).toBeUndefined();
  });

  it('cadenas vacías de FCM_* con provider none cuentan como ausentes', () => {
    const c = loadConfig(base({ FCM_PROJECT_ID: '', FCM_SERVICE_ACCOUNT_FILE: '  ' }));
    expect(c.FCM_PROJECT_ID).toBeUndefined();
    expect(c.FCM_SERVICE_ACCOUNT_FILE).toBeUndefined();
  });

  it("'fcm' sin FCM_PROJECT_ID falla nombrando la variable", () => {
    expect(msg(base({ PUSH_PROVIDER: 'fcm', FCM_SERVICE_ACCOUNT_FILE: '/x.json' }))).toContain('FCM_PROJECT_ID');
  });

  it("'fcm' sin FCM_SERVICE_ACCOUNT_FILE falla nombrando la variable", () => {
    expect(msg(base({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: 'p' }))).toContain('FCM_SERVICE_ACCOUNT_FILE');
  });

  it("'fcm' con cadenas vacías falla con ambas variables", () => {
    const m = msg(base({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: '', FCM_SERVICE_ACCOUNT_FILE: '' }));
    expect(m).toContain('FCM_PROJECT_ID');
    expect(m).toContain('FCM_SERVICE_ACCOUNT_FILE');
  });

  it("'fcm' completo es válido", () => {
    const c = loadConfig(base({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: 'p', FCM_SERVICE_ACCOUNT_FILE: '/x.json' }));
    expect(c.PUSH_PROVIDER).toBe('fcm');
  });

  it('PUSH_MAX_ATTEMPTS fuera de 1..5 o no entero se rechaza; los bordes pasan', () => {
    for (const v of ['0', '6', '-1', '1.5', 'abc']) {
      expect(msg(base({ PUSH_MAX_ATTEMPTS: v }))).toContain('PUSH_MAX_ATTEMPTS');
    }
    expect(loadConfig(base({ PUSH_MAX_ATTEMPTS: '1' })).PUSH_MAX_ATTEMPTS).toBe(1);
    expect(loadConfig(base({ PUSH_MAX_ATTEMPTS: '5' })).PUSH_MAX_ATTEMPTS).toBe(5);
  });

  it('PUSH_PROVIDER desconocido se rechaza', () => {
    expect(msg(base({ PUSH_PROVIDER: 'apns' }))).toContain('PUSH_PROVIDER');
  });
});

// ---------- buildApp ----------
describe('buildApp - push (D43)', () => {
  const cfg = (extra: Record<string, string> = {}) => loadConfig({ JWT_SECRET: SECRETO, NODE_ENV: 'test', ...extra });

  it('fcm con cuenta inválida lanza al construir, sin filtrar contenido', () => {
    const file = writeAccount('app-malo.json', '{ CONTENIDO-APP-SECRETO');
    const c = cfg({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: PROJECT, FCM_SERVICE_ACCOUNT_FILE: file });
    let m = '';
    try {
      buildApp(c);
    } catch (e) {
      m = (e as Error).message;
    }
    expect(m).toContain('FCM_SERVICE_ACCOUNT_FILE');
    expect(m).not.toContain('CONTENIDO-APP-SECRETO');
  });

  it('fcm con archivo inexistente lanza al construir', () => {
    const c = cfg({
      PUSH_PROVIDER: 'fcm',
      FCM_PROJECT_ID: PROJECT,
      FCM_SERVICE_ACCOUNT_FILE: join(dir, 'nada.json'),
    });
    expect(() => buildApp(c)).toThrow(/FCM_SERVICE_ACCOUNT_FILE/);
  });

  it.each([
    ['sin FCM_PROJECT_ID', { FCM_PROJECT_ID: undefined }],
    ['con FCM_PROJECT_ID vacío', { FCM_PROJECT_ID: '' }],
    ['sin FCM_SERVICE_ACCOUNT_FILE', { FCM_SERVICE_ACCOUNT_FILE: undefined }],
    ['con FCM_SERVICE_ACCOUNT_FILE vacío', { FCM_SERVICE_ACCOUNT_FILE: '' }],
    ['sin ninguno de los dos', { FCM_PROJECT_ID: undefined, FCM_SERVICE_ACCOUNT_FILE: undefined }],
  ] as [string, Partial<Config>][])(
    'Config con PUSH_PROVIDER=fcm %s (armado sin loadConfig) lanza y no cae al no-op',
    (_n, override) => {
      const c: Config = {
        ...cfg(),
        PUSH_PROVIDER: 'fcm',
        FCM_PROJECT_ID: PROJECT,
        FCM_SERVICE_ACCOUNT_FILE: accountFile,
        ...override,
      };
      expect(() => buildApp(c)).toThrow('PUSH_PROVIDER=fcm requiere FCM_PROJECT_ID y FCM_SERVICE_ACCOUNT_FILE');
    },
  );

  it('fcm con llave EC lanza al construir la app, sin mostrar la llave', () => {
    const pem = generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
    const file = writeAccount('app-ec.json', { client_email: CLIENT_EMAIL, private_key: pem });
    const c = cfg({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: PROJECT, FCM_SERVICE_ACCOUNT_FILE: file });
    let m = '';
    try {
      buildApp(c);
    } catch (e) {
      m = (e as Error).message;
    }
    expect(m).toBe('FCM_SERVICE_ACCOUNT_FILE: private_key debe ser una llave RSA');
  });

  it('fcm con token_uri no permitido lanza al construir la app', () => {
    const file = writeAccount('app-uri.json', {
      client_email: CLIENT_EMAIL,
      private_key: privatePem,
      token_uri: 'https://evil.example/token',
    });
    const c = cfg({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: PROJECT, FCM_SERVICE_ACCOUNT_FILE: file });
    expect(() => buildApp(c)).toThrow(TOKEN_URI_ERROR);
  });

  it('fcm con cuenta válida arranca', async () => {
    const c = cfg({ PUSH_PROVIDER: 'fcm', FCM_PROJECT_ID: PROJECT, FCM_SERVICE_ACCOUNT_FILE: accountFile });
    const app = buildApp(c);
    await app.close();
  });

  it('none arranca', async () => {
    const app = buildApp(cfg());
    await app.close();
  });

  it('deps.push inyectado tiene prioridad (no se lee la cuenta inválida)', async () => {
    const c = cfg({
      PUSH_PROVIDER: 'fcm',
      FCM_PROJECT_ID: PROJECT,
      FCM_SERVICE_ACCOUNT_FILE: join(dir, 'nada.json'),
    });
    const app = buildApp(c, { push: createRecordingNotifier() });
    await app.close();
  });
});
