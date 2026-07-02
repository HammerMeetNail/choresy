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

# Confirm correct version in the index page
curl -s https://nabu-app.com/ | grep 'app.js'
# Expected: src="/static/js/app.js?v=0.1.X"
```

### Troubleshooting

- If `cf-cache-status` is `HIT` or `MISS` (not `BYPASS`), the `no-store` header is not reaching Cloudflare — investigate `internal/app/server.go` and the CI build logs.
- If imports still show the old version number, the binary was not rebuilt with the new tag — check that `internal/version/version.go` is populated at build time via `-ldflags`.

## Known limitations (candidates for a future fix)

### iOS tests are skipped on release tags

**Symptom:** on a `v*` tag push (i.e. every deploy), the **iOS Unit Tests** job shows `skipped`, even when the tagged commit changed `ios/**`.

**Cause:** the `changes` (Detect Changes) job uses `dorny/paths-filter`, which needs a base ref to diff against. On a tag push there is no meaningful base, so `steps.filter.outputs.ios` returns `false` and the iOS job's `if: needs.changes.outputs.ios == 'true'` gate skips it. The `code` output dodges this by being forced `true` on tags; `ios` is not.

**Impact:** iOS tests are **not a release gate** today. This does not affect the deploy itself — the pipeline builds/ships only the server + web image, and the iOS app ships separately via the App Store. But an iOS regression can land on a release tag without CI catching it. Until fixed, **run the iOS suite locally before tagging** when a change touches `ios/**`:

```bash
cd ios
DEST="platform=iOS Simulator,id=$(xcrun simctl list devices available -j | jq -r '.devices|to_entries[]|.value[]|select(.name|test("iPhone"))|.udid' | head -1)"
xcodebuild build -project Nabu.xcodeproj -scheme Nabu -destination "$DEST"
xcodebuild build-for-testing -project Nabu.xcodeproj -scheme Nabu -destination "$DEST"
xcodebuild test-without-building -project Nabu.xcodeproj -scheme Nabu -destination "$DEST" -only-testing:NabuTests
```

**Fix:** force iOS on for tag pushes in `.github/workflows/ci.yaml` (`changes` job outputs), mirroring `code`:

```yaml
ios: ${{ startsWith(github.ref, 'refs/tags/v') || steps.filter.outputs.ios }}
```

Trade-off: this runs iOS tests on **every** release tag, including server/web-only releases, costing ~1–2 min of macOS-runner time per deploy. Acceptable for a real release gate, but decide deliberately (a PR-time iOS run already covers most changes; PRs get a real base ref, so the filter works there).
