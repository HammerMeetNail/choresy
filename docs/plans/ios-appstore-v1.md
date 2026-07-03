# iOS App Store v1 — Parity & Polish Plan

**Status:** Active · **Drafted:** 2026-07-02 · **Owner decisions recorded:** 2026-07-02

This plan supersedes [`docs/plans/ios.md`](./ios.md) (the original conversion
plan, now archived — its phases 0–12 shipped and its remaining content is
folded in here). It is the roadmap from *"native app exists and mostly works"*
to *"approved on the App Store and genuinely beautiful."*

Companion documents:

- [`docs/plans/client-parity.md`](./client-parity.md) — the living feature
  matrix. **That file remains the source of truth for per-feature status**;
  this plan sequences the work.
- [`docs/apns-implementation-plan.md`](../apns-implementation-plan.md) — the
  APNs work breakdown, executed in Workstream A of this plan.
- [`ios/AGENTS.md`](../../ios/AGENTS.md) — agent rules for the iOS codebase.

---

## 1. Where we are (audited 2026-07-02)

The native SwiftUI app is real: ~45 Swift source files under `ios/Nabu/`,
11 unit/contract test files, one XCUITest file, an iOS CI lane, and a parity
matrix that was re-baselined against the code on 2026-06-28. Phases 0–12 of
the original conversion plan are **Built**. What stands between the current
app and an approved, lovely App Store release falls into four buckets:

| Bucket | Summary |
|--------|---------|
| **A. Admission blockers** | Things App Review will reject without: in-app **account deletion** (no backend endpoint exists at all), **Sign in with Apple** (we offer Google OAuth, which triggers guideline 4.8), working **push** (APNs is entirely unbuilt end-to-end), and complete privacy metadata. |
| **B. Parity gaps** | ~20 **iOS pending** rows in the matrix, created by recent PWA work: generalized metrics, custom stats widgets, duration timer, subject tagging, day notes, history search, CSV export, volume units, offline queue, and several stats sections. |
| **C. Beauty gaps** | The app pixel-copies PWA CSS. There is no pull-to-refresh, no haptics, no Swift Charts, almost no accessibility labels, sparse SF Symbols, and hardcoded hex colors instead of asset-catalog semantics. It works; it does not yet *feel like an iPhone app*. |
| **D. Confidence gaps** | Most matrix rows are **Built**, not **Done**: behavior is implemented but not proven by tests that run in CI. The iOS CI lane is path-filtered and is not a release gate on tag pushes (documented limitation in `.github/workflows/ci.yaml`). |

Workstreams A–D below map one-to-one onto these buckets; Workstream E covers
submission mechanics.

---

## 2. Product decisions for v1

Recorded from the owner on 2026-07-02:

| Question | Decision |
|----------|----------|
| Parity bar for v1 | **Full parity + polish.** Every **iOS pending** row in the matrix ships before submission. No "fast-follow" carve-outs for the big features. |
| Native push | **APNs ships in v1.** Reminders are core to a baby-tracking app; in-app-only notifications are not acceptable at launch. |
| Design direction | **Native-first with brand accents.** Embrace iOS idiom (system materials, SF Symbols, native lists/sheets, haptics, springs); keep the Nabu palette as the accent voice, not the literal skin. |
| This document | New plan; `docs/plans/ios.md` archived with a superseded banner. |

Standing decisions carried forward from the original plan (unchanged):

- Native SwiftUI, no WebView shell. The PWA remains a first-class client.
- Existing Go backend and JSON API; session-cookie + CSRF auth (no bearer
  tokens without a security review).
- Online-first with a lightweight read cache; **no offline writes beyond the
  idempotent log queue** described in §4 (which mirrors the PWA's shipped
  behavior exactly).
- Business authority stays on the server.

New defaults set by this plan (revisit only with an owner decision):

- **Minimum iOS: 17.0.** iPhone-first; the app may run scaled on iPad but
  iPad-optimized layout is out of scope for v1.
- **Charts move to Swift Charts** (see §5) rather than hand-drawn `Canvas`.

### 2.1 The governing rule: behavior parity, presentation nativeness

This supersedes the old "mimic the PWA unless the plan says otherwise" rule
in `ios/AGENTS.md`:

> **Behavioral semantics must match the PWA. Presentation must be native
> iOS.**
>
> *Behavioral semantics* — what requests are sent, the `slotHour` and
> `completedAt` invariants, validation rules, anti-enumeration copy, what
> data appears where, what an action does — are shared product behavior and
> must not diverge between clients without a parity-matrix entry.
>
> *Presentation* — colors, spacing, list styles, sheet chrome, animations,
> control types — should use iOS idiom. Do **not** pixel-copy CSS. A
> segmented `Picker` beats a hand-built pill bar; a `List` with swipe
> actions beats a custom card stack; `.searchable` beats a custom search
> field. If a PWA interaction has a more natural native counterpart
> (pull-to-refresh, context menu, swipe-to-delete), use the native one and
> record the mapping in the parity matrix's "Known differences" column.

---

## 3. Workstream A — App Store admission blockers

These are ordered first because each one is a **rejection**, not a nice-to-have,
and two of them (A1, A2) require backend work that other workstreams don't
depend on — start them immediately and in parallel.

### A1. In-app account deletion — guideline 5.1.1(v)

Apps that support account creation **must** offer in-app account deletion.
Nothing exists today: no endpoint, no PWA UI, no iOS UI.

**Backend** (design first — this touches ownership semantics):

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

**Clients:** Settings → Account gains a "Delete account" flow on **both**
clients (destructive styling, typed confirmation, owner-transfer guidance).
This is a new parity row — added to the matrix alongside this plan.

**Tests:** handler tests for each household role path; store cascade tests;
PWA E2E spec; iOS contract + UI test. Anti-target: deletion must not be
reachable without re-confirmation.

### A2. Sign in with Apple — guideline 4.8

The app offers Google OAuth. Guideline 4.8 requires apps using third-party
login to offer a privacy-preserving alternative; **Sign in with Apple is the
safe interpretation** and reviewers routinely enforce it.

1. **Backend:** an `apple` identity provider alongside the existing Google
   flow — verify the identity token (JWKS from Apple, `aud`/`iss`/expiry
   checks), upsert the user by stable Apple `sub`, honor Apple's
   private-relay emails (they are real emails; no special-casing beyond
   normal verification rules).
2. **iOS:** native `SignInWithAppleButton` / `ASAuthorizationController` on
   the login and register screens, styled per Apple's button rules (it must
   be at least as prominent as the Google button).
3. **PWA:** optional for guideline purposes (4.8 applies to the app), but
   add "Sign in with Apple" via Apple's web JS to keep the clients honest —
   or record an explicit N/A parity exception. Default: ship it on both.
4. **Entitlement:** add the Sign in with Apple capability to the app ID.

**Tests:** token-verification unit tests with fixture JWKS; duplicate-account
linking test (same email via Google and Apple → defined behavior, documented);
iOS UI test that the button renders on both auth screens.

### A3. APNs native push

Execute [`docs/apns-implementation-plan.md`](../apns-implementation-plan.md)
in full — it is accurate and already audited. Summary of its scope:
device-token store + migration, `/api/mobile/apns/register|unregister`
routes, ES256-JWT HTTP/2 sender with sandbox/production hosts and
`Unregistered`/`BadDeviceToken` pruning, fan-out from the existing
notification `PushSender`, graceful no-op when unconfigured, and the iOS
registration lifecycle (authorization prompt → `registerForRemoteNotifications`
→ register on login, unregister on logout).

This plan adds two items on top, so native notifications reach parity with
the PWA's reminder actions **in the same release**:

1. **Notification action categories.** The reminder push carries
   `choreId`/`type` (already true for web push). Register a
   `UNNotificationCategory` with:
   - **"Log now"** → deep-link into the app with the log sheet pre-filled
     for that chore (parity with the PWA's `/?quicklog=chore:<id>`).
   - **"Snooze 30m"** → background `POST /api/reminders/snooze` (endpoint
     already shipped for the PWA service worker).
2. **Permission pre-prompt.** Never fire the system permission dialog cold.
   Show a one-screen explanation ("Get reminded when it's time to feed…")
   with an explicit button; request authorization only on tap. This is both
   good UX and an App Review expectation.

**Verification:** the simulator cannot receive remote push — the release gate
is a **physical-device test**: register, trigger a schedule reminder, receive
it, exercise both actions, logout, confirm unregister.

### A4. Email verification in the native app

The last **iOS pending** auth row. The verify link (`GET
/api/auth/email/verify?...`) lands in the user's mail client, so the natural
native path is **universal links**:

1. Add an `applinks:` associated domain + AASA file served by the Go backend.
2. Handle the verify (and magic-link consume) URLs in `onOpenURL` /
   `NSUserActivity`, calling the same endpoints the PWA does.
3. Fallback path (works even without associated-domain setup): verification
   completes in the browser; the app refreshes `/api/me` on foreground and
   picks up the verified state. Ship the fallback regardless — it is also the
   behavior when the user opens the link on another device.
4. "Resend verification" action in Settings → Account (endpoint exists).

Universal links also improve invite links (`/join?code=…` opening straight
into the app) — wire both while the AASA plumbing is fresh.

### A5. Privacy & legal metadata

- **Privacy policy URL** — required in App Store Connect; host it on the
  product site and link it from the app's Settings.
- **App Privacy labels:** data collected — email address, name (optional),
  user content (household activity logs) — *linked to identity*, *not used
  for tracking*. No third-party analytics/ads SDKs exist; keep it that way
  for v1 so the label stays clean.
- **`ITSAppUsesNonExemptEncryption = NO`** in Info.plist (HTTPS-only is
  exempt) so TestFlight builds don't stall on export compliance.
- No `NSUserTrackingUsageDescription` — the app must not require ATT.
- **In-app**: Settings gains Privacy Policy and Support links (App Review
  checks that the URLs work and match).

---

## 4. Workstream B — Parity gap closure

Every row below is **iOS pending** in the matrix (or is a matrix gap this
plan fixes). Grouped so each group is one coherent PR-sized effort with its
tests. For each item: read the PWA module and spec listed in the matrix row
first; port behavior, not markup.

### B1. Data-model catch-up (do first — everything else decodes through it)

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

### B2. Logging surfaces

1. **Volume unit (mL/oz).** Port `formatVolume`/`volumeOptions` from
   `utils.js` into `Support/` (canonical storage in mL, conversion at
   display/input). Settings toggle; respected in LogSheet, history rows, and
   stats charts. Unit-test the round-trip against the JS cases.
2. **Metric config in the chore editor.** "Track a value" picker
   (`none | amount (+unit) | rating | duration`) replacing the implicit
   `hasVolumeML`/`hasRating` flags in `ChoreEditView` (flags stay in the
   request for server compat, mirroring the PWA's 1:1 migration).
3. **Duration timer.** For duration-metric chores the log sheet gains
   **Start timer**; a persistent elapsed-time chip stays visible across tabs
   (top-of-screen overlay, mirroring the PWA's top-bar chip); **Stop & log**
   completes with `durationSeconds`. Persist the running timer's start time
   in `UserDefaults` so it survives relaunch (parity with the PWA's
   localStorage behavior). *Native bonus (see B8): surface it as a Live
   Activity.*
4. **Subject tagging (multi-baby).** If the chore declares `subjects`, the
   log sheet shows a single-select subject chip row; history rows show the
   tag.
5. **Recent-value chips.** Last 3 distinct volumes as tappable chips above
   the volume picker (PWA Phase 5.3 — shipped there but **missing a matrix
   row**; row added with this plan).
6. **Offline log queue + idempotency.** Queue failed `POST /api/logs` bodies
   (with a client-generated `idempotencyKey`) in the app's store; replay on
   foreground and on connectivity restore (`NWPathMonitor`); show queued
   logs inline in Activity with a subtle non-tappable **pending** badge,
   reconciled on replay — exactly the PWA's shipped semantics. Unit-test
   replay, de-dup, and reconciliation against a mock server.

### B3. Activity

1. **History search.** `.searchable` on the history list → `GET
   /api/logs/history?q=` (flat, capped, newest-first — match the PWA's
   result presentation, not its markup).
2. **Per-day diary notes.** Day headers gain a note affordance (`GET
   /api/day-notes`, `PUT /api/day-notes/{date}`); edit sheet with 500-char
   cap; empty clears.
3. **Infinite scroll + day count chips.** Auto-load next page when the
   sentinel row appears (`onAppear` on the tail item); keep the Load-more
   button as fallback; per-day count chip in headers.
4. **Pull-to-refresh.** `.refreshable` on every tab's scroll view, refetching
   that tab's data (parity with the PWA's overscroll refresh; currently
   absent from the iOS app entirely).

### B4. Schedule

1. **For-date overlay.** The one pending schedule row: consume `GET
   /api/schedules/for-date` wherever the PWA's `schedule.js` uses it, so
   scheduled-occurrence context matches. Verify actual PWA call sites first
   and mirror them — do not invent a new surface for it.

### B5. Stats (the largest group — also where Swift Charts lands, see §5)

1. **Missing sections:** Breakdown, Streaks, Recap, Feeding gaps, Last done —
   each is one endpoint + one section view. Match the PWA's section registry
   semantics (`last-done` etc. as registry keys).
2. **Chart color tokens & label palette.** Port `colorForIndicator` (stable
   hash → palette, four baby labels pinned to historical colors) so custom
   labels get identical colors on both clients. Unit-test hash outputs
   against the JS cases.
3. **Generalized per-chore analytics.** Any chore with a metric or indicators
   gets an auto-available `chore:<id>` section (member split +
   metric-appropriate chart), reusing `time-series`; baby section becomes a
   saved configuration, not special code.
4. **Interval analysis.** `feeding-gaps?choreId=` generalization.
5. **Custom stats widgets.** Decode the server-validated `statsWidgets` list;
   render each type (`timeseries | total | last-done | interval |
   member-split | top-list`) via the existing endpoints (`summary` for
   total/member-split); per-card day/week/month toggle that re-scopes and
   persists, matching the PWA. Builder wizard in the customize panel
   (multi-select chores → presentation → value → name). Titles render as
   plain `Text` — never as attributed/markdown content.
6. **Period toggles convergence (#84/#85).** The PWA's categories/chores
   sections carry day/week/month toggles and send `?period=`; iOS's stats
   design diverged. Converge on the PWA's *semantics* (period scoping, what
   data each section shows) using native segmented controls; the visual
   treatment is free per §2.1.
7. **Customize panel.** Section reorder/hide (`statsSections` prefs) covering
   static keys, `chore:<id>`, and `widget:<uuid>` — required for widgets and
   generalized sections to be manageable.

### B6. Settings & data

1. **CSV export.** Settings action → `GET /api/logs/export?start&end&choreId`
   → native share sheet (`ShareLink`/`UIActivityViewController`) with a
   `.csv` file. Date-range + chore pickers matching the PWA's options.
2. **Account section** additions from Workstream A: delete account, resend
   verification, Sign in with Apple linkage state, privacy/support links.

### B7. Notification actions

Covered in A3 (Log-now and Snooze-30m APNs categories) — listed here because
they close the two pending **Schedule Reminders** matrix rows.

### B8. Native-only value (beyond parity)

These have no PWA counterpart; they are what makes the native app *better*
than the PWA on its home platform and materially help the guideline-4.2
"minimum functionality" impression:

1. **WidgetKit Home-Screen widget** — "time since last ⟨chore⟩" (small +
   medium), fed by `GET /api/logs/latest-per-chore` via a shared app-group
   cache refreshed on app foreground + timeline reloads. *(Matrix row
   exists: Phase 5.6.)*
2. **Live Activity** for the running duration timer (lock screen + Dynamic
   Island) — natural pairing with B2.3.
3. **Home-Screen quick actions** (`UIApplicationShortcutItem`): Log feed /
   Log chore / Activity — parity with the PWA's manifest shortcuts row.
4. *(Post-v1, explicitly out of scope: Siri/App Shortcuts, Apple Watch.)*

Items 1–3 are **in scope for v1** (they are small, high-visibility, and two
of them close existing matrix rows). If the schedule slips, the Live Activity
is the first to drop to v1.1 — the widget and quick actions stay.

---

## 5. Workstream C — Design & polish ("beautiful")

Direction (owner decision): **native-first, brand accents**. The Nabu
palette — deep teal `#19323C`, ocean `#2E86AB`, amber `#F18F01`, warm paper
`#F4EFE7` — is the *voice* of the app: accents, tints, charts, the app icon.
The *structure* is pure iOS: system backgrounds and materials, SF Symbols,
native lists and sheets, springy motion. Audited gaps this workstream closes:
zero haptics, zero `.refreshable`, hand-drawn charts, two files with
accessibility labels, hardcoded hex colors.

### C1. Foundations

1. **Semantic colors in the asset catalog.** Replace `DesignColors`'
   hardcoded light/dark hex pairs with named colors in `Assets.xcassets`
   (any-appearance + dark + increased-contrast variants). Keep the brand hues
   as *tint/accent* roles; use `Color(.systemBackground)`,
   `.secondarySystemBackground`, `.separator` etc. for structure so the app
   inherits correct dark-mode, elevated-context, and high-contrast behavior
   for free.
2. **Typography = Dynamic Type text styles only.** No fixed point sizes.
   Audit for `.font(.system(size:))` and remove.
3. **SF Symbols everywhere chrome needs an icon** (tab bar, list rows,
   toolbar, empty states) with `.symbolRenderingMode(.hierarchical)` and
   brand tint. Per-chore emoji remain — they are user content, not chrome.
4. **App icon + launch screen.** Icon designed on the brand palette with
   light/dark/tinted variants (iOS 18 appearance set); launch screen matches
   the initial screen's background so launch feels instant.

### C2. Structure & navigation

1. `NavigationStack` per tab with proper titles (large titles where the
   screen is a browsable list: Activity, Stats, Settings; inline for Home).
2. **Native sheets with detents** (`.presentationDetents([.medium, .large])`,
   drag indicator) for the log sheet, pick-chore, widget wizard, day-note
   editor.
3. **Lists get native affordances:** swipe-to-delete on logs/notifications,
   swipe actions for mark-read, context menus (long-press a home tile →
   Log…, Edit chore, Hide from Home; long-press a schedule row → Edit,
   Delete), confirmation dialogs for destructive actions.
4. Replace custom pill/segment controls with segmented `Picker`s unless a
   screen truly needs the custom look.

### C3. Motion & feel

1. **Haptics** via `.sensoryFeedback`: `.success` on log creation, `.impact`
   on undo and jiggle-mode entry, `.warning` on destructive confirms.
2. **Springs, not ease-in-out:** log-tile tap bounce, undo toast slide,
   jiggle wobble. Every animation respects **Reduce Motion** (fade
   fallbacks).
3. Home tile tap-through: scale + haptic + checkmark tick so a successful
   log *feels* logged before the toast appears.

### C4. State quality

Every screen ships all four states, reviewed in one pass:

| State | Standard |
|-------|----------|
| Loading | `.redacted(reason: .placeholder)` skeletons on real layout — no spinners on full screens. |
| Empty | Icon (SF Symbol), one-line explanation, one CTA (e.g. Stats before any logs → "Log your first chore" → Home). Use `ContentUnavailableView`. |
| Error | Inline retry with the decoded server message; never a dead screen. |
| Offline | Global banner + queued-log pending badges (B2.6); mutating buttons stay enabled only where the queue covers them (logs), disabled elsewhere with a toast. |

### C5. Screen-by-screen polish pass

A tracked checklist — one focused PR per screen, after C1–C4 land:

| Screen | Known polish targets |
|--------|---------------------|
| Auth/Onboarding | Native text-field focus states, `SignInWithAppleButton`, error presentation, keyboard avoidance, autofill hints (`.textContentType`). |
| Home | Grid spacing/tile hierarchy, jiggle-mode wobble + haptics, context menus, progress ring treatment, date navigation ergonomics. |
| Log sheet | Detents, When-picker native `DatePicker` (minute-preserving invariant!), chip layout, duration timer entry point, subject chips. |
| Activity | Native list + day headers with count chips and note affordance, search, infinite scroll, swipe actions, pending badges. |
| Schedule | Row hierarchy (icon/name/recurrence/assignee/time), amber done-state, native reschedule interaction, FAB → toolbar button. |
| Stats | **Swift Charts migration** — replace hand-drawn charts with `Chart` (bar/line/heatmap-style plots), brand-tinted, with `.chartXSelection` scrubbing where useful; widget cards; customize panel. |
| Settings | `Form`/grouped-list idiom, sections (Account / Household / Notifications / Data / About), destructive styling for delete/leave. |
| Notifications | Swipe actions, relative timestamps, unread treatment, pre-prompt screen. |

### C6. Accessibility (review-blocking, not optional)

1. VoiceOver labels/values/hints on every custom control — home tiles
   ("Feed Baby, last logged 25 minutes ago, button"), chart summaries via
   `accessibilityChartDescriptor`, jiggle-mode actions exposed as custom
   actions.
2. **Dynamic Type through accessibility sizes** — grid reflows, no clipped
   text; audit at `AX3`.
3. Hit targets ≥ 44 pt; contrast ≥ 4.5:1 for text (re-check brand amber on
   paper).
4. Reduce Motion / Reduce Transparency / Increase Contrast honored (falls
   out of C1/C3 if done there).
5. Xcode Accessibility Inspector audit + one XCUITest running at an
   accessibility content size as a smoke gate.

---

## 6. Workstream D — Test & CI hardening

The matrix legend says **Built → Done requires CI-run coverage**. v1 ships
when the everyday paths are **Done**, not Built.

1. **Contract tests for every new endpoint touched by this plan** (account
   delete, SIWA, APNs register/unregister, day-notes, export, summary,
   snooze) in `APIContractTests` against the mock server, plus the
   local-Go-server mode for CSRF/cookie behavior.
2. **Ported unit cases from JS:** `colorForIndicator` hash outputs, volume
   conversion, widget-schema decoding, duration/idempotency request
   construction. (Recurrence is already ported — keep both suites in sync.)
3. **XCUITest coverage for the critical flows** (the real gate for Built →
   Done): auth + onboarding, home direct log + undo, log sheet with When
   picker, history search/filter, schedule create/edit, household switch,
   notification prefs, stats render + customize, account deletion, and the
   offline queue (airplane-mode simulation via mock). Grow
   `NabuUITests.swift` into per-flow files; keep edge cases in unit tests —
   XCUITest is for flows.
4. **Snapshot tests:** adopt `swift-snapshot-testing` for the design system
   and the four C4 states of each screen (light/dark × two Dynamic Type
   sizes). This is what keeps "beautiful" from regressing.
5. **CI:**
   - Fix the documented gap: force the iOS lane on tag pushes
     (`ios: ${{ startsWith(github.ref, 'refs/tags/v') || … }}`).
   - iOS lane runs unit + contract on every `ios/**` PR; UI/snapshot suite
     at minimum nightly and on release branches (macOS-minute budget).
   - Parity-matrix lint (`scripts/check-parity.sh`) already gates PRs —
     unchanged.
6. **Physical-device checklist** (release gate, manual): APNs end-to-end
   (A3), universal links, Dynamic Type sweep, VoiceOver smoke, widget
   timeline refresh, Live Activity.

---

## 7. Workstream E — Submission mechanics

1. **Apple developer setup:** bundle ID registered with Push Notifications,
   Sign in with Apple, Associated Domains, App Groups (widget) capabilities;
   APNs `.p8` key provisioned and injected into the deploy environment per
   the APNs plan's config section.
2. **TestFlight:** internal testing from the first A-workstream build;
   external beta once Workstream B closes, with the physical-device
   checklist run on every release candidate.
3. **App Store Connect metadata:**
   - Name, subtitle, description, keywords; category **Lifestyle** (or
     **Health & Fitness** — decide at submission; baby-tracking apps appear
     in both); age rating 4+.
   - **Screenshots** for 6.9″ and 6.5″ classes, taken from the polished app
     with a seeded demo household (light + dark). Screenshots are the first
     thing review and users see — do them after C5, not before.
   - Privacy labels + privacy policy URL (A5), support URL.
   - **Review notes:** demo account credentials on a production household
     seeded with realistic data; one paragraph explaining the household
     model; note that push requires the demo account's reminders (reviewers
     often test push).
4. **Review-risk register** (what a rejection would cite, and our answer):

   | Guideline | Risk | Mitigation in this plan |
   |-----------|------|------------------------|
   | 4.2 minimum functionality / web-port feel | Medium today | Native-first design (C), widget + quick actions + Live Activity (B8), haptics/motion (C3) |
   | 5.1.1(v) account deletion | **Certain rejection today** | A1 |
   | 4.8 login services | High (Google OAuth present) | A2 |
   | 2.1 completeness (dead/empty screens, broken states) | Medium | C4 state pass + snapshot tests |
   | 5.1.1 permission requests | Low-medium | A3 pre-prompt; request only on user intent |
   | 2.3 accurate metadata/screenshots | Low | E3 after polish |

---

## 8. Sequencing

Backend work (A1/A2/A3 server side) has no iOS dependencies — run it as a
parallel track from day one. Phase gates are hard: tests green (`make
test-go`, `make test-js`, `make e2e`, iOS lane) and the parity matrix updated
before the next phase starts.

| Phase | Contents | Exit gate |
|-------|----------|-----------|
| **P1 Foundations** | B1 model catch-up · A1/A2/A3 backend track · C1 design tokens/colors/typography · D5 CI fixes | Models decode everything on `main`; account-delete + SIWA + APNs endpoints live behind tests; app builds on semantic colors |
| **P2 Logging parity** | B2 (volume unit, metric config, duration timer, subjects, recent chips, offline queue) · C2 sheets/detents for the log sheet | All B2 matrix rows Built with unit/contract tests; log-sheet UI tests pass |
| **P3 Activity + Schedule + Settings parity** | B3, B4, B6 · C2 list affordances | Rows Built; search/notes/export UI tests pass |
| **P4 Stats parity** | B5 (+ Swift Charts migration from C5) | All stats rows Built; snapshot tests for every chart state |
| **P5 Push + auth completion** | A3 iOS client + actions, A4 universal links + email verification, A2 iOS button | Physical-device APNs test passed; auth rows Done |
| **P6 Beauty pass** | C3–C6 screen-by-screen · B8 widget/quick actions/Live Activity · A5 privacy | Accessibility audit clean; snapshot suite green; screenshots taken |
| **P7 Release** | D6 device checklist · E TestFlight external → submission | Every matrix row **Done** or an owner-signed exception; App Review submitted |

Rough sizing: P1 and P4 are the large phases (L); P2/P3/P5/P6 are M; P7 is S
plus review latency. The critical path is P1 → P2 → … → P7; the backend
track and C1 shorten it by starting inside P1.

---

## 9. Risks

| Risk | Mitigation |
|------|------------|
| APNs unverifiable until Apple credentials + physical device exist | Provision the developer account in P1, not P5; backend sender is testable with a fake APNs server meanwhile |
| Account-deletion cascade subtleties (owner households, log attribution) | Reuse existing remove-member/transfer semantics; audit FKs before writing the handler; owner sign-off on the chosen behavior |
| "Full parity" scope creep — the PWA keeps moving while we build | The CI parity gate already forces matrix rows for new PWA work; new rows land in the phase backlog, and P7's gate is *matrix-driven*, not list-driven |
| Swift Charts can't reproduce a PWA chart exactly | §2.1 allows presentation divergence; document per-chart differences in the matrix; keep data/semantics identical |
| Widget-builder rendering of user titles | Render titles only as SwiftUI `Text` (never attributed/markdown); port the PWA's XSS spec intent into a snapshot test with a hostile title |
| XCUITest suite runtime balloons | Flows only in XCUITest; edge cases stay unit/contract; UI suite nightly + release, unit lane on every PR |
| Cookie/CSRF quirks resurface with new endpoints | Every new endpoint gets a contract test in the local-Go-server mode before its UI is built |
| App Review surprises beyond the register in §7.4 | External TestFlight beta first; review notes with demo account; respond-and-resubmit budgeted into P7 |

---

## 10. Definition of Done — v1 submission

Submit to App Review only when **all** of the following hold:

1. Every row in `docs/plans/client-parity.md` is **Done**, **N/A**, or
   **Deferred with an owner-signed justification** — zero **iOS pending**,
   zero **Not built**.
2. Account deletion, Sign in with Apple, and APNs push (with Log-now and
   Snooze actions) work end-to-end — APNs proven on a physical device in
   both sandbox and production.
3. The app uses semantic colors, Dynamic Type styles, SF Symbols, native
   sheets/lists, haptics, and Swift Charts; the accessibility audit and the
   AX-size XCUITest pass; every screen has designed loading/empty/error/
   offline states.
4. iOS unit, contract, snapshot, and UI suites are green in CI; the iOS lane
   runs on tag pushes; `make test-go`, `make test-js`, and `make e2e` remain
   green (the PWA lost nothing).
5. Widget and Home-Screen quick actions ship; Live Activity ships or is an
   explicitly deferred v1.1 item.
6. App Store Connect is complete: icon set, screenshots from the polished
   build, privacy labels, privacy-policy and support URLs, review notes with
   a seeded demo account.
7. The physical-device release checklist (D6) is signed off on a TestFlight
   build of the release candidate.
