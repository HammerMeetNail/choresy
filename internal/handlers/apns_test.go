package handlers

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/HammerMeetNail/nabu/internal/apns"
	"github.com/HammerMeetNail/nabu/internal/auth"
	"github.com/HammerMeetNail/nabu/internal/mail"
)

func setupAPNsTest(t *testing.T) (*APNsHandler, *apns.MemoryStore, *auth.Service) {
	t.Helper()
	authStore := auth.NewMemoryStore()
	authService := auth.NewService(authStore)
	authService.SetMailer(mail.NewMemorySender(), "http://localhost:8080")
	store := apns.NewMemoryStore()
	return NewAPNsHandler(store), store, authService
}

func apnsRequest(path, body string) *http.Request {
	return httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
}

func TestAPNsRegister_Unauthorized(t *testing.T) {
	handler, _, _ := setupAPNsTest(t)
	rec := httptest.NewRecorder()
	handler.Register(rec, apnsRequest("/api/mobile/apns/register", `{"token":"aabb","environment":"sandbox","bundleId":"com.nabu.app"}`))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
}

func TestAPNsRegister_Validation(t *testing.T) {
	handler, store, authService := setupAPNsTest(t)
	_, session := quickRegister(authService, "apns@test.com")

	cases := []string{
		`{"environment":"sandbox","bundleId":"b"}`,                                            // missing token
		`{"token":"not hex!","environment":"sandbox","bundleId":"b"}`,                         // non-hex token
		`{"token":"aabb","environment":"staging","bundleId":"b"}`,                             // bad environment
		`{"token":"aabb","environment":"sandbox"}`,                                            // missing bundle id
		`{"token":"` + strings.Repeat("a", 201) + `","environment":"sandbox","bundleId":"b"}`, // oversized token
	}
	for _, body := range cases {
		rec := httptest.NewRecorder()
		req := withUser(apnsRequest("/api/mobile/apns/register", body), authService, session.ID)
		handler.Register(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("body %q: status = %d, want 400", body, rec.Code)
		}
	}
	devices, _ := store.DevicesForUser(apnsRequest("/", "").Context(), 1)
	if len(devices) != 0 {
		t.Fatal("invalid registrations must not persist")
	}
}

func TestAPNsRegisterUnregister_RoundTrip(t *testing.T) {
	handler, store, authService := setupAPNsTest(t)
	user, session := quickRegister(authService, "apns@test.com")
	ctx := apnsRequest("/", "").Context()

	rec := httptest.NewRecorder()
	req := withUser(apnsRequest("/api/mobile/apns/register",
		`{"token":"AABB01","environment":"sandbox","bundleId":"com.nabu.app","deviceName":"Dave's iPhone"}`), authService, session.ID)
	handler.Register(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("register status = %d, body=%s", rec.Code, rec.Body.String())
	}

	devices, _ := store.DevicesForUser(ctx, user.ID)
	if len(devices) != 1 || devices[0].Token != "AABB01" || devices[0].Environment != "sandbox" {
		t.Fatalf("devices = %+v", devices)
	}

	rec = httptest.NewRecorder()
	req = withUser(apnsRequest("/api/mobile/apns/unregister", `{"token":"AABB01"}`), authService, session.ID)
	handler.Unregister(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("unregister status = %d", rec.Code)
	}
	devices, _ = store.DevicesForUser(ctx, user.ID)
	if len(devices) != 0 {
		t.Fatalf("devices after unregister = %+v", devices)
	}
}

func TestAPNsUnregister_CrossUserIsolation(t *testing.T) {
	handler, store, authService := setupAPNsTest(t)
	owner, ownerSession := quickRegister(authService, "owner@test.com")
	_, otherSession := quickRegister(authService, "other@test.com")
	ctx := apnsRequest("/", "").Context()

	rec := httptest.NewRecorder()
	req := withUser(apnsRequest("/api/mobile/apns/register",
		`{"token":"cafe01","environment":"production","bundleId":"com.nabu.app"}`), authService, ownerSession.ID)
	handler.Register(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("register status = %d", rec.Code)
	}

	// Another user unregistering the same token must not remove it.
	rec = httptest.NewRecorder()
	req = withUser(apnsRequest("/api/mobile/apns/unregister", `{"token":"cafe01"}`), authService, otherSession.ID)
	handler.Unregister(rec, req)

	devices, _ := store.DevicesForUser(ctx, owner.ID)
	if len(devices) != 1 {
		t.Fatal("cross-user unregister removed the owner's token")
	}
}
