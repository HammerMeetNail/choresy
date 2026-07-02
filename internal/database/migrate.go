package database

import (
	"context"
	"database/sql"
	"fmt"
	"sort"

	migrationassets "github.com/HammerMeetNail/nabu/migrations"
)

// migrateLockKey is a Postgres session advisory-lock key that serializes
// concurrent migrators. Rolling deploys / multiple replicas all call Migrate at
// boot; without this, two instances racing to INSERT the same schema_migrations
// row would make the loser's transaction fail and crash-loop the pod. Distinct
// from reminder.LeaderLockKey ("nabu_rmd").
const migrateLockKey int64 = 0x6e6162755f6d6772 // "nabu_mgr"

// Migrate applies pending migrations under a session advisory lock so that only
// one instance migrates at a time; the others block until it finishes and then
// see the already-applied migrations and skip them.
func Migrate(ctx context.Context, db *sql.DB) error {
	// A session advisory lock is connection-scoped, so hold it on a single
	// dedicated connection for the duration of the migration run.
	conn, err := db.Conn(ctx)
	if err != nil {
		return fmt.Errorf("acquire migration connection: %w", err)
	}
	defer conn.Close()
	if _, err := conn.ExecContext(ctx, `SELECT pg_advisory_lock($1)`, migrateLockKey); err != nil {
		return fmt.Errorf("acquire migration lock: %w", err)
	}
	defer func() {
		_, _ = conn.ExecContext(context.Background(), `SELECT pg_advisory_unlock($1)`, migrateLockKey)
	}()
	return migrateLocked(ctx, db)
}

// migrateLocked runs the migration loop. The caller must already hold the
// migration advisory lock. The reads of schema_migrations happen after the lock
// is acquired, so a blocked-then-unblocked instance sees the winner's applied
// rows and skips them.
func migrateLocked(ctx context.Context, db *sql.DB) error {
	if _, err := db.ExecContext(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			name TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	applied := map[string]struct{}{}
	rows, err := db.QueryContext(ctx, `SELECT name FROM schema_migrations`)
	if err != nil {
		return fmt.Errorf("query schema_migrations: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return fmt.Errorf("scan schema_migrations: %w", err)
		}
		applied[name] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate schema_migrations: %w", err)
	}

	names, err := migrationassets.Names()
	if err != nil {
		return fmt.Errorf("list migrations: %w", err)
	}
	sort.Strings(names)

	for _, name := range names {
		if _, ok := applied[name]; ok {
			continue
		}
		body, err := migrationassets.Assets.ReadFile(name)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}

		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("begin migration %s: %w", name, err)
		}
		if _, err := tx.ExecContext(ctx, string(body)); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("apply migration %s: %w", name, err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations(name) VALUES ($1)`, name); err != nil {
			_ = tx.Rollback()
			return fmt.Errorf("record migration %s: %w", name, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("commit migration %s: %w", name, err)
		}
	}

	return nil
}
