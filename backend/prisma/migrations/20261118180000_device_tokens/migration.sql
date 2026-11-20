-- BE-04 paso 9 (D42): token push del dispositivo del guardia.
-- El CHECK se agrega a mano (Prisma no lo expresa), igual que en la migración init.

CREATE TABLE "device_tokens" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "token" TEXT NOT NULL,
    "family_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_tokens_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "device_tokens_token_key" ON "device_tokens"("token");
CREATE INDEX "device_tokens_user_id_idx" ON "device_tokens"("user_id");
CREATE INDEX "device_tokens_family_id_idx" ON "device_tokens"("family_id");

ALTER TABLE "device_tokens" ADD CONSTRAINT "device_tokens_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "device_tokens" ADD CONSTRAINT "device_tokens_token_len_chk"
  CHECK (char_length("token") BETWEEN 1 AND 512);
