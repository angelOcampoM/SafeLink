import multipart from '@fastify/multipart';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { PrismaClient } from '../../db/prisma.js';
import { AppError, invalidInput, notFound } from '../../errors/app-error.js';
import { ok } from '../../http/envelope.js';
import { parse, parseIdParam, userMsg } from '../../http/validate.js';
import { detectPhotoMime, type PhotoStorage } from '../../storage/photo-storage.js';
import type { PhotoUrlSigner } from '../../storage/photo-urls.js';
import { createAlertBodySchema, locationBodySchema, type CreateAlertBody } from './schemas.js';
import type { AlertsService } from './service.js';

export interface AlertsRoutesOptions {
  prisma: PrismaClient;
  /** Lo arma app.ts: es el mismo servicio que lee el canal alerts/active. */
  service: AlertsService;
  photos: PhotoStorage;
  photoUrls: PhotoUrlSigner;
}

/** El campo `data` del multipart lleva el mismo JSON que POST /alerts: es pequeño. */
const DATA_FIELD_MAX_BYTES = 8 * 1024;

const MSG_PHOTO_TOO_LARGE = 'La foto es demasiado grande';
const MSG_PHOTO_INVALID = 'La foto no es una imagen válida';
const MSG_MULTIPART_INVALID = 'Los datos de la alerta no son válidos';

/** Clave del rate limit: el usuario ya autenticado (por eso el límite corre en preHandler). */
const porUsuario = (request: FastifyRequest): string => request.user?.id ?? request.ip;

const photoQuerySchema = z
  .object({
    exp: z.string().regex(/^\d{1,12}$/, userMsg('El enlace de la foto no es válido')),
    sig: z.string().max(128, userMsg('El enlace de la foto no es válido')),
  })
  .strict();

/**
 * Alertas del usuario protegido (BE-03). El acceso lo decide la política central
 * (src/security/policies.ts): son del rol protected_user y sobre sus propias alertas,
 * salvo GET /alerts/:id/photo, que se autoriza con la firma de la URL (D2).
 */
export async function alertsRoutes(app: FastifyInstance, options: AlertsRoutesOptions): Promise<void> {
  const { config } = app;
  const { service, photos, photoUrls } = options;

  // Solo dentro de este plugin: POST /alerts acepta además multipart/form-data con la foto.
  await app.register(multipart, {
    limits: {
      fileSize: config.PHOTO_MAX_BYTES,
      files: 1,
      fields: 1,
      fieldSize: DATA_FIELD_MAX_BYTES,
      parts: 2,
      headerPairs: 20,
    },
  });

  /**
   * U-06 · D2: multipart con el campo `data` (el mismo JSON de POST /alerts) y, opcional,
   * el archivo `photo`. La foto se valida por su firma de bytes, nunca por su Content-Type.
   */
  async function leerMultipart(request: FastifyRequest): Promise<{ body: CreateAlertBody; photo: Buffer | null }> {
    let data: unknown;
    let photo: Buffer | null = null;
    try {
      for await (const part of request.parts()) {
        if (part.type === 'file') {
          if (part.fieldname !== 'photo' || photo !== null) throw invalidInput(MSG_MULTIPART_INVALID);
          photo = await part.toBuffer();
        } else if (part.fieldname === 'data' && typeof part.value === 'string') {
          data = JSON.parse(part.value);
        } else {
          throw invalidInput(MSG_MULTIPART_INVALID);
        }
      }
    } catch (error) {
      if (error instanceof AppError) throw error;
      const code = (error as { code?: unknown }).code;
      if (code === 'FST_REQ_FILE_TOO_LARGE') throw invalidInput(MSG_PHOTO_TOO_LARGE);
      throw invalidInput(MSG_MULTIPART_INVALID);
    }
    if (data === undefined) throw invalidInput(MSG_MULTIPART_INVALID);
    const body = parse(createAlertBodySchema, data);
    if (photo !== null && (photo.length === 0 || detectPhotoMime(photo) === null)) {
      throw invalidInput(MSG_PHOTO_INVALID);
    }
    return { body, photo };
  }

  const createLimit = {
    max: config.RATE_LIMIT_ALERTS_PER_MINUTE,
    timeWindow: 60_000,
    hook: 'preHandler' as const,
    keyGenerator: porUsuario,
  };
  const locationLimit = {
    max: config.RATE_LIMIT_LOCATIONS_PER_WINDOW,
    timeWindow: config.LOCATION_UPDATE_SECONDS * 1000,
    hook: 'preHandler' as const,
    keyGenerator: porUsuario,
  };

  // U-03 · U-04 · U-05 · U-06
  app.post('/alerts', { config: { rateLimit: createLimit } }, async (request, reply) => {
    let body: CreateAlertBody;
    let photo: Buffer | null = null;
    if (request.isMultipart()) {
      ({ body, photo } = await leerMultipart(request));
    } else {
      // JSON (lo que manda hoy nube_alerta_usuario_repository.dart): photoPath es una ruta
      // del teléfono y no se puede usar; la alerta queda con evidencia incompleta.
      body = parse(createAlertBodySchema, request.body);
    }

    const photoKey = photo ? await photos.save(photo) : null;
    try {
      const creada = await service.create(request.user.id, body, photoKey);
      void reply.code(201); // D22: los POST que crean recurso responden 201
      return ok(creada);
    } catch (error) {
      // Si la alerta no se crea (bloqueo, otra activa...), la foto no queda huérfana.
      if (photoKey) await photos.remove(photoKey);
      throw error;
    }
  });

  // Historial del usuario (extra del front)
  app.get('/alerts/mine', async (request) => ok(await service.mine(request.user.id)));

  // U-07
  app.post('/alerts/:id/locations', { config: { rateLimit: locationLimit } }, async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    const body = parse(locationBodySchema, request.body);
    return ok(await service.addLocation(request.user.id, id, body.location));
  });

  // U-09
  app.post('/alerts/:id/confirm', async (request) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    return ok(await service.confirm(request.user.id, id));
  });

  // D2: la foto, con la URL firmada que emitió el servidor. Cualquier fallo es 404
  // (no se distingue firma vencida de alerta inexistente: no se revela nada).
  app.get('/alerts/:id/photo', async (request, reply) => {
    const id = parseIdParam((request.params as { id?: unknown }).id);
    const query = photoQuerySchema.safeParse(request.query);
    if (!query.success) throw notFound();
    const alert = await options.prisma.alert.findUnique({ where: { id }, select: { photoKey: true } });
    if (!alert?.photoKey || !photoUrls.verify(id, alert.photoKey, Number(query.data.exp), query.data.sig)) {
      throw notFound();
    }
    const foto = await photos.read(alert.photoKey);
    if (!foto) throw notFound();
    void reply
      .header('content-type', foto.mime)
      .header('x-content-type-options', 'nosniff')
      .header('content-disposition', 'inline');
    return reply.send(foto.bytes);
  });
}
