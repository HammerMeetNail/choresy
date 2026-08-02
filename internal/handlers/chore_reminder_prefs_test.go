package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/household"
	"github.com/HammerMeetNail/nabu/internal/reminder"
)

func setupReminderTest(t *testing.T) (*ChoreReminderPrefsHandler, string, *auth.Service) {
	t.Helper()
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetAuditLogger(nil)

	store := reminder.NewMemoryStore()
	handler := NewChoreReminderPrefsHandler(store)

	user, session := quickRegister(authService, "reminder@example.com")
	_ = user

	return handler, session.ID, authService
}

func TestChoreReminderPrefs_ListUnauthorized(t *testing.T) {
	store := reminder.NewMemoryStore()
	handler := NewChoreReminderPrefsHandler(store)
	req := httptest.NewRequest(http.MethodGet, "/api/chore-reminder-prefs", nil)
	rec := httptest.NewRecorder()

	handler.List(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestChoreReminderPrefs_List(t *testing.T) {
	handler, sessionID, authService := setupReminderTest(t)
	req := withUser(httptest.NewRequest(http.MethodGet, "/api/chore-reminder-prefs", nil), authService, sessionID)
	rec := httptest.NewRecorder()

	handler.List(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", rec.Code, rec.Body.String())
	}

	var body struct {
		Prefs []reminder.ChoreReminderPref `json:"prefs"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(body.Prefs) != 0 {
		t.Errorf("expected empty prefs list, got %d items", len(body.Prefs))
	}
}

func TestChoreReminderPrefs_UpdateUnauthorized(t *testing.T) {
	store := reminder.NewMemoryStore()
	handler := NewChoreReminderPrefsHandler(store)
	req := httptest.NewRequest(http.MethodPatch, "/api/chore-reminder-prefs/10",
		strings.NewReader(`{"enabled": true, "leadMinutes": 15}`))
	req.SetPathValue("choreId", "10")
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler.Update(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestChoreReminderPrefs_Update(t *testing.T) {
	handler, sessionID, authService := setupReminderTest(t)
	req := withUser(httptest.NewRequest(http.MethodPatch, "/api/chore-reminder-prefs/10",
		strings.NewReader(`{"enabled": true, "leadMinutes": 15}`)), authService, sessionID)
	req.SetPathValue("choreId", "10")
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler.Update(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", rec.Code, rec.Body.String())
	}

	var body struct {
		Pref reminder.ChoreReminderPref `json:"pref"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !body.Pref.Enabled {
		t.Error("expected enabled=true")
	}
	if body.Pref.LeadMinutes != 15 {
		t.Errorf("LeadMinutes = %d, want 15", body.Pref.LeadMinutes)
	}
}

func TestChoreReminderPrefs_UpdateInvalidChoreId(t *testing.T) {
	handler, sessionID, authService := setupReminderTest(t)
	req := withUser(httptest.NewRequest(http.MethodPatch, "/api/chore-reminder-prefs/abc",
		strings.NewReader(`{"enabled": true}`)), authService, sessionID)
	req.SetPathValue("choreId", "abc")
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler.Update(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", rec.Code)
	}
}

// TestChoreReminderPrefs_UpdateCrossHouseholdChore proves the handler rejects
// prefs updates for a chore that belongs to another household (finding #10
// hygiene: do not trust the choreId from the client).
func TestChoreReminderPrefs_UpdateCrossHouseholdChore(t *testing.T) {
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetMailer(nil, "")
	authService.SetAuditLogger(nil)

	householdStore := household.NewMemoryStore()
	householdService := household.NewService(householdStore, authService)
	ctx := httptest.NewRequest(http.MethodGet, "/", nil).Context()

	userA, sessionA := quickRegister(authService, "alice@example.com")
	hhA, err := householdService.CreateHousehold(ctx, "Home A", "HA", userA.ID)
	if err != nil {
		t.Fatalf("CreateHousehold A: %v", err)
	}

	userB, _ := quickRegister(authService, "bob@example.com")
	hhB, err := householdService.CreateHousehold(ctx, "Home B", "HB", userB.ID)
	if err != nil {
		t.Fatalf("CreateHousehold B: %v", err)
	}

	choreStore := chore.NewMemoryStore()
	choreService := chore.NewService(choreStore)
	foreignChore, err := choreService.CreateChore(ctx, hhB.ID, userB.ID, "Their Chore", "🧹", "#FF0000", "", nil, nil, nil, "", "", nil)
	if err != nil {
		t.Fatalf("CreateChore in B: %v", err)
	}

	handler := NewChoreReminderPrefsHandler(reminder.NewMemoryStore()).WithChoreStore(choreStore)

	req := withUser(httptest.NewRequest(http.MethodPatch, "/api/chore-reminder-prefs/"+strconv.FormatInt(foreignChore.ID, 10),
		strings.NewReader(`{"enabled": true}`)), authService, sessionA.ID)
	req.SetPathValue("choreId", strconv.FormatInt(foreignChore.ID, 10))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler.Update(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (body=%s)", rec.Code, rec.Body.String())
	}

	// The user's own chore in household A is accepted (prefs flow intact).
	ownChore, err := choreService.CreateChore(ctx, hhA.ID, userA.ID, "My Chore", "🧽", "#00FF00", "", nil, nil, nil, "", "", nil)
	if err != nil {
		t.Fatalf("CreateChore in A: %v", err)
	}
	req2 := withUser(httptest.NewRequest(http.MethodPatch, "/api/chore-reminder-prefs/"+strconv.FormatInt(ownChore.ID, 10),
		strings.NewReader(`{"enabled": true}`)), authService, sessionA.ID)
	req2.SetPathValue("choreId", strconv.FormatInt(ownChore.ID, 10))
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	handler.Update(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("own-household status = %d, want 200 (body=%s)", rec2.Code, rec2.Body.String())
	}
}
