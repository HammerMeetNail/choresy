package handlers

import (
	"net/http"
	"time"

	"github.com/HammerMeetNail/nabu/internal/daynote"
	"github.com/HammerMeetNail/nabu/internal/middleware"
)

// DayNoteHandler serves the per-day household diary notes (Phase 5.4).
type DayNoteHandler struct {
	service *daynote.Service
}

// NewDayNoteHandler constructs a DayNoteHandler.
func NewDayNoteHandler(service *daynote.Service) *DayNoteHandler {
	return &DayNoteHandler{service: service}
}

// List handles GET /api/day-notes?start=YYYY-MM-DD&end=YYYY-MM-DD.
func (h *DayNoteHandler) List(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}
	now := time.Now().UTC()
	end := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, 1)
	start := end.AddDate(0, 0, -90)
	if s := r.URL.Query().Get("start"); s != "" {
		if t, err := time.Parse("2006-01-02", s); err == nil {
			start = t
		}
	}
	if s := r.URL.Query().Get("end"); s != "" {
		if t, err := time.Parse("2006-01-02", s); err == nil {
			end = t
		}
	}
	notes, err := h.service.ListRange(r.Context(), *user.HouseholdID, start, end)
	if err != nil {
		writeServerError(w, "failed to load day notes", err)
		return
	}
	if notes == nil {
		notes = []daynote.DayNote{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"notes": notes})
}

// Set handles PUT /api/day-notes/{date} with a JSON body {"note": "..."}.
func (h *DayNoteHandler) Set(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}
	date := r.PathValue("date")
	var req struct {
		Note string `json:"note"`
	}
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	note, err := h.service.SetNote(r.Context(), *user.HouseholdID, date, req.Note, user.ID)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"note": note})
}
