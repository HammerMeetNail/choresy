-- Generalized per-chore metrics (Phase 3). Replaces the implicit
-- has_volume_ml / has_rating flags with an explicit metric configuration:
--   metric_type: 'none' | 'amount' | 'rating' | 'duration'
--   metric_unit: display unit label for 'amount' metrics (e.g. 'mL', 'oz', 'g', 'min')
--
-- The old boolean columns are retained and kept in sync by the application
-- layer (chore store writes) so existing stats/log code that still reads them
-- keeps working. metric_type/metric_unit are the source of truth going forward.
ALTER TABLE chores ADD COLUMN IF NOT EXISTS metric_type TEXT NOT NULL DEFAULT 'none';
ALTER TABLE chores ADD COLUMN IF NOT EXISTS metric_unit TEXT NOT NULL DEFAULT '';

-- Migrate existing flags 1:1.
UPDATE chores SET metric_type = 'amount', metric_unit = 'mL'
  WHERE has_volume_ml = TRUE AND metric_type = 'none';
UPDATE chores SET metric_type = 'rating'
  WHERE has_rating = TRUE AND metric_type = 'none';

-- Duration metric value store (whole seconds). Used by duration-metric chores
-- and the duration timer (Phase 5.2). NULL means "no duration recorded".
ALTER TABLE chore_logs ADD COLUMN IF NOT EXISTS duration_seconds INTEGER;
