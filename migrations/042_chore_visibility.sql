-- All existing chores remain shared by default.
ALTER TABLE chores
    ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'household'
    CHECK (visibility IN ('household', 'admins'));

-- Supports the normal visible-task list ordered by sort_order.
CREATE INDEX IF NOT EXISTS idx_chores_household_visibility_sort
    ON chores (household_id, visibility, sort_order);
