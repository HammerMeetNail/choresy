package daynote

import (
	"context"
	"time"
)

// DayNote is a single household diary note for one calendar date.
type DayNote struct {
	Date      string    `json:"date"` // YYYY-MM-DD
	Note      string    `json:"note"`
	UpdatedBy *int64    `json:"updatedBy,omitempty"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// Store persists per-household, per-date diary notes.
type Store interface {
	// ListRange returns the household's notes whose date is in [start, end).
	ListRange(ctx context.Context, householdID int64, start, end time.Time) ([]DayNote, error)
	// Upsert sets the note for a household+date. An empty note deletes the row.
	Upsert(ctx context.Context, householdID int64, date string, note string, updatedBy int64) (DayNote, error)
}
