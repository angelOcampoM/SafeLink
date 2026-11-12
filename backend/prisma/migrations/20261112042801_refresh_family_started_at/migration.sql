-- AlterTable
ALTER TABLE "refresh_tokens" ADD COLUMN     "family_started_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Las sesiones existentes toman como inicio el created_at de su token más antiguo.
UPDATE "refresh_tokens" AS r
SET "family_started_at" = f.started
FROM (
  SELECT "family_id", MIN("created_at") AS started
  FROM "refresh_tokens"
  GROUP BY "family_id"
) AS f
WHERE r."family_id" = f."family_id";
