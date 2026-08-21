package userprefs

import "context"

// Preferences holds all user-specific settings.
type Preferences struct {
	// ChoreOrder is an ordered list of chore IDs reflecting the user's
	// preferred sort order in the pick-chore and quick-log sheets.
	// Chores absent from this list are appended after the ordered ones.
	ChoreOrder []int64 `json:"choreOrder"`

	// HiddenHomeChoreIDs is the set of chore IDs the user has removed from
	// their home grid.  The chores still exist in the household and are
	// accessible from the Chores tab; they are simply not shown on the home
	// screen for this user.
	HiddenHomeChoreIDs []int64 `json:"hiddenHomeChoreIds"`

	// Timezone is the IANA timezone name (e.g. "America/New_York") used for
	// stats aggregation.  Empty means UTC.
	Timezone string `json:"timezone"`

	// VolumeUnit is the user's preferred unit for displaying/inputting feed
	// volumes: "ml" (default) or "oz". Volumes are always stored canonically
	// in milliliters; this only affects rendering and the log-sheet picker.
	VolumeUnit string `json:"volumeUnit"`

	// StatsSectionOrder is the user's preferred ordering of stats page
	// sections, expressed as an ordered list of canonical section keys.
	// Missing or empty means "use the canonical default order".
	StatsSectionOrder []string `json:"statsSectionOrder"`

	// StatsSectionHidden is the set of section keys the user has removed
	// from the stats page. Hidden sections are not rendered.
	StatsSectionHidden []string `json:"statsSectionHidden"`

	// StatsWidgets is the user's list of custom stats widgets (Phase 4).
	StatsWidgets []StatsWidget `json:"statsWidgets"`

	// HideNotificationBadge suppresses the in-app unread-notifications
	// badge (the count on the bell / tab). Notifications still accumulate
	// and remain visible in the notifications panel; only the badge is
	// hidden. Default false.
	HideNotificationBadge bool `json:"hideNotificationBadge"`
}

// Store is the persistence interface for user preferences.
type Store interface {
	// Get returns the preferences for userID.  If no row exists yet it returns
	// a zero-value Preferences (empty ChoreOrder) without an error.
	Get(ctx context.Context, userID int64) (Preferences, error)

	// Upsert creates or replaces the preferences for userID.
	Upsert(ctx context.Context, userID int64, p Preferences) error
}
