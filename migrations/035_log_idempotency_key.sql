-- Client-generated idempotency key for offline log replay. Unique per
-- household when present so a replayed POST /api/logs cannot create a
-- duplicate. NULL means "no key" (the common online path).
ALTER TABLE chore_logs
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS chore_logs_household_idempotency_key
  ON chore_logs (household_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;
