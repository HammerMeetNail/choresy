-- Add indicator_labels to chores: JSON-encoded []string of boolean label names
-- e.g. '["Left","Right"]' — the user defines which labels each chore tracks.
ALTER TABLE chores
  ADD COLUMN IF NOT EXISTS indicator_labels TEXT NOT NULL DEFAULT '[]';

-- Add indicators to chore_logs: JSON-encoded []string of which labels were
-- marked when this log entry was recorded.
ALTER TABLE chore_logs
  ADD COLUMN IF NOT EXISTS indicators TEXT NOT NULL DEFAULT '[]';
