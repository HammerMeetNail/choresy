# P1 — Foundations

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). Read the index's
§2 decisions and the §2.1 governing rule (*behavior parity, presentation
nativeness*) before working here. Update the **Progress log** at the bottom
of this file as work lands, so later sessions can resume without re-deriving
state.

**Exit gate:** Models decode everything on `main`; account-delete + SIWA +
APNs endpoints live behind tests; app builds on semantic colors; iOS CI lane
runs on tag pushes.

The backend items (A1/A2/A3) have no iOS dependencies and no dependencies on
each other — they can land as independent PRs in any order.

---

## B1. iOS data-model catch-up (do first — everything else decodes through it)

One PR that brings `ios/Nabu/API/Models.swift` / `RequestModels.swift` up to
the current server schema, with decoding/encoding tests per field
(`ModelDecodingTests`, `RequestEncodingTests`):

| Model | New fields | Server source |
|-------|-----------|---------------|
| `Chore` | `metricType` (`none\|amount\|rating\|duration`), `metricUnit`, `subjects: [String]?` | migrations 036/039, `internal/chore/store.go` |
| `ChoreLog` | `durationSeconds: Int?`, `subject: String?` | migrations 036/039 |
| `CreateLogRequest` | `idempotencyKey`, `durationSeconds`, `subject` | migration 035, `today.js`/`offline-queue.js` |
| `Preferences` | `volumeUnit` (`ml\|oz`), `statsWidgets: [StatsWidget]` | migrations 034/037 |
| New: `StatsWidget` | closed enum schema: `type`, `choreIds`, `metric`, `agg`, `period`, `grain`, `title` | `internal/userprefs`, PWA `stats.js` wizard |
| New: `DayNote` | `date`, `note` | migration 038, `/api/day-notes` |
| New: `ChoreSummary` | period-scoped per-chore summary DTO | `GET /api/stats/chores/{id}/summary` |

Encoding rules that already bit us once (see `ios/AGENTS.md`): camelCase JSON
keys (`.useDefaultKeys`, never `.convertToSnakeCase`); fractional-seconds
RFC3339 dates; `decodeIfPresent(…) ?? []` for server fields that may be
`null`.

## A1. Account deletion backend — guideline 5.1.1(v)

Apps that support account creation **must** offer in-app account deletion.
Nothing exists today: no endpoint, no PWA UI, no iOS UI. P1 builds the
backend; client UI lands in P3 (Settings) — the matrix row stays **Not
built** until a client can reach it.

1. New endpoint, e.g. `DELETE /api/me` (auth-required, CSRF-protected,
   re-authentication or explicit typed confirmation in the request body).
2. Household rules, reusing the semantics that already exist for member
   removal and ownership transfer:
   - Sole owner of a household with other members → must transfer ownership
     first (client guides the user through the existing transfer flow).
   - Sole member of a household → household and its data are deleted with a
     clear warning.
   - Regular member → equivalent to leaving the household.
3. Cascade audit: sessions, magic-link/verification tokens, preferences,
   notification prefs, notifications, Web Push subscriptions, APNs device
   tokens (once A3 lands), chore-reminder prefs. Decide log attribution for
   departed users the same way remove-member already does — **follow the
   existing remove-member behavior; do not invent a new policy.**
4. All sessions invalidated immediately; the deleting client gets a clean
   logout.

**Tests:** handler tests for each household role path; store cascade tests.
Anti-target: deletion must not be reachable without re-confirmation.

## A2. Sign in with Apple backend — guideline 4.8

The app offers Google OAuth; 4.8 requires a privacy-preserving alternative
and Sign in with Apple is the safe interpretation. P1 builds the token
verification + user upsert; the iOS button lands in P5, the PWA button
whenever convenient before P7.

1. An `apple` identity provider alongside the existing Google flow — verify
   the identity token (JWKS from Apple, `aud`/`iss`/expiry checks), upsert
   the user by stable Apple `sub`, honor Apple's private-relay emails (they
   are real emails; no special-casing beyond normal verification rules).
2. Config in `.env.example` (client/App ID etc.); when unset, the provider
   is disabled the way Google is.
3. Duplicate-account behavior: same email arriving via Google and Apple →
   defined, tested, documented behavior.

**Tests:** token-verification unit tests with fixture JWKS; duplicate-account
linking test.

## A3. APNs backend

Execute the backend half of
[`docs/apns-implementation-plan.md`](../../apns-implementation-plan.md) — it
is accurate and already audited:

- Device-token migration + store (`RegisterDevice`, `UnregisterDevice`,
  `DevicesForUser`; memory + Postgres implementations).
- `POST /api/mobile/apns/register` / `POST /api/mobile/apns/unregister`
  (auth, CSRF, rate limiters), wired next to `/api/push/*`.
- ES256-JWT HTTP/2 sender (`api.push.apple.com` /
  `api.sandbox.push.apple.com` per stored environment), JWT cached < 1h,
  `apns-topic` = bundle ID; prune tokens on `410 Unregistered` /
  `BadDeviceToken`.
- Fan-out: the notification `PushSender` delivers to Web Push subscriptions
  (existing) **and** APNs device tokens (new), per user.
- Config (`APNS_AUTH_KEY_P8`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
  `APNS_BUNDLE_ID`, `APNS_ENVIRONMENT`) in `.env.example`; graceful no-op
  when unset (like the VAPID signer).

**Tests:** JWT construction + environment→host selection unit tests;
register/unregister + token pruning against the memory store; sender tests
against a fake APNs HTTP server. End-to-end verification needs a physical
device and Apple credentials — that is P5's gate, not P1's.

## C1. iOS design-token foundations

1. **Semantic colors in the asset catalog.** Replace `DesignColors`'
   hardcoded light/dark hex pairs with named colors in `Assets.xcassets`
   (any-appearance + dark + increased-contrast variants). Keep the brand
   hues — deep teal `#19323C`, ocean `#2E86AB`, amber `#F18F01`, warm paper
   `#F4EFE7` — as *tint/accent* roles; use `Color(.systemBackground)`,
   `.secondarySystemBackground`, `.separator` etc. for structure so the app
   inherits correct dark-mode, elevated-context, and high-contrast behavior
   for free.
2. **Typography = Dynamic Type text styles only.** No fixed point sizes.
   Audit for `.font(.system(size:))` and remove.
3. The app must still build and its unit lane pass; visual refinement is
   P6's job — P1 only moves the foundations.

## D5. CI fixes

- Fix the documented gap in `.github/workflows/ci.yaml`: force the iOS lane
  on tag pushes (`ios: ${{ startsWith(github.ref, 'refs/tags/v') || … }}`).
  Adds ~1–2 min of macOS-runner time per release tag — accepted, see
  `docs/deploy-runbook.md` "Known limitations".

---

## Progress log

Checklist (tick as items land on `main`; add dated notes below):

- [x] B1 model catch-up + decoding/encoding tests
- [x] A1 `DELETE /api/me` + role-path handler tests + cascade store tests
- [x] A2 Apple identity provider + JWKS verification tests
- [ ] A3 APNs store/routes/sender/fan-out + fake-server tests
- [ ] C1 asset-catalog semantic colors; fixed-size font audit
- [x] D5 iOS CI lane forced on tag pushes

### Notes

- **2026-07-02** — D5: iOS lane forced on `v*` tags in `ci.yaml`; runbook
  updated. B1: all migration-034–039 fields decode/encode
  (`ios/Nabu/API/Models.swift`, `RequestModels.swift`); NabuTests 164 green.
  A1: `DELETE /api/me` shipped — new `internal/account` service (sole-member
  household deleted, only-owner-with-members → 409 transfer-first, member =
  leave), `auth.Store.DeleteUser` (Postgres tx nulls `chores.created_by` and
  `chore_schedules.assigned_to_user_id`, revokes the user's invites, then
  deletes; everything else cascades), `household.Store.DeleteHousehold`.
  Caution for future callers: `users.household_id` cascades from households —
  deleting a household deletes users whose *active* household it is; only
  delete validated sole-member households. Client UI is P3.
- **2026-07-02** — A2: `POST /api/auth/apple/native` shipped —
  `internal/auth/apple.go` verifies RS256 identity tokens against Apple JWKS
  (iss/aud/exp checks, **nonce mandatory**, `email_verified` normalizes
  Apple's bool-or-"true" forms), `Service.LoginWithApple` mirrors the Google
  upsert exactly (keyed by email; same email links, marks verified).
  Config: `APPLE_CLIENT_IDS` (comma-separated audiences — bundle ID now,
  Services ID later); unset disables the endpoint (503). Web code-flow SIWA
  deliberately NOT built — decide button-vs-N/A for the PWA by P7. iOS
  button is P5.
