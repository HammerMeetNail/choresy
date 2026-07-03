package apns

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"sync"
	"time"
)

// ProviderTokenSigner mints the ES256 provider-authentication JWTs APNs
// requires. Apple rejects tokens older than 1h and rate-limits refreshes
// under ~20min, so tokens are cached and reused for 50 minutes.
type ProviderTokenSigner struct {
	key    *ecdsa.PrivateKey
	keyID  string
	teamID string

	mu       sync.Mutex
	token    string
	issuedAt time.Time
	now      func() time.Time
}

// NewProviderTokenSigner parses a PEM-encoded PKCS#8 ECDSA P-256 private key
// (the contents of the .p8 file downloaded from the Apple developer portal).
func NewProviderTokenSigner(p8PEM, keyID, teamID string) (*ProviderTokenSigner, error) {
	block, _ := pem.Decode([]byte(p8PEM))
	if block == nil {
		return nil, fmt.Errorf("apns: no PEM block in auth key")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("apns: parse auth key: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok {
		return nil, fmt.Errorf("apns: auth key is not an ECDSA key")
	}
	if keyID == "" || teamID == "" {
		return nil, fmt.Errorf("apns: key id and team id are required")
	}
	return &ProviderTokenSigner{
		key:    key,
		keyID:  keyID,
		teamID: teamID,
		now:    func() time.Time { return time.Now().UTC() },
	}, nil
}

// Token returns a cached provider JWT, minting a fresh one when the cached
// token is older than 50 minutes.
func (s *ProviderTokenSigner) Token() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.token != "" && s.now().Sub(s.issuedAt) < 50*time.Minute {
		return s.token, nil
	}
	token, err := s.mint()
	if err != nil {
		return "", err
	}
	s.token = token
	s.issuedAt = s.now()
	return token, nil
}

func (s *ProviderTokenSigner) mint() (string, error) {
	header, _ := json.Marshal(map[string]string{"alg": "ES256", "kid": s.keyID})
	claims, _ := json.Marshal(map[string]any{"iss": s.teamID, "iat": s.now().Unix()})
	signingInput := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(claims)

	digest := sha256.Sum256([]byte(signingInput))
	r, sVal, err := ecdsa.Sign(rand.Reader, s.key, digest[:])
	if err != nil {
		return "", fmt.Errorf("apns: sign provider token: %w", err)
	}
	// JOSE ES256 signatures are the raw 32-byte big-endian R and S values
	// concatenated, not ASN.1 DER.
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	sVal.FillBytes(sig[32:])
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}
