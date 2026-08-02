package handlers

import (
	"net/http"
	"strconv"

	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/middleware"
	"github.com/HammerMeetNail/nabu/internal/reminder"
)

type ChoreReminderPrefsHandler struct {
	store      reminder.Store
	choreStore chore.Store // optional; nil disables the ownership check
}

func NewChoreReminderPrefsHandler(store reminder.Store) *ChoreReminderPrefsHandler {
	return &ChoreReminderPrefsHandler{store: store}
}

// WithChoreStore attaches the chore store used to verify that a chore being
// configured belongs to the caller's household.
func (h *ChoreReminderPrefsHandler) WithChoreStore(cs chore.Store) *ChoreReminderPrefsHandler {
	h.choreStore = cs
	return h
}

func (h *ChoreReminderPrefsHandler) List(w http.ResponseWriter, r *http.Request) {
	user, ok := middleware.CurrentUser(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	prefs, err := h.store.GetChoreReminderPrefs(r.Context(), user.ID)
	if err != nil {
		writeServerError(w, "failed to load reminder preferences", err)
		return
	}

	if prefs == nil {
		prefs = []reminder.ChoreReminderPref{}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"prefs": prefs,
	})
}

func (h *ChoreReminderPrefsHandler) Update(w http.ResponseWriter, r *http.Request) {
	user, ok := middleware.CurrentUser(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	choreIDStr := r.PathValue("choreId")
	choreID, err := strconv.ParseInt(choreIDStr, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid choreId")
		return
	}

	// Do not trust the choreId from the client: verify the chore belongs to
	// the caller's household before touching prefs for it (defense in depth).
	if h.choreStore != nil {
		c, err := h.choreStore.GetChore(r.Context(), choreID)
		if err != nil || c.HouseholdID != *user.HouseholdID {
			writeError(w, http.StatusForbidden, "chore does not belong to your household")
			return
		}
	}

	var req struct {
		Enabled     *bool `json:"enabled"`
		LeadMinutes *int  `json:"leadMinutes"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	current, err := h.store.GetChoreReminderPref(r.Context(), user.ID, choreID)
	if err != nil {
		writeServerError(w, "failed to update reminder preferences", err)
		return
	}

	if req.Enabled != nil {
		current.Enabled = *req.Enabled
	}
	if req.LeadMinutes != nil {
		current.LeadMinutes = *req.LeadMinutes
	}
	current.UserID = user.ID
	current.ChoreID = choreID

	if err := h.store.UpdateChoreReminderPref(r.Context(), current); err != nil {
		writeServerError(w, "failed to update reminder preferences", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"pref": current,
	})
}
