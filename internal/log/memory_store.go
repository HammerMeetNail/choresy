package log

import (
	"context"
	"sync"
	"time"
)

type MemoryStore struct {
	mu    sync.RWMutex
	idSeq int64
	logs  map[int64]ChoreLog
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{logs: map[int64]ChoreLog{}}
}

func (s *MemoryStore) nextID() int64 {
	s.idSeq++
	return s.idSeq
}

func (s *MemoryStore) CreateLog(_ context.Context, log ChoreLog) (ChoreLog, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	log.ID = s.nextID()
	log.CreatedAt = time.Now().UTC()
	s.logs[log.ID] = log
	return log, nil
}

func (s *MemoryStore) GetLog(_ context.Context, id int64) (ChoreLog, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	l, ok := s.logs[id]
	if !ok {
		return ChoreLog{}, ErrNotFound
	}
	return l, nil
}

func (s *MemoryStore) DeleteLog(_ context.Context, id int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.logs, id)
	return nil
}

func (s *MemoryStore) FindLog(_ context.Context, householdID, choreID int64, date time.Time) (*ChoreLog, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, l := range s.logs {
		if l.HouseholdID == householdID && l.ChoreID == choreID {
			y1, m1, d1 := l.CompletedAt.UTC().Date()
			y2, m2, d2 := date.UTC().Date()
			if y1 == y2 && m1 == m2 && d1 == d2 {
				return &l, nil
			}
		}
	}
	return nil, ErrNotFound
}

func (s *MemoryStore) ListLogs(_ context.Context, householdID int64, date time.Time) ([]ChoreLog, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var result []ChoreLog
	for _, l := range s.logs {
		if l.HouseholdID == householdID {
			y1, m1, d1 := l.CompletedAt.UTC().Date()
			y2, m2, d2 := date.UTC().Date()
			if y1 == y2 && m1 == m2 && d1 == d2 {
				result = append(result, l)
			}
		}
	}
	return result, nil
}

func (s *MemoryStore) ListLogsRange(_ context.Context, householdID int64, start, end time.Time) ([]ChoreLog, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var result []ChoreLog
	for _, l := range s.logs {
		if l.HouseholdID == householdID && !l.CompletedAt.Before(start) && l.CompletedAt.Before(end) {
			result = append(result, l)
		}
	}
	return result, nil
}
