-- Per-day household diary notes (Phase 5.4). One optional free-text note per
-- household per calendar date, shared across members and rendered on the
-- Activity day headers.
CREATE TABLE IF NOT EXISTS day_notes (
    household_id BIGINT NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    note_date    DATE   NOT NULL,
    note         TEXT   NOT NULL DEFAULT '',
    updated_by   BIGINT,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (household_id, note_date)
);
