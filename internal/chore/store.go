package chore

import (
	"context"
	"time"
)

type Chore struct {
	ID                  int64     `json:"id"`
	HouseholdID         int64     `json:"householdId"`
	Name                string    `json:"name"`
	Icon                string    `json:"icon"`
	Color               string    `json:"color"`
	SortOrder           int       `json:"sortOrder"`
	Category            string    `json:"category"`
	IsPredefined        bool      `json:"isPredefined"`
	PredefinedKey       string    `json:"predefinedKey"`
	CreatedBy           *int64    `json:"createdBy"`
	CreatedAt           time.Time `json:"createdAt"`
	IndicatorLabels     []string  `json:"indicatorLabels"`
	IndicatorDefaults   []string  `json:"indicatorDefaults"`
	HasVolumeML         bool      `json:"hasVolumeML"`
	FollowUpEnabled     bool      `json:"followUpEnabled"`
	LastFollowUpMinutes int       `json:"lastFollowUpMinutes"`
	HasRating           bool      `json:"hasRating"`
	// MetricType is the explicit per-chore metric configuration (Phase 3):
	// "none" | "amount" | "rating" | "duration". It generalizes the older
	// HasVolumeML/HasRating booleans, which are kept in sync (see SyncMetricFlags)
	// for backward compatibility with the stats/log layers.
	MetricType string `json:"metricType"`
	// MetricUnit is the display unit label for an "amount" metric (e.g. "mL",
	// "oz", "g", "min"). Empty for non-amount metrics.
	MetricUnit string `json:"metricUnit"`
}

// Metric type constants for Chore.MetricType.
const (
	MetricNone     = "none"
	MetricAmount   = "amount"
	MetricRating   = "rating"
	MetricDuration = "duration"
)

// ValidMetricType reports whether t is a recognized metric type.
func ValidMetricType(t string) bool {
	switch t {
	case MetricNone, MetricAmount, MetricRating, MetricDuration:
		return true
	}
	return false
}

// NormalizeMetric fills in a default metric configuration, deriving it from the
// legacy HasVolumeML/HasRating flags when MetricType is unset, then re-syncs the
// legacy flags so both representations agree. Call before persisting a chore.
func (c *Chore) NormalizeMetric() {
	if c.MetricType == "" || !ValidMetricType(c.MetricType) {
		switch {
		case c.HasVolumeML:
			c.MetricType = MetricAmount
			if c.MetricUnit == "" {
				c.MetricUnit = "mL"
			}
		case c.HasRating:
			c.MetricType = MetricRating
		default:
			c.MetricType = MetricNone
		}
	}
	switch c.MetricType {
	case MetricAmount:
		if c.MetricUnit == "" {
			c.MetricUnit = "mL"
		}
	default:
		c.MetricUnit = ""
	}
	// Keep the legacy flags in lockstep so downstream readers stay correct.
	c.HasVolumeML = c.MetricType == MetricAmount
	c.HasRating = c.MetricType == MetricRating
}

type Store interface {
	CreateChore(ctx context.Context, chore Chore) (Chore, error)
	GetChore(ctx context.Context, id int64) (Chore, error)
	ListChores(ctx context.Context, householdID int64) ([]Chore, error)
	UpdateChore(ctx context.Context, chore Chore) error
	DeleteChore(ctx context.Context, id int64) error
	ReorderChores(ctx context.Context, householdID int64, choreIDs []int64) error
	SeedPredefinedChores(ctx context.Context, householdID int64) error
}
