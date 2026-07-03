package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/HammerMeetNail/nabu/internal/account"
	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/household"
	"github.com/HammerMeetNail/nabu/internal/mail"
)

func setupAccountTest(t *testing.T) (*AccountHandler, *auth.Service, *household.Service, auth.Store, household.Store) {
	t.Helper()
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetMailer(mail.NewMemorySender(), "http://localhost:8080")

	householdStore := household.NewMemoryStore()
	householdService := household.NewService(householdStore, authService)

	authHandler := NewAuthHandler(authService, "nabu_session", false, "http://localhost:8080")
	accountService := account.NewService(authStore, householdStore)
	handler := NewAccountHandler(accountService, authHandler)
	return handler, authService, householdService, authStore, householdStore
}

func deleteMeRequest(body string) *http.Request {
	return httptest.NewRequest(http.MethodDelete, "/api/me", strings.NewReader(body))
}

func TestAccountDelete_Unauthorized(t *testing.T) {
	handler, _, _, _, _ := setupAccountTest(t)
	rec := httptest.NewRecorder()

	handler.DeleteMe(rec, deleteMeRequest(`{"confirm":"DELETE"}`))

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestAccountDelete_RequiresTypedConfirmation(t *testing.T) {
	handler, authService, _, authStore, _ := setupAccountTest(t)
	user, session := quickRegister(authService, "confirm@test.com")

	for _, body := range []string{`{}`, `{"confirm":"delete"}`, `{"confirm":"yes"}`, ``} {
		rec := httptest.NewRecorder()
		req := withUser(deleteMeRequest(body), authService, session.ID)
		handler.DeleteMe(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("body %q: status = %d, want 400", body, rec.Code)
		}
	}
	if _, err := authStore.GetUserByID(deleteMeRequest("").Context(), user.ID); err != nil {
		t.Fatal("user deleted without valid confirmation")
	}
}

func TestAccountDelete_Success(t *testing.T) {
	handler, authService, householdService, authStore, _ := setupAccountTest(t)
	user, session := quickRegister(authService, "gone@test.com")
	ctx := deleteMeRequest("").Context()
	if _, err := householdService.CreateHousehold(ctx, "My Home", "MH", user.ID); err != nil {
		t.Fatalf("CreateHousehold: %v", err)
	}

	rec := httptest.NewRecorder()
	req := withUser(deleteMeRequest(`{"confirm":"DELETE"}`), authService, session.ID)
	handler.DeleteMe(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200, body=%s", rec.Code, rec.Body.String())
	}
	if _, err := authStore.GetUserByID(ctx, user.ID); err == nil {
		t.Fatal("user still exists")
	}
	// The session cookie must be cleared (expired) in the response.
	cleared := false
	for _, c := range rec.Result().Cookies() {
		if c.Name == "nabu_session" && c.MaxAge < 0 {
			cleared = true
		}
	}
	if !cleared {
		t.Fatal("session cookie was not cleared")
	}
	// The old session must no longer authenticate.
	if _, err := authService.Authenticate(ctx, session.ID); err == nil {
		t.Fatal("session still authenticates after account deletion")
	}
}

func TestAccountDelete_SoleOwnerWithMembersConflict(t *testing.T) {
	handler, authService, householdService, authStore, householdStore := setupAccountTest(t)
	owner, ownerSession := quickRegister(authService, "owner@test.com")
	member, _ := quickRegister(authService, "member@test.com")
	ctx := deleteMeRequest("").Context()
	hh, err := householdService.CreateHousehold(ctx, "Family", "F", owner.ID)
	if err != nil {
		t.Fatalf("CreateHousehold: %v", err)
	}
	if err := householdStore.AddMember(ctx, hh.ID, member.ID, household.RoleMember); err != nil {
		t.Fatalf("AddMember: %v", err)
	}

	rec := httptest.NewRecorder()
	req := withUser(deleteMeRequest(`{"confirm":"DELETE"}`), authService, ownerSession.ID)
	handler.DeleteMe(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, want 409, body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "transfer ownership") {
		t.Fatalf("body should explain the transfer requirement, got %s", rec.Body.String())
	}
	if _, err := authStore.GetUserByID(ctx, owner.ID); err != nil {
		t.Fatal("owner deleted despite conflict")
	}
}
