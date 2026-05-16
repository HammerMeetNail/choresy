-- Add slot_hour to track which calendar hour slot a log was recorded from.
-- NULL means it was logged without a specific time slot (shows in "Anytime").
-- 0-23 means it was logged from that hour's slot in the day view.
ALTER TABLE chore_logs
  ADD COLUMN IF NOT EXISTS slot_hour INT;
