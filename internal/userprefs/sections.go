package userprefs

import (
	"strconv"
	"strings"
)

// StatsSections lists every stats section in canonical default order.
// This is the single source of truth for section key names.
//
// When you add a new stats section, append it to the END of this list.
// Existing users will see the new section appear (visible by default)
// below their existing sections, per the layout-resolution algorithm.
var StatsSections = []string{
	"overview",
	"last-done",
	"baby",
	"activity",
	"busy-hours",
	"leaderboard",
	"top-chores",
	"categories",
	"chores",
	"recap",
}

// IsKnownStatsSection reports whether key is a recognized stats section. In
// addition to the static canonical sections it accepts the dynamic per-entity
// keys:
//   - "chore:<id>"   — a generalized per-chore analytics section (Phase 3)
//   - "widget:<uuid>" — a user-defined stats widget (Phase 4)
//
// The referenced chore/widget need not still exist: unknown dynamic keys are
// dropped harmlessly at render time (same as deleted static sections), so
// accepting them here only affects ordering/hidden bookkeeping.
func IsKnownStatsSection(key string) bool {
	for _, s := range StatsSections {
		if s == key {
			return true
		}
	}
	return isDynamicSectionKey(key)
}

// isDynamicSectionKey reports whether key is a well-formed dynamic section key.
func isDynamicSectionKey(key string) bool {
	if rest, ok := strings.CutPrefix(key, "chore:"); ok {
		id, err := strconv.ParseInt(rest, 10, 64)
		return err == nil && id > 0
	}
	if rest, ok := strings.CutPrefix(key, "widget:"); ok {
		return rest != "" && len(rest) <= 64 && isSafeWidgetID(rest)
	}
	return false
}

// isSafeWidgetID allows only URL/DOM-safe identifier characters in a widget id.
func isSafeWidgetID(s string) bool {
	for _, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}

// DefaultStatsSectionOrder returns a copy of the canonical order.
func DefaultStatsSectionOrder() []string {
	out := make([]string, len(StatsSections))
	copy(out, StatsSections)
	return out
}
