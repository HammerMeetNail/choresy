-- User-defined stats widgets (Phase 4). A widget is a typed, validated JSON
-- document (no formulas / user code) stored per-user. Rendering maps onto the
-- existing stats endpoints, so there is no new query surface. Size is capped by
-- the application layer (max widgets + byte cap).
ALTER TABLE user_preferences
  ADD COLUMN IF NOT EXISTS stats_widgets JSONB NOT NULL DEFAULT '[]';
