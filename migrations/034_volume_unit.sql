ALTER TABLE user_preferences
  ADD COLUMN IF NOT EXISTS volume_unit TEXT NOT NULL DEFAULT 'ml';
