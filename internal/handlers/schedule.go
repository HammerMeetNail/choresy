// internal/handlers/schedule.go

package handlers

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/HammerMeetNail/nabu/internal/audit"
	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/household"
	"github.com/HammerMeetNail/nabu/internal/middleware"
	"github.com/HammerMeetNail/nabu/internal/schedule"
)

// ScheduleHandler handles HTTP requests for schedule CRUD and queries.
type ScheduleHandler struct {
	store          schedule.Store
	service        *schedule.Service
	choreStore     chore.Store
	householdStore household.Store
	auditLogger    audit.Logger
}

// NewScheduleHandler creates a new ScheduleHandler.
func NewScheduleHandler(store schedule.Store, service *schedule.Service) *ScheduleHandler {
	return &ScheduleHandler{store: store, service: service, auditLogger: audit.NopLogger{}}
}

// WithChoreStore attaches a chore store so the handler can verify that a
// schedule's referenced chore belongs to the caller's household, preventing a
// user from scheduling (and thus surfacing) another household's chore.
func (h *ScheduleHandler) WithChoreStore(cs chore.Store) *ScheduleHandler {
	h.choreStore = cs
	return h
}

// WithHouseholdStore attaches the household store for visibility/assignment checks.
func (h *ScheduleHandler) WithHouseholdStore(hs household.Store) *ScheduleHandler {
	h.householdStore = hs
	return h
}

// choreBelongsToHousehold reports whether choreID is owned by householdID. When
// no chore store is wired (some tests) it returns true so behavior is unchanged.
func (h *ScheduleHandler) choreBelongsToHousehold(ctx context.Context, choreID, householdID int64) bool {
	if h.choreStore == nil {
		return true
	}
	c, err := h.choreStore.GetChore(ctx, choreID)
	if err != nil {
		return false
	}
	return c.HouseholdID == householdID
}

func (h *ScheduleHandler) choreVisibleToUser(ctx context.Context, userID, householdID, choreID int64) (chore.Chore, bool) {
	if h.choreStore == nil {
		return chore.Chore{}, true
	}
	c, err := h.choreStore.GetChore(ctx, choreID)
	if err != nil {
		return chore.Chore{}, false
	}
	if c.HouseholdID != householdID {
		return chore.Chore{}, false
	}
	if c.Visibility == chore.VisibilityAdmins {
		if h.householdStore == nil {
			return c, false
		}
		role, err := h.householdStore.GetMembershipForHousehold(ctx, userID, householdID)
		if err != nil {
			return c, false
		}
		if role != household.RoleOwner && role != household.RoleAdmin {
			return c, false
		}
	}
	return c, true
}

func (h *ScheduleHandler) isAdmin(ctx context.Context, userID, householdID int64) bool {
	if h.householdStore == nil {
		return true
	}
	role, err := h.householdStore.GetMembershipForHousehold(ctx, userID, householdID)
	if err != nil {
		return false
	}
	return role == household.RoleOwner || role == household.RoleAdmin
}

func (h *ScheduleHandler) filterSchedulesVisible(ctx context.Context, userID, householdID int64, schedules []schedule.ChoreSchedule) []schedule.ChoreSchedule {
	if h.choreStore == nil {
		return schedules
	}
	var out []schedule.ChoreSchedule
	for _, s := range schedules {
		if _, ok := h.choreVisibleToUser(ctx, userID, householdID, s.ChoreID); ok {
			out = append(out, s)
		}
	}
	if out == nil {
		return []schedule.ChoreSchedule{}
	}
	return out
}

func (h *ScheduleHandler) validateAssignment(ctx context.Context, choreID int64, assignedUserID *int64, householdID int64) (int, string) {
	if assignedUserID == nil {
		return 0, ""
	}
	if h.choreStore == nil {
		return 0, ""
	}
	c, err := h.choreStore.GetChore(ctx, choreID)
	if err != nil {
		return 0, ""
	}
	if c.Visibility != chore.VisibilityAdmins {
		return 0, ""
	}
	if h.householdStore == nil {
		return 0, ""
	}
	role, err := h.householdStore.GetMembershipForHousehold(ctx, *assignedUserID, householdID)
	if err != nil {
		return 400, "assigned user is not a member"
	}
	if role != household.RoleOwner && role != household.RoleAdmin {
		return 400, "private task may only be assigned to an admin"
	}
	return 0, ""
}

// SetAuditLogger attaches a sink for schedule mutation events. A nil logger is
// a no-op (the handler keeps its default NopLogger).
func (h *ScheduleHandler) SetAuditLogger(logger audit.Logger) {
	if logger != nil {
		h.auditLogger = logger
	}
}

func (h *ScheduleHandler) logAudit(ctx context.Context, event string, attrs map[string]string) {
	audit.Emit(ctx, h.auditLogger, event, attrs)
}

// List returns all schedules for the user's household.
// GET /api/schedules
func (h *ScheduleHandler) List(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}
	schedules, err := h.store.ListByHousehold(r.Context(), *user.HouseholdID)
	if err != nil {
		writeServerError(w, "failed to load schedule", err)
		return
	}
	schedules = h.filterSchedulesVisible(r.Context(), user.ID, *user.HouseholdID, schedules)
	if schedules == nil {
		schedules = []schedule.ChoreSchedule{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"schedules": schedules})
}

// ForDate returns schedules active on a given date.
// GET /api/schedules/for-date?date=YYYY-MM-DD
func (h *ScheduleHandler) ForDate(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}

	dateStr := r.URL.Query().Get("date")
	date := time.Now().UTC()
	if dateStr != "" {
		if parsed, err := time.Parse("2006-01-02", dateStr); err == nil {
			date = parsed
		}
	}

	all, err := h.store.ListByHousehold(r.Context(), *user.HouseholdID)
	if err != nil {
		writeServerError(w, "failed to load schedule", err)
		return
	}
	all = h.filterSchedulesVisible(r.Context(), user.ID, *user.HouseholdID, all)

	active := h.service.GetSchedulesForDate(all, date)
	if active == nil {
		active = []schedule.ChoreSchedule{}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"schedules": active,
		"date":      date.Format("2006-01-02"),
	})
}

// Create adds a new schedule entry.
// POST /api/schedules
func (h *ScheduleHandler) Create(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}

	var req schedule.ChoreSchedule
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.ChoreID == 0 {
		writeError(w, http.StatusBadRequest, "choreId is required")
		return
	}
	if h.choreStore != nil {
		c, err := h.choreStore.GetChore(r.Context(), req.ChoreID)
		if err != nil {
			writeError(w, http.StatusNotFound, "chore not found")
			return
		}
		if c.HouseholdID != *user.HouseholdID {
			writeError(w, http.StatusForbidden, "chore does not belong to your household")
			return
		}
		if c.Visibility == chore.VisibilityAdmins && !h.isAdmin(r.Context(), user.ID, *user.HouseholdID) {
			writeError(w, http.StatusNotFound, "chore not found")
			return
		}
	}
	if req.TimePeriod == "" {
		req.TimePeriod = schedule.PeriodAnytime
	}
	if req.FrequencyType == "" {
		req.FrequencyType = "once"
	}
	if code, msg := h.validateAssignment(r.Context(), req.ChoreID, req.AssignedUserID, *user.HouseholdID); code != 0 {
		writeError(w, code, msg)
		return
	}
	req.HouseholdID = *user.HouseholdID
	req.IsActive = true

	created, err := h.store.Create(r.Context(), req)
	if err != nil {
		writeServerError(w, "failed to create schedule", err)
		return
	}
	h.logAudit(r.Context(), "schedule.created", map[string]string{
		"schedule_id": strconv.FormatInt(created.ID, 10),
		"chore_id":    strconv.FormatInt(req.ChoreID, 10),
	})
	writeJSON(w, http.StatusCreated, map[string]any{"schedule": created})
}

// Update partially updates a schedule entry.
// Only fields present in the JSON body are modified; all others are preserved
// from the existing record.  This prevents implicit zero-value overwrites (e.g.
// isActive being reset to false when only timePeriod is being changed).
// PATCH /api/schedules/{id}
func (h *ScheduleHandler) Update(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}

	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid schedule id")
		return
	}

	existing, err := h.store.Get(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "schedule not found")
		return
	}
	if existing.HouseholdID != *user.HouseholdID {
		writeError(w, http.StatusForbidden, "not your schedule")
		return
	}
	if _, ok := h.choreVisibleToUser(r.Context(), user.ID, *user.HouseholdID, existing.ChoreID); !ok {
		writeError(w, http.StatusNotFound, "schedule not found")
		return
	}

	// Decode as a raw map so we can distinguish "field not sent" from "field
	// sent as zero/false/null".  Only keys present in the payload are applied.
	var raw map[string]json.RawMessage
	if err := readJSON(r, &raw); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	// Start from the existing record; patch only what was provided.
	req := existing
	req.ID = id
	req.HouseholdID = *user.HouseholdID

	if v, ok := raw["choreId"]; ok {
		_ = json.Unmarshal(v, &req.ChoreID)
		if h.choreStore != nil {
			c, err := h.choreStore.GetChore(r.Context(), req.ChoreID)
			if err != nil {
				writeError(w, http.StatusNotFound, "chore not found")
				return
			}
			if c.HouseholdID != *user.HouseholdID {
				writeError(w, http.StatusForbidden, "chore does not belong to your household")
				return
			}
			if c.Visibility == chore.VisibilityAdmins && !h.isAdmin(r.Context(), user.ID, *user.HouseholdID) {
				writeError(w, http.StatusNotFound, "chore not found")
				return
			}
		}
	}
	if v, ok := raw["assignedUserId"]; ok {
		if string(v) == "null" {
			req.AssignedUserID = nil
		} else {
			var uid int64
			if json.Unmarshal(v, &uid) == nil {
				req.AssignedUserID = &uid
			}
		}
		if code, msg := h.validateAssignment(r.Context(), req.ChoreID, req.AssignedUserID, *user.HouseholdID); code != 0 {
			writeError(w, code, msg)
			return
		}
	}
	if v, ok := raw["timePeriod"]; ok {
		var s string
		if json.Unmarshal(v, &s) == nil {
			req.TimePeriod = schedule.TimePeriod(s)
		}
	}
	if v, ok := raw["specificTime"]; ok {
		if string(v) == "null" {
			req.SpecificTime = ""
		} else {
			_ = json.Unmarshal(v, &req.SpecificTime)
		}
	}
	if v, ok := raw["frequencyType"]; ok {
		_ = json.Unmarshal(v, &req.FrequencyType)
	}
	if v, ok := raw["isActive"]; ok {
		_ = json.Unmarshal(v, &req.IsActive)
	}
	if v, ok := raw["daysOfWeek"]; ok {
		_ = json.Unmarshal(v, &req.DaysOfWeek)
	}
	if v, ok := raw["intervalDays"]; ok {
		_ = json.Unmarshal(v, &req.IntervalDays)
	}
	if v, ok := raw["dayOfMonth"]; ok {
		_ = json.Unmarshal(v, &req.DayOfMonth)
	}
	if v, ok := raw["monthOfYear"]; ok {
		_ = json.Unmarshal(v, &req.MonthOfYear)
	}
	if v, ok := raw["startDate"]; ok {
		if string(v) == "null" {
			req.StartDate = nil
		} else {
			var d schedule.DateOnly
			if json.Unmarshal(v, &d) == nil {
				req.StartDate = &d
			}
		}
	}
	if v, ok := raw["recurrenceEnd"]; ok {
		if string(v) == "null" {
			req.RecurrenceEnd = nil
		} else {
			var t time.Time
			if json.Unmarshal(v, &t) == nil {
				req.RecurrenceEnd = &t
			}
		}
	}
	// If chore changed to private but assignment wasn't explicitly patched, still validate.
	if _, ok := raw["assignedUserId"]; !ok {
		if code, msg := h.validateAssignment(r.Context(), req.ChoreID, req.AssignedUserID, *user.HouseholdID); code != 0 {
			writeError(w, code, msg)
			return
		}
	}

	updated, err := h.store.Update(r.Context(), req)
	if err != nil {
		writeServerError(w, "failed to update schedule", err)
		return
	}
	h.logAudit(r.Context(), "schedule.updated", map[string]string{
		"schedule_id": strconv.FormatInt(id, 10),
	})
	writeJSON(w, http.StatusOK, map[string]any{"schedule": updated})
}

// Delete removes a schedule entry.
// DELETE /api/schedules/{id}
func (h *ScheduleHandler) Delete(w http.ResponseWriter, r *http.Request) {
	user, _ := middleware.CurrentUser(r.Context())
	if user.HouseholdID == nil {
		writeError(w, http.StatusUnauthorized, "no household")
		return
	}

	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid schedule id")
		return
	}

	existing, err := h.store.Get(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "schedule not found")
		return
	}
	if existing.HouseholdID != *user.HouseholdID {
		writeError(w, http.StatusForbidden, "not your schedule")
		return
	}
	if _, ok := h.choreVisibleToUser(r.Context(), user.ID, *user.HouseholdID, existing.ChoreID); !ok {
		writeError(w, http.StatusNotFound, "schedule not found")
		return
	}

	if err := h.store.Delete(r.Context(), id); err != nil {
		writeServerError(w, "failed to delete schedule", err)
		return
	}
	h.logAudit(r.Context(), "schedule.deleted", map[string]string{
		"schedule_id": strconv.FormatInt(id, 10),
	})
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
