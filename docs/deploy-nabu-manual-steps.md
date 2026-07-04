# CI/CD Pipeline — Manual Steps

These steps must be completed by hand before the automated pipeline
can run a full build and deploy.

## Phase 1 — Create Quay.io repository and robot account

1. Log in to https://quay.io
2. Create a new **public** repository: `HammerMeetNail/nabu`
   (namespace `dave`, repository name `nabu`)
3. Go to **Account Settings → Robot Accounts → Create Robot Account**
   Name it `nabu_ci`
4. Grant the `nabu_ci` robot **Write** permission on `HammerMeetNail/nabu`
5. Copy the robot account username (`dave+nabu_ci`) and token —
   you need these for Phase 3

## Phase 3 — Add GitHub repository secrets

In https://github.com/HammerMeetNail/nabu → **Settings → Secrets and
variables → Actions**, create the following secrets:

| Secret name          | Where to get the value |
|----------------------|------------------------|
| `SSH_PRIVATE_KEY`    | Content of `~/.ssh/hetzner_yearofbingo_ci` (full PEM, same key as yearofbingo) |
| `QUAY_USERNAME`      | Robot account username from Phase 1 (`dave+nabu_ci`) |
| `QUAY_PASSWORD`      | Robot account token from Phase 1 |
| `CODECOV_TOKEN`      | Add nabu at https://codecov.io and copy its upload token (optional — remove codecov steps from workflow if skipping) |
| `DB_PASSWORD`        | Must match the value already in `/opt/nabu/.env` on the server. If creating fresh: `openssl rand -base64 32` |
| `SMTP_HOST`          | Must match `/opt/nabu/.env` on the server |
| `SMTP_PORT`          | Must match `/opt/nabu/.env` on the server (typically 587) |
| `SMTP_USER`          | Must match `/opt/nabu/.env` on the server |
| `SMTP_PASS`          | Must match `/opt/nabu/.env` on the server |
| `SMTP_FROM`          | Must match `/opt/nabu/.env` on the server |
| `GOOGLE_CLIENT_ID`   | Must match `/opt/nabu/.env` on the server |
| `GOOGLE_CLIENT_SECRET` | Must match `/opt/nabu/.env` on the server |
| `APNS_AUTH_KEY_P8`   | **Base64 of the .p8 PEM** (single line — the deploy writes `.env` line-per-var, so the raw multiline PEM would break it; the server decodes base64 automatically). Optional until the Apple account exists — leave unset and APNs stays disabled |
| `APNS_KEY_ID`        | Key ID of the APNs auth key (Apple portal). Optional as above |
| `APNS_TEAM_ID`       | Apple developer team ID. Optional as above |
| `APNS_BUNDLE_ID`     | iOS bundle ID (`com.nabu.app`). Optional as above |
| `APPLE_CLIENT_IDS`   | Sign in with Apple audiences (the iOS bundle ID). Optional; unset disables native SIWA |
| `APPLE_WEB_CLIENT_ID`| Services ID for web SIWA (domain + `/api/auth/apple/web/callback` return URL registered in the portal). Optional; unset hides the PWA button |

## Phase 7 — Verify server can pull from Quay.io

Run from your local machine (after Phase 1 repo is created and public):

```bash
ssh -i ~/.ssh/hetzner_yearofbingo_ci \
    -o ProxyCommand="cloudflared access ssh --hostname ssh.yearofbingo.com" \
    deploy@ssh.yearofbingo.com \
    "podman pull quay.io/nabu/nabu:latest 2>&1 | tail -5"
```

If the repo is public, no credentials are needed. If it's private,
log in on the server:

```bash
podman login quay.io --username dave+nabu_ci --password <token>
```

## Phase 8 — Tag to trigger the first full deploy

After Phases 1–3 and 7 are complete:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The pipeline runs in order:
1. `changes` + `secrets` in parallel
2. `lint` + `test-go` + `test-js` (after `changes`)
3. `e2e` (after `test-go` + `test-js`)
4. `build-image` amd64 + arm64 in parallel (after all tests)
5. `scan-and-push` — Trivy scan + Cosign sign + manifest push
6. `release` + `deploy` in parallel (after `scan-and-push`)

Total wall time: ~8–15 minutes.

## Phase 9 — Verify the deployment

```bash
# App is live
curl -sf https://nabu-app.com/health

# yearofbingo is still healthy
curl -sf https://yearofbingo.com/health
```

On the server:

```bash
ssh -i ~/.ssh/hetzner_yearofbingo_ci \
    -o ProxyCommand="cloudflared access ssh --hostname ssh.yearofbingo.com" \
    deploy@ssh.yearofbingo.com \
    "podman ps --format 'table {{.Names}}\t{{.Status}}'"
```

## Going forward

Push a version tag to deploy:

```bash
git tag v1.2.3
git push origin v1.2.3
```

To re-deploy the current image (e.g. to rotate a secret) without a
code change: use the **workflow_dispatch** trigger in the GitHub
Actions UI. The deploy job will re-write `.env` with fresh secrets
and restart the stack.
