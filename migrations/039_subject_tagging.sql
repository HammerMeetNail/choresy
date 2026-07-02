-- Multi-subject tagging (Phase 5.5). A chore may declare an optional set of
-- subjects (e.g. twin names) and each log may be tagged with one of them, so a
-- single "Feed Baby" chore can distinguish which baby a log is about.
ALTER TABLE chores ADD COLUMN IF NOT EXISTS subjects JSONB NOT NULL DEFAULT '[]';
ALTER TABLE chore_logs ADD COLUMN IF NOT EXISTS subject TEXT;
