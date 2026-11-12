-- Restricciones adicionales (defensa en profundidad) que Prisma no expresa en el esquema.

-- Hash SHA-256 en hexadecimal minúsculas.
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_token_hash_format_chk"
  CHECK ("token_hash" ~ '^[0-9a-f]{64}$');

-- Coherencia de la alerta.
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_guard_not_user_chk"
  CHECK ("guard_id" IS NULL OR "guard_id" <> "user_id");
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_guard_required_chk"
  CHECK ("status" NOT IN ('in_progress', 'guard_arrived', 'closed') OR "guard_id" IS NOT NULL);
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_closed_at_required_chk"
  CHECK ("status" NOT IN ('closed', 'resolved_by_admin') OR "closed_at" IS NOT NULL);

-- La clave de la foto es un UUID (nunca una ruta).
ALTER TABLE "alerts" ADD CONSTRAINT "alerts_photo_key_format_chk"
  CHECK ("photo_key" IS NULL OR "photo_key" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

-- Topes de cordura en texto libre.
ALTER TABLE "users" ADD CONSTRAINT "users_name_len_chk" CHECK (char_length("name") <= 200);
ALTER TABLE "users" ADD CONSTRAINT "users_email_len_chk" CHECK (char_length("email") <= 254);
ALTER TABLE "users" ADD CONSTRAINT "users_phone_len_chk" CHECK (char_length("phone") <= 30);
ALTER TABLE "guard_profiles" ADD CONSTRAINT "guard_profiles_zone_len_chk"
  CHECK ("zone" IS NULL OR char_length("zone") <= 100);
