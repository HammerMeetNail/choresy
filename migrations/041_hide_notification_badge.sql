ALTER TABLE user_preferences
  ADD COLUMN IF NOT EXISTS hide_notification_badge BOOLEAN NOT NULL DEFAULT FALSE;
