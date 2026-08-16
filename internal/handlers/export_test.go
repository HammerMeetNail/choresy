package handlers

import (
	"context"
	"encoding/csv"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/daynote"
	"github.com/HammerMeetNail/nabu/internal/household"
	logsvc "github.com/HammerMeetNail/nabu/internal/log"
	"github.com/HammerMeetNail/nabu/internal/mail"
	"github.com/HammerMeetNail/nabu/internal/schedule"
)

type exportFixture struct {
	handler        *ExportHandler
	authService    *auth.Service
	householdStore *household.MemoryStore
	household      household.Household
	ownerSession   auth.Session
	owner          auth.User
}

func newExportFixture(t *testing.T) exportFixture {
	t.Helper()
	ctx := context.Background()
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetMailer(mail.NewMemorySender(), "http://localhost:8080")
	authService.SetAuditLogger(nil)

	householdStore := household.NewMemoryStore()
	householdService := household.NewService(householdStore, authService)
	owner, ownerSession := quickRegister(authService, "export-owner@example.com")
	hh, err := householdService.CreateHousehold(ctx, "Export Home", "EH", owner.ID)
	if err != nil {
		t.Fatalf("CreateHousehold: %v", err)
	}

	choreStore := chore.NewMemoryStore()
	ch, err := choreStore.CreateChore(ctx, chore.Chore{
		HouseholdID: hh.ID,
		Name:        "Export Chore",
		Icon:        "*",
		Color:       "#123456",
		Category:    "testing",
		CreatedBy:   &owner.ID,
	})
	if err != nil {
		t.Fatalf("CreateChore: %v", err)
	}

	logStore := logsvc.NewMemoryStore()
	logService := logsvc.NewService(logStore)
	now := time.Now().UTC()
	if _, err := logService.LogChore(ctx, hh.ID, owner.ID, ch.ID, nil, `=HYPERLINK("https://example.test")`, []string{"done"}, map[string]int{"done": 1}, &now, nil, &now, nil, nil, nil, nil); err != nil {
		t.Fatalf("LogChore: %v", err)
	}

	scheduleStore := schedule.NewMemoryStore()
	if _, err := scheduleStore.Create(ctx, schedule.ChoreSchedule{
		HouseholdID:   hh.ID,
		ChoreID:       ch.ID,
		FrequencyType: "daily",
		TimePeriod:    schedule.PeriodAnytime,
		IsActive:      true,
	}); err != nil {
		t.Fatalf("Create schedule: %v", err)
	}

	dayNoteService := daynote.NewService(daynote.NewMemoryStore())
	if _, err := dayNoteService.SetNote(ctx, hh.ID, "2026-06-16", "export diary note", owner.ID); err != nil {
		t.Fatalf("SetNote: %v", err)
	}
	if _, err := householdStore.CreateInvite(ctx, hh.ID, owner.ID, "SECRET-INVITE-CODE", 1); err != nil {
		t.Fatalf("CreateInvite: %v", err)
	}

	handler := NewExportHandler(householdService, householdStore, choreStore, logService, scheduleStore, dayNoteService)
	return exportFixture{
		handler:        handler,
		authService:    authService,
		householdStore: householdStore,
		household:      hh,
		ownerSession:   ownerSession,
		owner:          owner,
	}
}

func TestHouseholdExportIncludesScopedData(t *testing.T) {
	fixture := newExportFixture(t)
	req := withUser(httptest.NewRequest(http.MethodGet, "/api/household/data", nil), fixture.authService, fixture.ownerSession.ID)
	rec := httptest.NewRecorder()

	fixture.handler.Data(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); !strings.HasPrefix(got, "text/csv") {
		t.Fatalf("Content-Type = %q, want text/csv", got)
	}
	if got := rec.Header().Get("Content-Disposition"); !strings.Contains(got, "nabu-household-data.csv") {
		t.Fatalf("Content-Disposition = %q, want household export filename", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", got)
	}

	rows, err := csv.NewReader(strings.NewReader(rec.Body.String())).ReadAll()
	if err != nil {
		t.Fatalf("read CSV: %v", err)
	}
	if len(rows) < 8 {
		t.Fatalf("rows = %d, want header plus all record types", len(rows))
	}
	types := map[string]bool{}
	for _, row := range rows[1:] {
		if len(row) > 0 {
			types[row[0]] = true
		}
	}
	for _, recordType := range []string{"household", "member", "chore", "log", "schedule", "day_note", "invite"} {
		if !types[recordType] {
			t.Errorf("missing %s record", recordType)
		}
	}
	body := rec.Body.String()
	if !strings.Contains(body, "'=HYPERLINK") {
		t.Fatalf("formula cell was not escaped:\n%s", body)
	}
	if !strings.Contains(body, "export diary note") {
		t.Fatalf("day note missing from export:\n%s", body)
	}
	if strings.Contains(body, "SECRET-INVITE-CODE") {
		t.Fatalf("invite capability leaked into export:\n%s", body)
	}
}

func TestHouseholdExportAllowsAdminAndDeniesMember(t *testing.T) {
	fixture := newExportFixture(t)
	ctx := context.Background()

	if err := fixture.householdStore.UpdateMemberRole(ctx, fixture.household.ID, fixture.owner.ID, household.RoleAdmin); err != nil {
		t.Fatalf("promote owner to admin: %v", err)
	}
	adminReq := withUser(httptest.NewRequest(http.MethodGet, "/api/household/data", nil), fixture.authService, fixture.ownerSession.ID)
	adminRec := httptest.NewRecorder()
	fixture.handler.Data(adminRec, adminReq)
	if adminRec.Code != http.StatusOK {
		t.Fatalf("admin status = %d, want 200, body=%s", adminRec.Code, adminRec.Body.String())
	}

	member, memberSession := quickRegister(fixture.authService, "export-member@example.com")
	if err := fixture.householdStore.AddMember(ctx, fixture.household.ID, member.ID, household.RoleMember); err != nil {
		t.Fatalf("add member: %v", err)
	}
	if err := fixture.authService.SetUserHousehold(ctx, member.ID, fixture.household.ID, household.RoleMember); err != nil {
		t.Fatalf("set member household: %v", err)
	}
	memberReq := withUser(httptest.NewRequest(http.MethodGet, "/api/household/data", nil), fixture.authService, memberSession.ID)
	memberRec := httptest.NewRecorder()
	fixture.handler.Data(memberRec, memberReq)
	if memberRec.Code != http.StatusForbidden {
		t.Fatalf("member status = %d, want 403, body=%s", memberRec.Code, memberRec.Body.String())
	}
}
