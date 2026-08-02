package push

import "testing"

func TestEndpointAllowed(t *testing.T) {
	cases := []struct {
		name     string
		endpoint string
		want     bool
	}{
		{"fcm", "https://fcm.googleapis.com/fcm/send/abc123", true},
		{"fcm subdomain", "https://android.googleapis.com/fcm/send/x", false},
		{"apple", "https://web.push.apple.com/xyz", true},
		{"mozilla", "https://updates.push.services.mozilla.com/wpush/v2/abc", true},
		{"mozilla apex", "https://push.services.mozilla.com/wpush/v2/abc", true},
		{"windows", "https://push.notify.windows.com/xyz", true},
		{"http scheme", "http://fcm.googleapis.com/fcm/send/abc", false},
		{"no scheme", "fcm.googleapis.com/fcm/send/abc", false},
		{"not a url", "notaurl", false},
		{"empty", "", false},
		{"loopback literal", "https://127.0.0.1/x", false},
		{"localhost literal", "https://localhost/x", false},
		{"cloud metadata", "https://169.254.169.254/latest/meta-data/", false},
		{"private literal", "https://10.0.0.5/x", false},
		{"public literal", "https://8.8.8.8/x", false},
		{"internal hostname", "https://metadata.internal/latest/meta-data/", false},
		{"intranet hostname", "https://my-corpserver.internal/x", false},
		{"spoofed suffix", "https://fcm.googleapis.com.evil.example/x", false},
		{"userinfo", "https://user:pass@fcm.googleapis.com/x", false},
		{"ipv6 literal", "https://[::1]/x", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := EndpointAllowed(tc.endpoint); got != tc.want {
				t.Errorf("EndpointAllowed(%q) = %v, want %v", tc.endpoint, got, tc.want)
			}
		})
	}
}

func TestEndpointHost(t *testing.T) {
	cases := []struct {
		endpoint string
		want     string
	}{
		{"https://fcm.googleapis.com/fcm/send/abc", "https://fcm.googleapis.com"},
		{"https://updates.push.services.mozilla.com/wpush/v2/xyz", "https://updates.push.services.mozilla.com"},
		{"notaurl", "unknown"},
		{"", "unknown"},
	}
	for _, tc := range cases {
		if got := endpointHost(tc.endpoint); got != tc.want {
			t.Errorf("endpointHost(%q) = %q, want %q", tc.endpoint, got, tc.want)
		}
	}
}
