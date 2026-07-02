package userprefs

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"unicode/utf8"
)

// StatsWidget is a user-defined stats widget (Phase 4). It is a typed,
// declarative document — never an expression or user-supplied code. Every field
// is validated server-side against a closed allowlist, and Title is stored as
// data and always rendered through the client's escapeHTML discipline. Widgets
// are a presentation layer over the existing stats endpoints: they cannot
// express a query the API does not already answer, which is what keeps them
// secure (no user-controlled SQL/aggregation path).
type StatsWidget struct {
	ID       string  `json:"id"`
	Type     string  `json:"type"`
	ChoreIDs []int64 `json:"choreIds"`
	Metric   string  `json:"metric"`
	Agg      string  `json:"agg"`
	Period   string  `json:"period"`
	Grain    string  `json:"grain"`
	Title    string  `json:"title"`
}

// Closed allowlists for every enum field. Adding a value here is the only way
// to widen what a widget can express.
var (
	widgetTypes   = map[string]bool{"timeseries": true, "total": true, "last-done": true, "interval": true, "member-split": true, "top-list": true}
	widgetMetrics = map[string]bool{"count": true, "amount": true, "rating": true, "duration": true}
	widgetAggs    = map[string]bool{"": true, "sum": true, "avg": true, "min": true, "max": true}
	widgetPeriods = map[string]bool{"day": true, "week": true, "month": true, "all": true}
	widgetGrains  = map[string]bool{"": true, "daily": true, "weekly": true, "monthly": true}
)

// Widget storage caps.
const (
	MaxStatsWidgets      = 20
	MaxStatsWidgetsBytes = 4096
	MaxWidgetChoreIDs    = 10
	MaxWidgetTitleRunes  = 60
)

// newWidgetID returns a short, URL/DOM-safe random identifier.
func newWidgetID() string {
	var b [8]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

// ValidateAndNormalizeWidgets checks a widget list against the closed schema and
// caps, assigns server-side IDs to any widget missing a (safe) one, and returns
// the normalized list. It performs NO ownership check on ChoreIDs — the caller
// (which knows the household) must validate those separately.
func ValidateAndNormalizeWidgets(widgets []StatsWidget) ([]StatsWidget, error) {
	if widgets == nil {
		return []StatsWidget{}, nil
	}
	if len(widgets) > MaxStatsWidgets {
		return nil, fmt.Errorf("too many widgets (max %d)", MaxStatsWidgets)
	}
	out := make([]StatsWidget, 0, len(widgets))
	seenID := map[string]bool{}
	for _, w := range widgets {
		if !widgetTypes[w.Type] {
			return nil, fmt.Errorf("invalid widget type: %q", w.Type)
		}
		if w.Metric != "" && !widgetMetrics[w.Metric] {
			return nil, fmt.Errorf("invalid widget metric: %q", w.Metric)
		}
		if !widgetAggs[w.Agg] {
			return nil, fmt.Errorf("invalid widget agg: %q", w.Agg)
		}
		if w.Period != "" && !widgetPeriods[w.Period] {
			return nil, fmt.Errorf("invalid widget period: %q", w.Period)
		}
		if !widgetGrains[w.Grain] {
			return nil, fmt.Errorf("invalid widget grain: %q", w.Grain)
		}
		if utf8.RuneCountInString(w.Title) > MaxWidgetTitleRunes {
			return nil, fmt.Errorf("widget title too long (max %d)", MaxWidgetTitleRunes)
		}
		if len(w.ChoreIDs) > MaxWidgetChoreIDs {
			return nil, fmt.Errorf("too many chores in widget (max %d)", MaxWidgetChoreIDs)
		}
		id := w.ID
		if id == "" || !isSafeWidgetID(id) || len(id) > 64 || seenID[id] {
			id = newWidgetID()
			for seenID[id] {
				id = newWidgetID()
			}
		}
		seenID[id] = true
		ids := w.ChoreIDs
		if ids == nil {
			ids = []int64{}
		}
		out = append(out, StatsWidget{
			ID:       id,
			Type:     w.Type,
			ChoreIDs: ids,
			Metric:   w.Metric,
			Agg:      w.Agg,
			Period:   w.Period,
			Grain:    w.Grain,
			Title:    w.Title,
		})
	}
	// Enforce the byte cap on the serialized form.
	raw, err := json.Marshal(out)
	if err != nil {
		return nil, err
	}
	if len(raw) > MaxStatsWidgetsBytes {
		return nil, fmt.Errorf("widgets too large (max %d bytes)", MaxStatsWidgetsBytes)
	}
	return out, nil
}
