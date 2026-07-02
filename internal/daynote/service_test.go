package daynote_test

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/HammerMeetNail/nabu/internal/daynote"
)

func TestDayNoteService(t *testing.T) {
	ctx := context.Background()
	svc := daynote.NewService(daynote.NewMemoryStore())

	t.Run("set and list", func(t *testing.T) {
		if _, err := svc.SetNote(ctx, 1, "2026-07-01", "first solid food!", 9); err != nil {
			t.Fatalf("SetNote: %v", err)
		}
		start := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
		end := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
		notes, err := svc.ListRange(ctx, 1, start, end)
		if err != nil {
			t.Fatalf("ListRange: %v", err)
		}
		if len(notes) != 1 || notes[0].Note != "first solid food!" {
			t.Fatalf("notes = %+v", notes)
		}
	})

	t.Run("empty note clears the entry", func(t *testing.T) {
		if _, err := svc.SetNote(ctx, 1, "2026-07-01", "   ", 9); err != nil {
			t.Fatalf("SetNote clear: %v", err)
		}
		notes, _ := svc.ListRange(ctx, 1, time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC), time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC))
		if len(notes) != 0 {
			t.Fatalf("expected note cleared, got %+v", notes)
		}
	})

	t.Run("rejects bad date and overlong note", func(t *testing.T) {
		if _, err := svc.SetNote(ctx, 1, "not-a-date", "x", 9); err == nil {
			t.Fatalf("expected date rejection")
		}
		if _, err := svc.SetNote(ctx, 1, "2026-07-01", strings.Repeat("x", daynote.MaxNoteRunes+1), 9); err == nil {
			t.Fatalf("expected length rejection")
		}
	})

	t.Run("scoped by household", func(t *testing.T) {
		_, _ = svc.SetNote(ctx, 2, "2026-07-02", "house 2 note", 5)
		notes, _ := svc.ListRange(ctx, 1, time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC), time.Date(2026, 7, 10, 0, 0, 0, 0, time.UTC))
		for _, n := range notes {
			if n.Note == "house 2 note" {
				t.Fatalf("household 1 leaked household 2's note")
			}
		}
	})
}
