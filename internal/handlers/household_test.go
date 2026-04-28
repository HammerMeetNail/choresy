package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/dave/choresy/internal/auth"
	"github.com/dave/choresy/internal/household"
	"github.com/dave/choresy/internal/mail"
)

func setupHouseholdTest(t *testing.T) (*HouseholdHandler, string, *auth.Service) {
	t.Helper()
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	mailer := mail.NewMemorySender()
	authService.SetMailer(mailer, "http://localhost:8080")
	authService.SetAuditLogger(nil)

	householdStore := household.NewMemoryStore()
	householdService := household.NewService(householdStore, authService)
	handler := NewHouseholdHandler(householdService)

	user, session, _ := authService.Register(
		httptest.NewRequest(http.MethodGet, "/", nil).Context(),
		"alice@example.com", "password123",
	)
	_ = user

	return handler, session.ID, authService
}

func TestHouseholdGetNoHousehold(t *testing.T) {
	handler, sessionID, authService := setupHouseholdTest(t)
	req := withUser(httptest.NewRequest(http.MethodGet, "/api/household", nil), authService, sessionID)
	rec := httptest.NewRecorder()

	handler.Get(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusNotFound)
	}
}

func TestHouseholdCreate(t *testing.T) {
	handler, sessionID, authService := setupHouseholdTest(t)
	req := withUser(httptest.NewRequest(http.MethodPost, "/api/household", strings.NewReader(
		`{"name":"My Home"}`,
	)), authService, sessionID)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	handler.Create(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d, body=%s", rec.Code, http.StatusCreated, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"My Home"`) {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestHouseholdGet(t *testing.T) {
	handler, sessionID, authService := setupHouseholdTest(t)
	// Create household first
	createReq := withUser(httptest.NewRequest(http.MethodPost, "/", strings.NewReader(
		`{"name":"Test Home"}`,
	)), authService, sessionID)
	createReq.Header.Set("Content-Type", "application/json")
	handler.Create(httptest.NewRecorder(), createReq)

	req := withUser(httptest.NewRequest(http.MethodGet, "/api/household", nil), authService, sessionID)
	rec := httptest.NewRecorder()

	handler.Get(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d, body=%s", rec.Code, http.StatusOK, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"Test Home"`) {
		t.Fatalf("body = %s", rec.Body.String())
	}
}

func TestHouseholdLeave(t *testing.T) {
	handler, sessionID, authService := setupHouseholdTest(t)
	// Create household
	createReq := withUser(httptest.NewRequest(http.MethodPost, "/", strings.NewReader(
		`{"name":"Leave Me"}`,
	)), authService, sessionID)
	createReq.Header.Set("Content-Type", "application/json")
	handler.Create(httptest.NewRecorder(), createReq)

	req := withUser(httptest.NewRequest(http.MethodPost, "/api/household/leave", nil), authService, sessionID)
	rec := httptest.NewRecorder()

	handler.Leave(rec, req)

	// Sole owner cannot leave — that's correct behavior (ErrLastOwner)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want %d, body=%s", rec.Code, http.StatusForbidden, rec.Body.String())
	}
}

func TestHouseholdRequiresAuth(t *testing.T) {
	handler, _, _ := setupHouseholdTest(t)
	req := httptest.NewRequest(http.MethodGet, "/api/household", nil)
	rec := httptest.NewRecorder()

	handler.Get(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusUnauthorized)
	}
}
