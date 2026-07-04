package app

import (
	"net/http"
	"strings"
)

// Static legal/support pages required for App Store submission (P6/A5):
// App Store Connect needs a privacy-policy URL and a support URL, and the
// iOS app's Settings → About links here. Served ahead of the SPA catch-all.

const pageShell = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%TITLE% — Nabu</title>
<style>
body { font-family: -apple-system, system-ui, sans-serif; max-width: 42rem; margin: 0 auto; padding: 2rem 1.25rem; line-height: 1.6; color: #1c2b33; background: #f4efe7; }
h1 { font-size: 1.5rem; } h2 { font-size: 1.15rem; margin-top: 1.75rem; }
a { color: #236886; }
@media (prefers-color-scheme: dark) { body { color: #e8e2d6; background: #0e1117; } a { color: #4dabce; } }
</style>
</head>
<body>
%BODY%
<p><a href="/">← Back to Nabu</a></p>
</body>
</html>`

const privacyBody = `
<h1>Privacy Policy</h1>
<p><em>Last updated: 2026-07-04</em></p>
<p>Nabu is a household activity tracker. This policy describes what data the
service stores and how it is used.</p>

<h2>Data we collect</h2>
<ul>
<li><strong>Account data:</strong> your email address and, optionally, a
display name. Used to sign you in and to identify you to other members of
your household.</li>
<li><strong>Household activity data:</strong> the chores, logs, schedules,
and notes you and your household members create. This is the product's
content and is visible to the members of your household.</li>
<li><strong>Push tokens:</strong> if you enable notifications, a device
push token used only to deliver your reminders.</li>
</ul>

<h2>What we don't do</h2>
<ul>
<li>No advertising, no third-party analytics, and no tracking SDKs.</li>
<li>Your data is never sold or shared with third parties.</li>
<li>Data is not used to train machine-learning models.</li>
</ul>

<h2>Data retention and deletion</h2>
<p>You can delete your account at any time from Settings → Account →
Delete Account (in the app or on the web). Deletion is immediate and
permanent: your account and, for households where you are the only member,
all household data are removed.</p>

<h2>Contact</h2>
<p>Questions about this policy: see the <a href="/support">support page</a>.</p>
`

const supportBody = `
<h1>Support</h1>
<p>Nabu is a household activity tracker for logging feeds, chores, and
routines together.</p>
<h2>Get help</h2>
<ul>
<li>Report issues or ask questions on
<a href="https://github.com/HammerMeetNail/nabu/issues">GitHub Issues</a>.</li>
</ul>
<h2>Common tasks</h2>
<ul>
<li><strong>Reset your password:</strong> use "Forgot password?" on the sign-in screen.</li>
<li><strong>Join a household:</strong> open the invite link a member shared with you.</li>
<li><strong>Delete your account:</strong> Settings → Account → Delete Account.</li>
</ul>
`

func registerStaticPages(mux *http.ServeMux) {
	serve := func(title, body string) http.HandlerFunc {
		html := strings.NewReplacer("%TITLE%", title, "%BODY%", body).Replace(pageShell)
		page := []byte(html)
		return func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Write(page) //nolint:errcheck
		}
	}
	mux.HandleFunc("/privacy", method(http.MethodGet, serve("Privacy Policy", privacyBody)))
	mux.HandleFunc("/support", method(http.MethodGet, serve("Support", supportBody)))
}
