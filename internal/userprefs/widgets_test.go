package userprefs_test

import (
	"strings"
	"testing"

	"github.com/HammerMeetNail/nabu/internal/userprefs"
)

func TestValidateAndNormalizeWidgets(t *testing.T) {
	t.Run("assigns id when missing and preserves fields", func(t *testing.T) {
		out, err := userprefs.ValidateAndNormalizeWidgets([]userprefs.StatsWidget{
			{Type: "total", Metric: "amount", Agg: "sum", Period: "week", Title: "Bottles this week", ChoreIDs: []int64{12}},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(out) != 1 {
			t.Fatalf("len = %d, want 1", len(out))
		}
		if out[0].ID == "" {
			t.Fatalf("expected a server-assigned id")
		}
		if out[0].Title != "Bottles this week" || out[0].Metric != "amount" {
			t.Fatalf("fields not preserved: %+v", out[0])
		}
	})

	t.Run("rejects unknown enum values", func(t *testing.T) {
		cases := []userprefs.StatsWidget{
			{Type: "evil"},
			{Type: "total", Metric: "sql"},
			{Type: "total", Agg: "drop"},
			{Type: "total", Period: "forever"},
			{Type: "total", Grain: "hourly"},
		}
		for i, w := range cases {
			if _, err := userprefs.ValidateAndNormalizeWidgets([]userprefs.StatsWidget{w}); err == nil {
				t.Fatalf("case %d: expected rejection for %+v", i, w)
			}
		}
	})

	t.Run("caps title length and widget count", func(t *testing.T) {
		if _, err := userprefs.ValidateAndNormalizeWidgets([]userprefs.StatsWidget{
			{Type: "total", Title: strings.Repeat("x", 61)},
		}); err == nil {
			t.Fatalf("expected title length rejection")
		}
		many := make([]userprefs.StatsWidget, userprefs.MaxStatsWidgets+1)
		for i := range many {
			many[i] = userprefs.StatsWidget{Type: "total"}
		}
		if _, err := userprefs.ValidateAndNormalizeWidgets(many); err == nil {
			t.Fatalf("expected widget-count rejection")
		}
	})

	t.Run("rejects an unsafe supplied id by reassigning", func(t *testing.T) {
		out, err := userprefs.ValidateAndNormalizeWidgets([]userprefs.StatsWidget{
			{ID: "../etc/passwd", Type: "total"},
		})
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if strings.ContainsAny(out[0].ID, "/.") {
			t.Fatalf("unsafe id was not replaced: %q", out[0].ID)
		}
	})

	t.Run("nil is normalized to empty", func(t *testing.T) {
		out, err := userprefs.ValidateAndNormalizeWidgets(nil)
		if err != nil || out == nil || len(out) != 0 {
			t.Fatalf("nil -> %v, %v", out, err)
		}
	})
}
