// Package apns delivers native iOS push notifications through Apple's APNs
// HTTP/2 API and manages the device tokens the app registers.
package apns

import (
	"context"
	"database/sql"
	"sync"
)

const (
	EnvironmentSandbox    = "sandbox"
	EnvironmentProduction = "production"
)

type Device struct {
	UserID      int64
	Token       string
	Environment string // "sandbox" | "production"
	BundleID    string
	DeviceName  string
}

type Store interface {
	// RegisterDevice upserts by token: a device token is unique to a physical
	// device, so registration by a different user takes the token over.
	RegisterDevice(ctx context.Context, d Device) error
	// UnregisterDevice removes the token if it belongs to userID.
	UnregisterDevice(ctx context.Context, userID int64, token string) error
	DevicesForUser(ctx context.Context, userID int64) ([]Device, error)
	// DeleteToken removes a token regardless of owner — used when APNs
	// reports it terminally invalid (Unregistered / BadDeviceToken).
	DeleteToken(ctx context.Context, token string) error
}

// MemoryStore backs tests and the zero-DB development mode. The sender reads
// devices from scheduler goroutines while HTTP handlers write them, so all
// access is mutex-guarded.
type MemoryStore struct {
	mu      sync.Mutex
	byToken map[string]Device
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{byToken: map[string]Device{}}
}

func (s *MemoryStore) RegisterDevice(_ context.Context, d Device) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.byToken[d.Token] = d
	return nil
}

func (s *MemoryStore) UnregisterDevice(_ context.Context, userID int64, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if d, ok := s.byToken[token]; ok && d.UserID == userID {
		delete(s.byToken, token)
	}
	return nil
}

func (s *MemoryStore) DevicesForUser(_ context.Context, userID int64) ([]Device, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []Device
	for _, d := range s.byToken {
		if d.UserID == userID {
			out = append(out, d)
		}
	}
	return out, nil
}

func (s *MemoryStore) DeleteToken(_ context.Context, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.byToken, token)
	return nil
}

type PostgresStore struct {
	db *sql.DB
}

func NewPostgresStore(db *sql.DB) *PostgresStore {
	return &PostgresStore{db: db}
}

func (s *PostgresStore) RegisterDevice(ctx context.Context, d Device) error {
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO mobile_device_tokens (user_id, token, environment, bundle_id, device_name, created_at, last_seen_at)
		VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
		ON CONFLICT (token) DO UPDATE
		SET user_id = EXCLUDED.user_id,
		    environment = EXCLUDED.environment,
		    bundle_id = EXCLUDED.bundle_id,
		    device_name = EXCLUDED.device_name,
		    last_seen_at = NOW()
	`, d.UserID, d.Token, d.Environment, d.BundleID, d.DeviceName)
	return err
}

func (s *PostgresStore) UnregisterDevice(ctx context.Context, userID int64, token string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM mobile_device_tokens WHERE user_id = $1 AND token = $2`, userID, token)
	return err
}

func (s *PostgresStore) DevicesForUser(ctx context.Context, userID int64) ([]Device, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT user_id, token, environment, bundle_id, device_name
		FROM mobile_device_tokens WHERE user_id = $1
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Device
	for rows.Next() {
		var d Device
		if err := rows.Scan(&d.UserID, &d.Token, &d.Environment, &d.BundleID, &d.DeviceName); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

func (s *PostgresStore) DeleteToken(ctx context.Context, token string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM mobile_device_tokens WHERE token = $1`, token)
	return err
}
