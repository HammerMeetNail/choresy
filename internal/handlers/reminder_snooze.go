package handlers

import (
	"net/http"
	"time"

	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/household"
	"github.com/HammerMeetNail/nabu/internal/middleware"
	"github.com/HammerMeetNail/nabu/internal/schedule"
	"github.com/HammerMeetNail/nabu/internal/userprefs"
)

// ReminderSnoozeHandler reschedules a chore's reminder a short time into the
// future (Phase 2.6). It is invoked by the service worker's "Snooze" push
// action, which cannot present a CSRF token, so the route is CSRF-exempt (see
// middleware.CSRF): it is session-authenticated, ownership-checked, and only
// re-emits the caller's own reminder — SameSite=Lax already blocks cross-site
// POSTs from carrying the session cookie.
type ReminderSnoozeHandler struct {
	scheduleStore  schedule.Store
	choreStore     chore.Store
	prefsStore     userprefs.Store
	householdStore household.Store
}

// NewReminderSnoozeHandler constructs a ReminderSnoozeHandler.
func NewReminderSnoozeHandler(scheduleStore schedule.Store, choreStore chore.Store, prefsStore userprefs.Store) *ReminderSnoozeHandler {
	return &ReminderSnoozeHandler{scheduleStore: scheduleStore, choreStore: choreStore, prefsStore: prefsStore}
}

func (h *ReminderSnoozeHandler) WithHouseholdStore(hs household.Store) *ReminderSnoozeHandler {
	h.householdStore = hs
	return h
}

// Snooze handles POST /api/reminders/snooze with {"choreId": N, "minutes": M}.
// It (idempotently) replaces any existing follow-up for the chore with a one-off
// follow-up schedule at now+minutes, so the reminder re-fires later.
func (h *ReminderSnoozeHandler) Snooze(w http.ResponseWriter, r *http.Request) {
	user, ok := middleware.CurrentUser(r.Context())
	if !ok || user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}

	var req struct {
		ChoreID int64 `json:"choreId"`
		Minutes int   `json:"minutes"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.ChoreID == 0 {
		writeError(w, http.StatusBadRequest, "choreId required")
		return
	}
	minutes := req.Minutes
	if minutes <= 0 {
		minutes = 30
	}
	if minutes > 24*60 {
		minutes = 24 * 60
	}

	// Ownership + visibility: the chore must be visible to the caller.
	c, err := h.choreStore.GetChore(r.Context(), req.ChoreID)
	if err != nil {
		writeError(w, http.StatusForbidden, "chore does not belong to your household")
		return
	}
	if c.HouseholdID != *user.HouseholdID {
		writeError(w, http.StatusForbidden, "chore does not belong to your household")
		return
	}
	if c.Visibility == chore.VisibilityAdmins && h.householdStore != nil {
		role, err := h.householdStore.GetMembershipForHousehold(r.Context(), user.ID, *user.HouseholdID)
		if err != nil || (role != household.RoleOwner && role != household.RoleAdmin) {
			writeError(w, http.StatusNotFound, "chore not found")
			return
		}
	}

	// Compute the target wall-clock time in the user's timezone so the
	// scheduled specificTime lines up with how reminders are evaluated.
	loc := time.UTC
	if h.prefsStore != nil {
		if prefs, perr := h.prefsStore.Get(r.Context(), user.ID); perr == nil && prefs.Timezone != "" {
			if l, lerr := time.LoadLocation(prefs.Timezone); lerr == nil {
				loc = l
			}
		}
	}
	target := time.Now().In(loc).Add(time.Duration(minutes) * time.Minute)
	startDate := schedule.DateOnly{Time: time.Date(target.Year(), target.Month(), target.Day(), 0, 0, 0, 0, loc)}

	// Idempotent: drop any existing follow-up for this chore, then create one.
	if err := h.scheduleStore.DeleteFollowUpSchedulesByChore(r.Context(), req.ChoreID); err != nil {
		writeServerError(w, "failed to snooze reminder", err)
		return
	}
	if _, err := h.scheduleStore.Create(r.Context(), schedule.ChoreSchedule{
		HouseholdID:   *user.HouseholdID,
		ChoreID:       req.ChoreID,
		FrequencyType: "once",
		TimePeriod:    schedule.PeriodAnytime,
		SpecificTime:  target.Format("15:04"),
		StartDate:     &startDate,
		IsActive:      true,
		IsFollowUp:    true,
	}); err != nil {
		writeServerError(w, "failed to snooze reminder", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "snoozed",
		"minutes": minutes,
	})
}
