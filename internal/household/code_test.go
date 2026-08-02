package household

import (
	"strings"
	"testing"
)

func TestGenerateInviteCode(t *testing.T) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	const wantLen = 10

	seen := map[string]bool{}
	for i := 0; i < 200; i++ {
		code := GenerateInviteCode()
		if len(code) != wantLen {
			t.Fatalf("code %q has length %d, want %d", code, len(code), wantLen)
		}
		for _, r := range code {
			if !strings.ContainsRune(alphabet, r) {
				t.Fatalf("code %q contains rune %q outside the alphabet", code, r)
			}
		}
		if seen[code] {
			t.Fatalf("duplicate code %q generated (200 draws; collision at 50 bits is suspicious)", code)
		}
		seen[code] = true
	}
}
