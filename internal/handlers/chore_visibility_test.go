package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/chore"
	"github.com/HammerMeetNail/nabu/internal/household"
	"github.com/HammerMeetNail/nabu/internal/mail"
	"github.com/HammerMeetNail/nabu/internal/middleware"
)

func setupVisibilityTest(t *testing.T) (*ChoreHandler, *ChoreHandler, func(*http.Request) *http.Request, func(*http.Request) *http.Request, int64) {
	t.Helper()
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetMailer(mail.NewMemorySender(), "http://localhost:8080")
	householdStore := household.NewMemoryStore()
	householdService := household.NewService(householdStore, authService)
	choreStore := chore.NewMemoryStore()
	choreService := chore.NewService(choreStore)
	choreService.WithMemberships(householdStore)
	handler := NewChoreHandler(choreService)

	owner, ownerSession := quickRegister(authService, "owner-vis@example.com")
	hh, err := householdService.CreateHousehold(httptest.NewRequest(http.MethodGet, "/", nil).Context(), "Vis Home", "", owner.ID)
	if err != nil {
		t.Fatalf("CreateHousehold: %v", err)
	}

	// Create member
	member, memberSession := quickRegister(authService, "member-vis@example.com")
	// Member joins via invite
	// Use householdStore directly to add member
	_ = householdStore.AddMember(httptest.NewRequest(http.MethodGet, "/", nil).Context(), hh.ID, member.ID, household.RoleMember)
	// Set auth household for member
	_ = authStore.SetUserHousehold(httptest.NewRequest(http.MethodGet, "/", nil).Context(), member.ID, hh.ID, household.RoleMember)

	ownerWrapper := func(r *http.Request) *http.Request {
		r.AddCookie(&http.Cookie{Name: "nabu_session", Value: ownerSession.ID})
		var authed *http.Request
		rec := httptest.NewRecorder()
		middleware.Session(authService, "nabu_session")(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			authed = req
		})).ServeHTTP(rec, r)
		return authed
	}
	memberWrapper := func(r *http.Request) *http.Request {
		r.AddCookie(&http.Cookie{Name: "nabu_session", Value: memberSession.ID})
		var authed *http.Request
		rec := httptest.NewRecorder()
		middleware.Session(authService, "nabu_session")(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
			authed = req
		})).ServeHTTP(rec, r)
		return authed
	}

	// Both handlers share same service/store, but we return same handler for both
	return handler, handler, ownerWrapper, memberWrapper, hh.ID
}

func TestPrivateChoreVisibility(t *testing.T) {
	handler, _, ownerReq, memberReq, _ := setupVisibilityTest(t)

	// Owner creates Admins-only chore
	req := ownerReq(httptest.NewRequest(http.MethodPost, "/api/chores", strings.NewReader(`{"name":"Secret Gift","icon":"🎁","color":"#8B5CF6","visibility":"admins"}`)))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("owner create private: status=%d body=%s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Secret Gift") {
		t.Fatalf("body missing name: %s", rec.Body.String())
	}

	// Member tries to create Admins-only chore -> 403
	req2 := memberReq(httptest.NewRequest(http.MethodPost, "/api/chores", strings.NewReader(`{"name":"Member Private","icon":"🎁","color":"#8B5CF6","visibility":"admins"}`)))
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	handler.Create(rec2, req2)
	if rec2.Code != http.StatusForbidden {
		t.Fatalf("member create private: expected 403 got %d body=%s", rec2.Code, rec2.Body.String())
	}

	// Member lists chores -> should not see Secret Gift
	req3 := memberReq(httptest.NewRequest(http.MethodGet, "/api/chores", nil))
	rec3 := httptest.NewRecorder()
	handler.List(rec3, req3)
	if rec3.Code != http.StatusOK {
		t.Fatalf("member list: %d", rec3.Code)
	}
	if strings.Contains(rec3.Body.String(), "Secret Gift") {
		t.Fatalf("member list should not contain private chore: %s", rec3.Body.String())
	}

	// Owner lists -> should see it
	req4 := ownerReq(httptest.NewRequest(http.MethodGet, "/api/chores", nil))
	rec4 := httptest.NewRecorder()
	handler.List(rec4, req4)
	if !strings.Contains(rec4.Body.String(), "Secret Gift") {
		t.Fatalf("owner list should contain private chore: %s", rec4.Body.String())
	}

	// Member GET private chore -> 404
	req5 := memberReq(httptest.NewRequest(http.MethodGet, "/api/chores/1", nil))
	req5.SetPathValue("id", "1")
	rec5 := httptest.NewRecorder()
	handler.Get(rec5, req5)
	if rec5.Code != http.StatusNotFound {
		t.Fatalf("member get private: expected 404 got %d body=%s", rec5.Code, rec5.Body.String())
	}

	// Owner GET private chore -> 200
	req6 := ownerReq(httptest.NewRequest(http.MethodGet, "/api/chores/1", nil))
	req6.SetPathValue("id", "1")
	rec6 := httptest.NewRecorder()
	handler.Get(rec6, req6)
	if rec6.Code != http.StatusOK {
		t.Fatalf("owner get private: expected 200 got %d body=%s", rec6.Code, rec6.Body.String())
	}

	// Member tries to PATCH private chore visibility -> 404 (cannot view)
	req7 := memberReq(httptest.NewRequest(http.MethodPatch, "/api/chores/1", strings.NewReader(`{"name":"Hacked"}`)))
	req7.Header.Set("Content-Type", "application/json")
	req7.SetPathValue("id", "1")
	rec7 := httptest.NewRecorder()
	handler.Update(rec7, req7)
	if rec7.Code != http.StatusNotFound {
		t.Fatalf("member patch private: expected 404 got %d body=%s", rec7.Code, rec7.Body.String())
	}

	// Invalid visibility -> 400
	req8 := ownerReq(httptest.NewRequest(http.MethodPost, "/api/chores", strings.NewReader(`{"name":"Bad Vis","icon":"🎁","color":"#8B5CF6","visibility":"superadmin"}`)))
	req8.Header.Set("Content-Type", "application/json")
	rec8 := httptest.NewRecorder()
	handler.Create(rec8, req8)
	if rec8.Code != http.StatusBadRequest {
		t.Fatalf("invalid visibility: expected 400 got %d body=%s", rec8.Code, rec8.Body.String())
	}
}

func TestPrivateChoreUpdateReturnsChore(t *testing.T) {
	handler, _, ownerReq, _, _ := setupVisibilityTest(t)
	// Create shared chore
	req := ownerReq(httptest.NewRequest(http.MethodPost, "/api/chores", strings.NewReader(`{"name":"Shared","icon":"📋","color":"#FF0000"}`)))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.Create(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create shared: %d %s", rec.Code, rec.Body.String())
	}
	// Update with visibility admins and check response contains chore
	req2 := ownerReq(httptest.NewRequest(http.MethodPatch, "/api/chores/1", strings.NewReader(`{"visibility":"admins"}`)))
	req2.Header.Set("Content-Type", "application/json")
	req2.SetPathValue("id", "1")
	rec2 := httptest.NewRecorder()
	handler.Update(rec2, req2)
	if rec2.Code != http.StatusOK {
		t.Fatalf("update to private: %d %s", rec2.Code, rec2.Body.String())
	}
	if !strings.Contains(rec2.Body.String(), `"visibility":"admins"`) && !strings.Contains(rec2.Body.String(), `"visibility": "admins"`) {
		t.Fatalf("response should contain updated chore with visibility admins: %s", rec2.Body.String())
	}
	if !strings.Contains(rec2.Body.String(), `"chore"`) {
		t.Fatalf("response should contain chore object: %s", rec2.Body.String())
	}
}
