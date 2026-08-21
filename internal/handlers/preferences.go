package handlers

import (
	"errors"
	"net/http"

	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/middleware"
	"github.com/HammerMeetNail/nabu/internal/userprefs"
)

// PreferencesHandler handles GET /api/preferences and PATCH /api/preferences.
type PreferencesHandler struct {
	service    *userprefs.Service
	choreStore chore.Store // optional; used to ownership-check widget choreIds
}

// NewPreferencesHandler constructs a PreferencesHandler.
func NewPreferencesHandler(service *userprefs.Service) *PreferencesHandler {
	return &PreferencesHandler{service: service}
}

// WithChoreStore attaches a chore store so widget choreIds can be
// ownership-checked against the caller's household.
func (h *PreferencesHandler) WithChoreStore(cs chore.Store) *PreferencesHandler {
	h.choreStore = cs
	return h
}

// Get returns the current user's preferences.
func (h *PreferencesHandler) Get(w http.ResponseWriter, r *http.Request) {
	user, ok := middleware.CurrentUser(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	prefs, err := h.service.GetPreferences(r.Context(), user.ID)
	if err != nil {
		writeServerError(w, "failed to load preferences", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"preferences": prefs})
}

// Update patches the current user's preferences.  Only fields present in the
// request body are updated; choreOrder, hiddenHomeChoreIds, and timezone are
// supported.
func (h *PreferencesHandler) Update(w http.ResponseWriter, r *http.Request) {
	user, ok := middleware.CurrentUser(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req struct {
		ChoreOrder            *[]int64                 `json:"choreOrder"`
		HiddenHomeChoreIDs    *[]int64                 `json:"hiddenHomeChoreIds"`
		Timezone              *string                  `json:"timezone"`
		VolumeUnit            *string                  `json:"volumeUnit"`
		StatsSectionOrder     *[]string                `json:"statsSectionOrder"`
		StatsSectionHidden    *[]string                `json:"statsSectionHidden"`
		StatsWidgets          *[]userprefs.StatsWidget `json:"statsWidgets"`
		HideNotificationBadge *bool                    `json:"hideNotificationBadge"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	if req.ChoreOrder != nil {
		if err := h.service.UpdateChoreOrder(r.Context(), user.ID, *req.ChoreOrder); err != nil {
			writeServerError(w, "failed to update preferences", err)
			return
		}
	}

	if req.HiddenHomeChoreIDs != nil {
		if err := h.service.UpdateHiddenHomeChores(r.Context(), user.ID, *req.HiddenHomeChoreIDs); err != nil {
			writeServerError(w, "failed to update preferences", err)
			return
		}
	}

	if req.Timezone != nil {
		if err := h.service.UpdateTimezone(r.Context(), user.ID, *req.Timezone); err != nil {
			if errors.Is(err, userprefs.ErrInvalidInput) {
				writeError(w, http.StatusBadRequest, err.Error())
				return
			}
			writeServerError(w, "failed to update preferences", err)
			return
		}
	}

	if req.VolumeUnit != nil {
		if err := h.service.UpdateVolumeUnit(r.Context(), user.ID, *req.VolumeUnit); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	if req.StatsSectionOrder != nil {
		if err := h.service.UpdateStatsSectionOrder(r.Context(), user.ID, *req.StatsSectionOrder); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	if req.StatsSectionHidden != nil {
		if err := h.service.UpdateStatsSectionHidden(r.Context(), user.ID, *req.StatsSectionHidden); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	if req.HideNotificationBadge != nil {
		if err := h.service.UpdateHideNotificationBadge(r.Context(), user.ID, *req.HideNotificationBadge); err != nil {
			writeServerError(w, "failed to update preferences", err)
			return
		}
	}

	if req.StatsWidgets != nil {
		// Ownership check: every referenced chore must belong to the caller's
		// household. This is defense-in-depth on top of the stats endpoints'
		// own ownership checks (a widget renders via those endpoints).
		if h.choreStore != nil {
			owned := map[int64]bool{}
			if user.HouseholdID != nil {
				chores, err := h.choreStore.ListChores(r.Context(), *user.HouseholdID)
				if err != nil {
					writeServerError(w, "failed to update preferences", err)
					return
				}
				for _, c := range chores {
					owned[c.ID] = true
				}
			}
			for _, wdg := range *req.StatsWidgets {
				for _, cid := range wdg.ChoreIDs {
					if !owned[cid] {
						writeError(w, http.StatusForbidden, "widget references a chore outside your household")
						return
					}
				}
			}
		}
		if _, err := h.service.UpdateStatsWidgets(r.Context(), user.ID, *req.StatsWidgets); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
	}

	prefs, err := h.service.GetPreferences(r.Context(), user.ID)
	if err != nil {
		writeServerError(w, "failed to load preferences", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"preferences": prefs})
}
