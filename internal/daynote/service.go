package daynote

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"
)

// MaxNoteRunes caps a diary note's length.
const MaxNoteRunes = 500

// Service holds the business logic for day notes.
type Service struct {
	store Store
}

// NewService constructs a Service.
func NewService(store Store) *Service {
	return &Service{store: store}
}

// ListRange returns the household's notes with date in [start, end).
func (s *Service) ListRange(ctx context.Context, householdID int64, start, end time.Time) ([]DayNote, error) {
	return s.store.ListRange(ctx, householdID, start, end)
}

// SetNote validates and upserts a diary note. An empty (or whitespace-only)
// note clears the entry for that date.
func (s *Service) SetNote(ctx context.Context, householdID int64, date, note string, userID int64) (DayNote, error) {
	if _, err := time.Parse("2006-01-02", date); err != nil {
		return DayNote{}, fmt.Errorf("invalid date, expected YYYY-MM-DD")
	}
	note = strings.TrimSpace(note)
	if strings.ContainsAny(note, "\x00") {
		return DayNote{}, fmt.Errorf("note contains invalid characters")
	}
	if utf8.RuneCountInString(note) > MaxNoteRunes {
		return DayNote{}, fmt.Errorf("note must be %d characters or fewer", MaxNoteRunes)
	}
	return s.store.Upsert(ctx, householdID, date, note, userID)
}
