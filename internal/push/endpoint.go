package push

import (
	"net"
	"net/url"
	"strings"
)

// allowedPushHostSuffixes lists the push services this app may deliver to.
// Web Push endpoints always live on one of these (FCM for Chrome/Edge,
// APNs for Safari, Mozilla's autopush for Firefox, WNS for legacy Windows);
// allowlisting the host is the primary defense against SSRF to internal
// addresses — an unvalidated endpoint becomes a server-side POST to
// whatever URL the subscriber chose.
var allowedPushHostSuffixes = []string{
	"fcm.googleapis.com",
	"push.apple.com",
	"notify.windows.com",
	"push.services.mozilla.com",
}

// EndpointAllowed reports whether a Web Push endpoint may be subscribed to
// and POSTed to. Requires:
//   - a parseable https URL with a host (no userinfo, no IP literals — real
//     push endpoints are always hostnames, and IP-literal hosts are the
//     classic SSRF payload shape);
//   - a host on the push-service allowlist (suffix match).
func EndpointAllowed(endpoint string) bool {
	u, err := url.Parse(endpoint)
	if err != nil || u.Scheme != "https" || u.Hostname() == "" {
		return false
	}
	if u.User != nil {
		// Browsers never produce userinfo endpoints; reject so any embedded
		// credentials can never be shipped to the push host.
		return false
	}
	host := u.Hostname()
	if ip := net.ParseIP(host); ip != nil {
		// Reject IP-literal hosts outright: loopback/private/link-local/
		// unspecified addresses are internal-network SSRF payloads, and even
		// a public literal is never a real push-service endpoint.
		return false
	}
	for _, suffix := range allowedPushHostSuffixes {
		if host == suffix || strings.HasSuffix(host, "."+suffix) {
			return true
		}
	}
	return false
}

// endpointHost returns just the scheme+host of a push endpoint for logging.
// The full endpoint URL is a bearer-style capability (its path/query authorize
// delivery to a specific browser), so only the host is safe to log.
func endpointHost(endpoint string) string {
	u, err := url.Parse(endpoint)
	if err != nil || u.Host == "" {
		return "unknown"
	}
	return u.Scheme + "://" + u.Host
}
