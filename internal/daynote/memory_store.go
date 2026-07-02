package daynote

import (
	"context"
	"sort"
	"sync"
	"time"
)

type memoryStore struct {
	mu   sync.RWMutex
	data map[int64]map[string]DayNote // householdID -> date -> note
}

// NewMemoryStore returns an in-memory Store for tests and the no-database mode.
func NewMemoryStore() Store {
	return &memoryStore{data: map[int64]map[string]DayNote{}}
}

func (s *memoryStore) ListRange(_ context.Context, householdID int64, start, end time.Time) ([]DayNote, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	startStr := start.Format("2006-01-02")
	endStr := end.Format("2006-01-02")
	var out []DayNote
	for date, n := range s.data[householdID] {
		if date >= startStr && date < endStr {
			out = append(out, n)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date > out[j].Date })
	return out, nil
}

func (s *memoryStore) Upsert(_ context.Context, householdID int64, date, note string, updatedBy int64) (DayNote, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.data[householdID] == nil {
		s.data[householdID] = map[string]DayNote{}
	}
	if note == "" {
		delete(s.data[householdID], date)
		return DayNote{Date: date, Note: ""}, nil
	}
	uid := updatedBy
	n := DayNote{Date: date, Note: note, UpdatedBy: &uid, UpdatedAt: time.Now().UTC()}
	s.data[householdID][date] = n
	return n, nil
}
