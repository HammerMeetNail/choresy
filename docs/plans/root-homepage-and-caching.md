# Root homepage + HTML caching plan

Documentation of the change that made `/` serve the server-rendered marketing
page (`home.html`) to anonymous visitors and the SPA app shell to
authenticated users, and made every HTML page `Cache-Control: no-store`.

## Why

- **SEO / share links:** before this change the root `/` served the app shell
  to *everyone*, so anonymous crawlers and share links (e.g. `og:image` and
  `og:url` metadata on `https://nabu-app.com/`) landed on an empty `<div
  id="app">` shell with no content, no title, and no metadata.
- **No duplication:** the marketing content already existed in
  `web/templates/home.html`, reachable only at the legacy `/home` URL.
  Restyling the root to render that template to anonymous visitors removes the
  need for a separately-hosted marketing site.
- **Cache correctness:** the root alternates between two audiences depending on
  session state, so it can never be cached. All server-rendered HTML now ships
  `Cache-Control: no-store` (matching the JS files) so Cloudflare returns
  `cf-cache-status: BYPASS` and every visit reflects the latest state.

## Server behaviour (final)

`mux.HandleFunc("/", ...)` in `internal/app/server.go`:

1. `/api/*` → `404` (unchanged).
2. Session present → **app shell** (`renderIndex`). In-app navigations,
   deeplinks, and `GET /` signed-in all keep working.
3. No session and path is exactly `/` → **marketing page** (`renderHome`).
4. No session and any other path (`/login`, `/register`, `/today`, …) → app
   shell; the SPA's client-side router shows the login view there.

`renderIndex`, `renderHome`, and the static pages handler
(`registerStaticPages` in `internal/app/pages.go`) all set
`Cache-Control: no-store` + `Content-Type: text/html; charset=utf-8`.

## home.html edits

- `<link rel="canonical" href="{{.BaseURL}}/">`
- `<meta property="og:url" content="{{.BaseURL}}/">` (was `/home`)
- Logo link `/home` → `/`
- All CTAs (`Open Nabu`, hero, bottom) → `/login` (was `/`)

## File checklist

| File | Change |
|------|--------|
| `internal/app/server.go` | Root route: authenticated→shell, anonymous `/`→marketing; `renderIndex`/`renderHome` add `Cache-Control: no-store` |
| `internal/app/pages.go` | Static page handler (`/privacy`, `/support`) adds `Cache-Control: no-store` |
| `web/templates/home.html` | canonical + `og:url` → `/`, logo → `/`, CTAs → `/login` |
| `internal/app/server_test.go` | Unit tests: anonymous `/` → marketing HTML; authenticated `/` → shell; anonymous `/login` → shell; `/home` → marketing; all HTML responses `no-store` |
| `tests/e2e/magic-link.spec.js` | `page.goto(BASE)` → `goto(`/login`)` so the anonymous flow hits an app-shell route |
| `tests/e2e/settings-auth.spec.js` | same |
| `tests/e2e/validation.spec.js` | same |
| `tests/e2e/marketing-home.spec.js` | **new** — anonymous `/` marketing + no-store; CTA→login; authenticated `/` shell; logout→marketing; `/home` canonical |
| `docs/plans/client-parity.md` | `Web & Marketing` → `N/A` row (PWA-only) |
| `README.md` | HTML no-store paragraph; verify commands use `/login` + marketing checks; spec count |
| `docs/deploy-runbook.md` | verify commands updated |

## Verification (deploy)

```bash
curl -s https://nabu-app.com/ | grep 'rel="canonical"'
# <link rel="canonical" href="https://nabu-app.com/">

curl -sI https://nabu-app.com/ | grep -i cache
# cache-control: no-store
# cf-cache-status: BYPASS

curl -s https://nabu-app.com/login | grep 'app.js'
# src="/static/js/app.js?v=<version>"
```

## What NOT to do

- Do **not** cache `/` — it is session-dependent; `no-store` is correct.
- Do **not** add `?v=` manually to JS imports (server rewrites at startup).
- Do **not** point marketing CTAs back to `/` — they must reach the login view.