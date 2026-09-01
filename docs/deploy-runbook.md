# Deploy & CI Babysitting Runbook

> Extracted from `AGENTS.md` for progressive disclosure — read this when cutting a release tag, watching the deploy pipeline, or verifying production.

## Deploy trigger

Push a `v*` tag on `main` (e.g. `git tag v0.1.7 && git push origin v0.1.7`). CI builds, tests, scans/signs the image, deploys via SSH + Cloudflare Tunnel, and creates a GitHub release. The deploy job verifies the tagged commit is reachable from `origin/main` before proceeding — **never tag on a branch.**

Production URL: `https://nabu-app.com`. Production test account: `verify@yearofbingo.com` / `test123456`.

## 1. Watch the CI run

After pushing a `v*` tag, monitor the pipeline to completion and verify production. Do not wait for the user to ask. (A cheaper subagent may be delegated to this.)

```bash
# Find the run ID for the tag
gh run list --limit 5

# Stream logs until the run completes (blocks until done)
gh run watch <run-id>

# If a job fails, check which step failed
gh run view <run-id> --json jobs \
  --jq '.jobs[] | {name: .name, conclusion: .conclusion, steps: [.steps[] | select(.conclusion == "failure") | .name]}'

# Re-run only failed jobs (for transient infra errors)
gh run rerun <run-id> --failed
```

## 2. Distinguish transient vs. real failures

- If **only** the checkout/setup step failed and all test jobs passed → transient GitHub Actions infra error → re-run with `gh run rerun <run-id> --failed`.
- If a test job (Go Tests, JS Tests, E2E, Lint, iOS Unit Tests) failed → real failure → read the full log, fix the code, commit, re-tag, and push a new `v*` tag.

## 3. Verify production after deploy

Once the `Deploy to Production` job goes green:

```bash
# Confirm the app is up
curl -sS -o /dev/null -w "%{http_code}\n" https://nabu-app.com/health   # expect 200

# Confirm versioned imports carry the new tag
curl -s https://nabu-app.com/static/js/calendar.js | grep "^import"
# Expected: import { ... } from "./utils.js?v=0.1.X";

# Confirm cache headers — must be no-store / BYPASS, NOT max-age / HIT
curl -sI https://nabu-app.com/static/js/app.js | grep -i cache
# Expected: cache-control: no-store
#           cf-cache-status: BYPASS

# Confirm correct version in the app shell — anonymous GET / now serves the
# marketing page, so use a SPA route like /login for the shell
curl -s https://nabu-app.com/login | grep 'app.js'
# Expected: src="/static/js/app.js?v=0.1.X"

# Confirm the anonymous root serves the server-rendered marketing page with a
# canonical URL pointing at the root
curl -s https://nabu-app.com/ | grep 'rel="canonical"'
# Expected: <link rel="canonical" href="https://nabu-app.com/">

# HTML cache headers must also be no-store (Cloudflare reports DYNAMIC —
# its passthrough marker for uncacheable responses — rather than BYPASS)
curl -sI https://nabu-app.com/ | grep -i cache
# Expected: cache-control: no-store
#           cf-cache-status: DYNAMIC
```

### Verify per-IP rate limiting (after the trusted-proxy deploy, once only)

With `TRUSTED_PROXY_CIDRS` set, the auth limiter must key on real client IPs — not one shared tunnel bucket:

```bash
# 8 rapid login attempts from one machine: expect 401 x5, then 429s
for i in $(seq 1 8); do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X POST https://nabu-app.com/api/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"email":"nobody@example.com","password":"wrongpass"}'
done
# Expected: 401 401 401 401 401 429 429 429 (with Retry-After on the 429s)

# From a second client on a different network (e.g. phone on LTE), a login
# attempt must still return 401 while the first client is limited — that
# proves per-IP bucketing rather than a sitewide bucket.
```

Also spot-check request logs: the hashed `client` attribute should now vary between visitors instead of being one tunnel IP for everyone.

### Troubleshooting

- If `cf-cache-status` is `HIT` or `MISS` (not `BYPASS` for JS / `DYNAMIC` for HTML), the `no-store` header is not reaching Cloudflare — investigate `internal/app/server.go` and the CI build logs.
- If imports still show the old version number, the binary was not rebuilt with the new tag — check that `internal/version/version.go` is populated at build time via `-ldflags`.

## Known limitations (candidates for a future fix)

### iOS tests on release tags

**Fixed (2026-07-02, iOS v1 plan P1/D5):** the `changes` job in
`.github/workflows/ci.yaml` now forces the iOS lane on for `v*` tag pushes,
the same way `code` is forced, so iOS unit tests are a release gate. The
trade-off (accepted): iOS tests run on **every** release tag, including
server/web-only releases, costing ~1–2 min of macOS-runner time per deploy.

If a tag-time iOS failure looks unrelated to the release (e.g. a
simulator/runner infra flake), re-run the failed job; a genuine failure means
the tagged commit shipped an iOS regression — fix, re-tag, push.
