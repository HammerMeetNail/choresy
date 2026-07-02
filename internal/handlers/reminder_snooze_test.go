package handlers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/household"
	"github.com/HammerMeetNail/nabu/internal/mail"
	"github.com/HammerMeetNail/nabu/internal/schedule"
	"github.com/HammerMeetNail/nabu/internal/userprefs"
)

func TestReminderSnooze(t *testing.T) {
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetMailer(mail.NewMemorySender(), "http://localhost:8080")

	householdStore := household.NewMemoryStore()
	householdService := household.NewService(householdStore, authService)

	choreStore := chore.NewMemoryStore()
	scheduleStore := schedule.NewMemoryStore()
	prefsStore := userprefs.NewMemoryStore()
	handler := NewReminderSnoozeHandler(scheduleStore, choreStore, prefsStore)

	user, session := quickRegister(authService, "alice@example.com")
	ctx := context.Background()
	hh, err := householdService.CreateHousehold(ctx, "My Home", "", user.ID)
	if err != nil {
		t.Fatalf("CreateHousehold: %v", err)
	}

	ownChore, err := choreStore.CreateChore(ctx, chore.Chore{HouseholdID: hh.ID, Name: "Feed Baby"})
	if err != nil {
		t.Fatalf("create own chore: %v", err)
	}
	foreignChore, err := choreStore.CreateChore(ctx, chore.Chore{HouseholdID: hh.ID + 999, Name: "Litter"})
	if err != nil {
		t.Fatalf("create foreign chore: %v", err)
	}

	// Snoozing a foreign chore must be rejected (IDOR).
	body := fmt.Sprintf(`{"choreId":%d}`, foreignChore.ID)
	req := withUser(httptest.NewRequest(http.MethodPost, "/api/reminders/snooze", strings.NewReader(body)), authService, session.ID)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.Snooze(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("foreign chore: expected 403, got %d, body=%s", rec.Code, rec.Body.String())
	}

	// Snoozing an owned chore creates a one-off follow-up schedule.
	body = fmt.Sprintf(`{"choreId":%d,"minutes":30}`, ownChore.ID)
	req = withUser(httptest.NewRequest(http.MethodPost, "/api/reminders/snooze", strings.NewReader(body)), authService, session.ID)
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	handler.Snooze(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("own chore: expected 200, got %d, body=%s", rec.Code, rec.Body.String())
	}

	scheds, err := scheduleStore.ListByHousehold(ctx, hh.ID)
	if err != nil {
		t.Fatalf("List schedules: %v", err)
	}
	found := false
	for _, s := range scheds {
		if s.ChoreID == ownChore.ID && s.IsFollowUp && s.FrequencyType == "once" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected a once follow-up schedule for the chore, got %+v", scheds)
	}
}
