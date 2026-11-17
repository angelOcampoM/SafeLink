// BE-03 · Foto de evidencia (D2): tipo por firma de bytes, guardado en disco y URL firmada.
// Unitaria: usa una carpeta temporal, no la base.
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config/env.js';
import { createDiskPhotoStorage, detectPhotoMime, isPhotoKey } from '../../src/storage/photo-storage.js';
import { createPhotoUrlSigner } from '../../src/storage/photo-urls.js';

export const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0x24, 0, 0, 0]), Buffer.from('WEBPVP8 ')]);

describe('detectPhotoMime', () => {
  it('reconoce JPEG, PNG y WebP por sus primeros bytes', () => {
    expect(detectPhotoMime(JPEG)).toBe('image/jpeg');
    expect(detectPhotoMime(PNG)).toBe('image/png');
    expect(detectPhotoMime(WEBP)).toBe('image/webp');
  });

  it('rechaza lo que no es imagen aunque diga serlo', () => {
    expect(detectPhotoMime(Buffer.from('<html><script>alert(1)</script>'))).toBeNull();
    expect(detectPhotoMime(Buffer.from('%PDF-1.7'))).toBeNull();
    expect(detectPhotoMime(Buffer.alloc(0))).toBeNull();
    expect(detectPhotoMime(Buffer.from([0xff, 0xd8]))).toBeNull();
  });
});

describe('createDiskPhotoStorage', () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'safelink-fotos-'));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('guarda con una llave UUID del servidor y la lee con su tipo', async () => {
    const fotos = createDiskPhotoStorage(dir);
    const key = await fotos.save(JPEG);
    expect(isPhotoKey(key)).toBe(true);
    expect(await readdir(dir)).toEqual([key]);
    expect(await fotos.read(key)).toEqual({ bytes: JPEG, mime: 'image/jpeg' });
  });

  it('no guarda lo que no es una imagen admitida', async () => {
    const fotos = createDiskPhotoStorage(dir);
    await expect(fotos.save(Buffer.from('no soy foto'))).rejects.toThrow();
    expect(await readdir(dir)).toEqual([]);
  });

  it('una llave que no es UUID nunca se convierte en ruta', async () => {
    const fotos = createDiskPhotoStorage(dir);
    expect(await fotos.read('../../.env')).toBeNull();
    expect(await fotos.read('11111111-1111-4111-8111-111111111111')).toBeNull();
    await expect(fotos.remove('../../.env')).resolves.toBeUndefined();
  });

  it('borra la foto y borrar dos veces no falla', async () => {
    const fotos = createDiskPhotoStorage(dir);
    const key = await fotos.save(PNG);
    await fotos.remove(key);
    await fotos.remove(key);
    expect(await fotos.read(key)).toBeNull();
  });
});

describe('createPhotoUrlSigner', () => {
  const ALERTA = '11111111-1111-4111-8111-111111111111';
  const LLAVE = '22222222-2222-4222-8222-222222222222';
  let ahora = new Date('2026-11-16T18:00:00Z');
  const firmador = createPhotoUrlSigner({
    secret: 'secreto-solo-para-pruebas-minimo-32-caracteres',
    publicApiUrl: 'http://192.168.1.10:3000/api/v1/',
    ttlSeconds: 900,
    now: () => ahora,
  });

  function partes(url: string) {
    const u = new URL(url);
    return { path: u.pathname, exp: Number(u.searchParams.get('exp')), sig: u.searchParams.get('sig') ?? '' };
  }

  it('arma una URL absoluta de la API, sin el token de acceso', () => {
    const url = firmador.url(ALERTA, LLAVE);
    expect(url.startsWith(`http://192.168.1.10:3000/api/v1/alerts/${ALERTA}/photo?`)).toBe(true);
    expect(url).not.toContain('Bearer');
    expect(url).not.toContain(LLAVE);
  });

  it('la firma vale para esa alerta y esa foto mientras no caduque', () => {
    const { exp, sig } = partes(firmador.url(ALERTA, LLAVE));
    expect(firmador.verify(ALERTA, LLAVE, exp, sig)).toBe(true);
    expect(firmador.verify('33333333-3333-4333-8333-333333333333', LLAVE, exp, sig)).toBe(false);
    expect(firmador.verify(ALERTA, '44444444-4444-4444-8444-444444444444', exp, sig)).toBe(false);
    expect(firmador.verify(ALERTA, LLAVE, exp + 1, sig)).toBe(false);
    expect(firmador.verify(ALERTA, LLAVE, exp, sig.replace(/.$/, (c) => (c === '0' ? '1' : '0')))).toBe(false);
    expect(firmador.verify(ALERTA, LLAVE, exp, 'basura')).toBe(false);
  });

  it('caduca a los PHOTO_URL_TTL_SECONDS', () => {
    const { exp, sig } = partes(firmador.url(ALERTA, LLAVE));
    ahora = new Date(ahora.getTime() + 901_000);
    expect(firmador.verify(ALERTA, LLAVE, exp, sig)).toBe(false);
  });
});

describe('configuración de la foto', () => {
  const base = { JWT_SECRET: 'x'.repeat(32) };

  it('tiene valores por defecto seguros', () => {
    const c = loadConfig(base);
    expect(c.PHOTO_DIR).toBe('storage/fotos');
    expect(c.PHOTO_MAX_BYTES).toBe(5 * 1024 * 1024);
    expect(c.PHOTO_URL_TTL_SECONDS).toBe(900);
    expect(c.PUBLIC_API_URL).toBeUndefined();
  });

  it('acota el tamaño máximo y exige una URL http(s) válida', () => {
    expect(() => loadConfig({ ...base, PHOTO_MAX_BYTES: String(16 * 1024 * 1024) })).toThrow();
    expect(() => loadConfig({ ...base, PUBLIC_API_URL: 'ftp://x' })).toThrow();
    expect(loadConfig({ ...base, PUBLIC_API_URL: 'http://192.168.1.10:3000/api/v1' }).PUBLIC_API_URL).toBe(
      'http://192.168.1.10:3000/api/v1',
    );
  });
});
