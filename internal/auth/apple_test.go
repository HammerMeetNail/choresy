package auth

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// appleTestKit hosts a fixture JWKS over httptest and mints RS256 identity
// tokens signed with the matching private key.
type appleTestKit struct {
	key      *rsa.PrivateKey
	kid      string
	jwksSrv  *httptest.Server
	verifier *AppleVerifier
}

func newAppleTestKit(t *testing.T, clientIDs ...string) *appleTestKit {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("GenerateKey: %v", err)
	}
	kit := &appleTestKit{key: key, kid: "test-kid"}

	kit.jwksSrv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := base64.RawURLEncoding.EncodeToString(key.N.Bytes())
		e := base64.RawURLEncoding.EncodeToString([]byte{1, 0, 1}) // 65537
		_ = json.NewEncoder(w).Encode(map[string]any{
			"keys": []map[string]string{
				{"kid": kit.kid, "kty": "RSA", "alg": "RS256", "n": n, "e": e},
			},
		})
	}))
	t.Cleanup(kit.jwksSrv.Close)

	kit.verifier = &AppleVerifier{
		ClientIDs: clientIDs,
		Issuer:    appleIssuer,
		JWKsURL:   kit.jwksSrv.URL,
	}
	return kit
}

// mint builds an RS256 JWT with the given claim overrides on top of a valid
// baseline.
func (k *appleTestKit) mint(t *testing.T, overrides map[string]any) string {
	t.Helper()
	header := map[string]any{"alg": "RS256", "kid": k.kid}
	claims := map[string]any{
		"iss":            appleIssuer,
		"aud":            "com.nabu.app",
		"sub":            "001234.abcdef",
		"email":          "user@privaterelay.appleid.com",
		"email_verified": "true",
		"nonce":          "expected-nonce",
		"exp":            time.Now().Add(10 * time.Minute).Unix(),
	}
	for key, val := range overrides {
		if val == nil {
			delete(claims, key)
		} else {
			claims[key] = val
		}
	}
	headerJSON, _ := json.Marshal(header)
	claimsJSON, _ := json.Marshal(claims)
	signingInput := base64.RawURLEncoding.EncodeToString(headerJSON) + "." + base64.RawURLEncoding.EncodeToString(claimsJSON)
	digest := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, k.key, crypto.SHA256, digest[:])
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func TestAppleVerifier_ValidToken(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	token := kit.mint(t, nil)

	identity, err := kit.verifier.VerifyIdentityToken(context.Background(), token, "expected-nonce")
	if err != nil {
		t.Fatalf("VerifyIdentityToken: %v", err)
	}
	if identity.Subject != "001234.abcdef" {
		t.Fatalf("subject = %q", identity.Subject)
	}
	if identity.Email != "user@privaterelay.appleid.com" {
		t.Fatalf("email = %q", identity.Email)
	}
	if !identity.EmailVerified {
		t.Fatal("email_verified string \"true\" should normalize to true")
	}
}

func TestAppleVerifier_BoolEmailVerified(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	token := kit.mint(t, map[string]any{"email_verified": true})

	identity, err := kit.verifier.VerifyIdentityToken(context.Background(), token, "expected-nonce")
	if err != nil {
		t.Fatalf("VerifyIdentityToken: %v", err)
	}
	if !identity.EmailVerified {
		t.Fatal("bool email_verified should pass through")
	}
}

func TestAppleVerifier_Rejections(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")

	cases := []struct {
		name      string
		token     func() string
		nonce     string
		wantInErr string
	}{
		{"wrong issuer", func() string { return kit.mint(t, map[string]any{"iss": "https://evil.example"}) }, "expected-nonce", "invalid iss"},
		{"wrong audience", func() string { return kit.mint(t, map[string]any{"aud": "com.other.app"}) }, "expected-nonce", "aud does not match"},
		{"expired", func() string { return kit.mint(t, map[string]any{"exp": time.Now().Add(-time.Minute).Unix()}) }, "expected-nonce", "expired"},
		{"nonce mismatch", func() string { return kit.mint(t, nil) }, "other-nonce", "nonce"},
		{"nonce missing in token", func() string { return kit.mint(t, map[string]any{"nonce": nil}) }, "expected-nonce", "nonce"},
		{"empty expected nonce", func() string { return kit.mint(t, nil) }, "", "nonce required"},
		{"garbage token", func() string { return "not.a.jwt" }, "expected-nonce", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := kit.verifier.VerifyIdentityToken(context.Background(), tc.token(), tc.nonce)
			if err == nil {
				t.Fatal("expected error")
			}
			if tc.wantInErr != "" && !strings.Contains(err.Error(), tc.wantInErr) {
				t.Fatalf("err = %v, want substring %q", err, tc.wantInErr)
			}
		})
	}
}

func TestAppleVerifier_TamperedSignature(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	token := kit.mint(t, nil)
	parts := strings.Split(token, ".")

	// Re-encode the payload with a different subject but keep the old signature.
	payload, _ := base64.RawURLEncoding.DecodeString(parts[1])
	tampered := strings.Replace(string(payload), "001234.abcdef", "999999.attacker", 1)
	parts[1] = base64.RawURLEncoding.EncodeToString([]byte(tampered))

	_, err := kit.verifier.VerifyIdentityToken(context.Background(), strings.Join(parts, "."), "expected-nonce")
	if err == nil || !strings.Contains(err.Error(), "signature") {
		t.Fatalf("err = %v, want signature failure", err)
	}
}

func TestAppleVerifier_RejectsWrongAlg(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	// alg=none style token: header says none, empty signature.
	header, _ := json.Marshal(map[string]string{"alg": "none", "kid": kit.kid})
	claims, _ := json.Marshal(map[string]any{
		"iss": appleIssuer, "aud": "com.nabu.app", "sub": "x",
		"nonce": "expected-nonce", "exp": time.Now().Add(time.Minute).Unix(),
	})
	token := fmt.Sprintf("%s.%s.", base64.RawURLEncoding.EncodeToString(header), base64.RawURLEncoding.EncodeToString(claims))

	_, err := kit.verifier.VerifyIdentityToken(context.Background(), token, "expected-nonce")
	if err == nil || !strings.Contains(err.Error(), "algorithm") {
		t.Fatalf("err = %v, want algorithm rejection", err)
	}
}

func TestAppleVerifier_SecondAudienceAccepted(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app", "com.nabu.web")
	token := kit.mint(t, map[string]any{"aud": "com.nabu.web"})

	if _, err := kit.verifier.VerifyIdentityToken(context.Background(), token, "expected-nonce"); err != nil {
		t.Fatalf("VerifyIdentityToken: %v", err)
	}
}

// ─── Service-level upsert behavior ───────────────────────────────────────────

func TestLoginWithApple_CreatesVerifiedUser(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	store := NewMemoryStore()
	svc := NewService(store)
	svc.SetAppleVerifier(kit.verifier)

	user, session, err := svc.LoginWithApple(context.Background(), kit.mint(t, nil), "expected-nonce")
	if err != nil {
		t.Fatalf("LoginWithApple: %v", err)
	}
	if user.Email != "user@privaterelay.appleid.com" {
		t.Fatalf("email = %q", user.Email)
	}
	if !user.EmailVerified {
		t.Fatal("apple-created user should be email-verified")
	}
	if session.ID == "" {
		t.Fatal("expected a session")
	}
}

func TestLoginWithApple_LinksExistingAccountByEmail(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	store := NewMemoryStore()
	svc := NewService(store)
	svc.SetAppleVerifier(kit.verifier)

	existing, err := store.CreateUser(context.Background(), "user@privaterelay.appleid.com", "hash")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	user, _, err := svc.LoginWithApple(context.Background(), kit.mint(t, nil), "expected-nonce")
	if err != nil {
		t.Fatalf("LoginWithApple: %v", err)
	}
	if user.ID != existing.ID {
		t.Fatalf("logged into user %d, want existing %d (same email must link, not duplicate)", user.ID, existing.ID)
	}
	if !user.EmailVerified {
		t.Fatal("apple sign-in should mark the linked account verified")
	}
}

func TestLoginWithApple_UnverifiedEmailRejected(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app")
	svc := NewService(NewMemoryStore())
	svc.SetAppleVerifier(kit.verifier)

	_, _, err := svc.LoginWithApple(context.Background(), kit.mint(t, map[string]any{"email_verified": "false"}), "expected-nonce")
	if err != ErrAppleNoEmail {
		t.Fatalf("err = %v, want ErrAppleNoEmail", err)
	}
}

// ─── Web-flow authorization URL ──────────────────────────────────────────────

func TestAppleWebAuthCodeURL(t *testing.T) {
	kit := newAppleTestKit(t, "com.nabu.app", "com.nabu.web")
	svc := NewService(NewMemoryStore())
	svc.SetAppleVerifier(kit.verifier)
	svc.SetAppleWebAuth(&AppleWebAuth{
		ClientID:    "com.nabu.web",
		RedirectURL: "https://nabu.example/api/auth/apple/web/callback",
	})

	got, err := svc.AppleWebAuthCodeURL("the-state", "the-nonce")
	if err != nil {
		t.Fatalf("AppleWebAuthCodeURL: %v", err)
	}
	u, err := url.Parse(got)
	if err != nil {
		t.Fatalf("parse url: %v", err)
	}
	if u.Scheme != "https" || u.Host != "appleid.apple.com" || u.Path != "/auth/authorize" {
		t.Fatalf("url = %s, want https://appleid.apple.com/auth/authorize", got)
	}
	q := u.Query()
	want := map[string]string{
		"client_id":     "com.nabu.web",
		"redirect_uri":  "https://nabu.example/api/auth/apple/web/callback",
		"response_type": "code id_token",
		"response_mode": "form_post",
		"scope":         "email",
		"state":         "the-state",
		"nonce":         "the-nonce",
	}
	for key, val := range want {
		if q.Get(key) != val {
			t.Fatalf("%s = %q, want %q", key, q.Get(key), val)
		}
	}
}

func TestAppleWebAuthCodeURL_NotConfigured(t *testing.T) {
	svc := NewService(NewMemoryStore())
	if _, err := svc.AppleWebAuthCodeURL("s", "n"); err != ErrAppleUnavailable {
		t.Fatalf("err = %v, want ErrAppleUnavailable", err)
	}

	// A web-auth config without an enabled verifier is still unavailable:
	// the callback could never verify what Apple posts back.
	svc.SetAppleWebAuth(&AppleWebAuth{ClientID: "com.nabu.web", RedirectURL: "https://nabu.example/cb"})
	if _, err := svc.AppleWebAuthCodeURL("s", "n"); err != ErrAppleUnavailable {
		t.Fatalf("err = %v, want ErrAppleUnavailable", err)
	}
}

func TestLoginWithApple_NotConfigured(t *testing.T) {
	svc := NewService(NewMemoryStore())
	if _, _, err := svc.LoginWithApple(context.Background(), "token", "nonce"); err != ErrAppleUnavailable {
		t.Fatalf("err = %v, want ErrAppleUnavailable", err)
	}

	svc.SetAppleVerifier(&AppleVerifier{}) // no client IDs → disabled
	if _, _, err := svc.LoginWithApple(context.Background(), "token", "nonce"); err != ErrAppleUnavailable {
		t.Fatalf("err = %v, want ErrAppleUnavailable", err)
	}
}
