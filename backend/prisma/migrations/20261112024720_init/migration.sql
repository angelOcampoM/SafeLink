-- CreateEnum
CREATE TYPE "user_role" AS ENUM ('protected_user', 'guard', 'admin');

-- CreateEnum
CREATE TYPE "alert_status" AS ENUM ('pending_location', 'searching', 'in_progress', 'guard_arrived', 'closed', 'no_response', 'escalated', 'resolved_by_admin');

-- CreateEnum
CREATE TYPE "trigger_method" AS ENUM ('tap', 'hold', 'shake');

-- CreateEnum
CREATE TYPE "escalation_reason" AS ENUM ('no_response', 'no_confirmation');

-- CreateEnum
CREATE TYPE "alert_resolution" AS ENUM ('resolved', 'false_alarm', 'service_incident');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "role" "user_role" NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "volume_double_click_enabled" BOOLEAN NOT NULL DEFAULT false,
    "false_alarm_count" INTEGER NOT NULL DEFAULT 0,
    "blocked_until" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guard_profiles" (
    "user_id" UUID NOT NULL,
    "shift_start" CHAR(5) NOT NULL,
    "shift_end" CHAR(5) NOT NULL,
    "coverage_center_lat" DOUBLE PRECISION,
    "coverage_center_lng" DOUBLE PRECISION,
    "coverage_radius_meters" INTEGER,
    "zone" TEXT,
    "last_location_lat" DOUBLE PRECISION,
    "last_location_lng" DOUBLE PRECISION,
    "last_location_at" TIMESTAMPTZ(3),

    CONSTRAINT "guard_profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "alerts" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "guard_id" UUID,
    "status" "alert_status" NOT NULL,
    "trigger_method" "trigger_method" NOT NULL,
    "photo_key" TEXT,
    "evidence_incomplete" BOOLEAN NOT NULL DEFAULT false,
    "lat" DOUBLE PRECISION,
    "lng" DOUBLE PRECISION,
    "heading" INTEGER,
    "triggered_at" TIMESTAMPTZ(3) NOT NULL,
    "received_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status_changed_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "accepted_at" TIMESTAMPTZ(3),
    "arrived_at" TIMESTAMPTZ(3),
    "closed_at" TIMESTAMPTZ(3),
    "escalation_reason" "escalation_reason",
    "resolution" "alert_resolution",
    "admin_note" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "alerts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "alert_ignores" (
    "guard_id" UUID NOT NULL,
    "alert_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "alert_ignores_pkey" PRIMARY KEY ("guard_id","alert_id")
);

-- CreateTable
CREATE TABLE "alert_status_history" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "alert_id" UUID NOT NULL,
    "from_status" "alert_status",
    "to_status" "alert_status" NOT NULL,
    "actor_id" UUID,
    "at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "alert_status_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "family_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" CHAR(64) NOT NULL,
    "parent_id" UUID,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "used_at" TIMESTAMPTZ(3),
    "revoked_at" TIMESTAMPTZ(3),
    "replaced_by_id" UUID,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "alerts_status_idx" ON "alerts"("status");

-- CreateIndex
CREATE INDEX "alerts_guard_id_idx" ON "alerts"("guard_id");

-- CreateIndex
CREATE INDEX "alerts_user_id_idx" ON "alerts"("user_id");

-- CreateIndex
CREATE INDEX "alerts_received_at_idx" ON "alerts"("received_at");

-- CreateIndex
CREATE INDEX "alert_status_history_alert_id_at_idx" ON "alert_status_history"("alert_id", "at");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_family_id_idx" ON "refresh_tokens"("family_id");

-- AddForeignKey
ALTER TABLE "guard_profiles" ADD CONSTRAINT "guard_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_guard_id_fkey" FOREIGN KEY ("guard_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alert_ignores" ADD CONSTRAINT "alert_ignores_guard_id_fkey" FOREIGN KEY ("guard_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alert_ignores" ADD CONSTRAINT "alert_ignores_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "alerts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alert_status_history" ADD CONSTRAINT "alert_status_history_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "alerts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "alert_status_history" ADD CONSTRAINT "alert_status_history_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "refresh_tokens"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_replaced_by_id_fkey" FOREIGN KEY ("replaced_by_id") REFERENCES "refresh_tokens"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- ============================================================================
-- Restricciones que Prisma no puede expresar en schema.prisma (editadas a mano).
-- Los rangos que vienen de configuración (radio de cobertura, largo de la nota
-- del admin) se validan en la aplicación; aquí solo hay cotas de cordura.
-- ============================================================================

-- D18: el correo siempre en minúsculas.
ALTER TABLE "users" ADD CONSTRAINT "users_email_lowercase_chk" CHECK ("email" = lower("email"));
ALTER TABLE "users" ADD CONSTRAINT "users_false_alarm_count_chk" CHECK ("false_alarm_count" >= 0);

-- D1: turno "HH:mm" (00:00 a 23:59). Puede cruzar medianoche; inicio = fin es 24 h.
ALTER TABLE "guard_profiles" ADD CONSTRAINT "guard_profiles_shift_format_chk"
  CHECK ("shift_start" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND "shift_end" ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
ALTER TABLE "guard_profiles" ADD CONSTRAINT "guard_profiles_coverage_chk"
  CHECK (
    ("coverage_center_lat" IS NULL OR "coverage_center_lat" BETWEEN -90 AND 90)
    AND ("coverage_center_lng" IS NULL OR "coverage_center_lng" BETWEEN -180 AND 180)
    AND ("coverage_radius_meters" IS NULL OR "coverage_radius_meters" > 0)
    AND ("last_location_lat" IS NULL OR "last_location_lat" BETWEEN -90 AND 90)
    AND ("last_location_lng" IS NULL OR "last_location_lng" BETWEEN -180 AND 180)
  );

-- D17: coordenadas válidas; rumbo entero 0-359; nota con tope holgado
-- (el límite real, ADMIN_NOTE_MAX_LENGTH, se valida en la aplicación).
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_lat_chk" CHECK ("lat" IS NULL OR "lat" BETWEEN -90 AND 90);
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_lng_chk" CHECK ("lng" IS NULL OR "lng" BETWEEN -180 AND 180);
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_heading_chk" CHECK ("heading" IS NULL OR "heading" BETWEEN 0 AND 359);
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_admin_note_len_chk" CHECK ("admin_note" IS NULL OR char_length("admin_note") <= 1000);

-- D15: una sola alerta activa por usuario (índice único PARCIAL).
CREATE UNIQUE INDEX "alerts_one_active_per_user_idx" ON "alerts"("user_id")
  WHERE "status" IN ('pending_location', 'searching', 'in_progress', 'guard_arrived');
