# P6 — Beauty pass

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). Direction (owner
decision): **native-first, brand accents** — the Nabu palette is the app's
*voice* (accents, tints, charts, icon); the *structure* is pure iOS. C1
foundations (semantic colors, Dynamic Type) landed in P1; this phase is the
visible polish. Update the **Progress log** below as work lands.

**Exit gate:** Accessibility audit clean; snapshot suite green; screenshots
taken.

---

## C3. Motion & feel

1. **Haptics** via `.sensoryFeedback`: `.success` on log creation, `.impact`
   on undo and jiggle-mode entry, `.warning` on destructive confirms.
2. **Springs, not ease-in-out:** log-tile tap bounce, undo toast slide,
   jiggle wobble. Every animation respects **Reduce Motion** (fade
   fallbacks).
3. Home tile tap-through: scale + haptic + checkmark tick so a successful
   log *feels* logged before the toast appears.

## C4. State quality

Every screen ships all four states, reviewed in one pass:

| State | Standard |
|-------|----------|
| Loading | `.redacted(reason: .placeholder)` skeletons on real layout — no spinners on full screens. |
| Empty | Icon (SF Symbol), one-line explanation, one CTA (e.g. Stats before any logs → "Log your first chore" → Home). Use `ContentUnavailableView`. |
| Error | Inline retry with the decoded server message; never a dead screen. |
| Offline | Global banner + queued-log pending badges (P2); mutating buttons stay enabled only where the queue covers them (logs), disabled elsewhere with a toast. |

## C5. Screen-by-screen polish pass

One focused PR per screen:

| Screen | Known polish targets |
|--------|---------------------|
| Auth/Onboarding | Native text-field focus states, `SignInWithAppleButton`, error presentation, keyboard avoidance, autofill hints (`.textContentType`). |
| Home | Grid spacing/tile hierarchy, jiggle-mode wobble + haptics, context menus, progress ring treatment, date navigation ergonomics. |
| Log sheet | Detents, When-picker native `DatePicker` (minute-preserving invariant!), chip layout, duration timer entry point, subject chips. |
| Activity | Native list + day headers with count chips and note affordance, search, infinite scroll, swipe actions, pending badges. |
| Schedule | Row hierarchy (icon/name/recurrence/assignee/time), amber done-state, native reschedule interaction, FAB → toolbar button. |
| Stats | Widget cards; customize panel; chart scrubbing polish (charts themselves migrated in P4). |
| Settings | `Form`/grouped-list idiom, sections (Account / Household / Notifications / Data / About), destructive styling for delete/leave. |
| Notifications | Swipe actions, relative timestamps, unread treatment, pre-prompt screen. |

Also from C1/C2 if not already landed: `NavigationStack` titles (large for
Activity/Stats/Settings, inline for Home), SF Symbols with
`.symbolRenderingMode(.hierarchical)` in all chrome (per-chore emoji remain —
user content, not chrome), app icon with light/dark/tinted variants (iOS 18
appearance set), launch screen matching the initial screen's background.

## C6. Accessibility (review-blocking, not optional)

1. VoiceOver labels/values/hints on every custom control — home tiles
   ("Feed Baby, last logged 25 minutes ago, button"), chart summaries via
   `accessibilityChartDescriptor`, jiggle-mode actions exposed as custom
   actions.
2. **Dynamic Type through accessibility sizes** — grid reflows, no clipped
   text; audit at `AX3`.
3. Hit targets ≥ 44 pt; contrast ≥ 4.5:1 for text (re-check brand amber on
   paper).
4. Reduce Motion / Reduce Transparency / Increase Contrast honored.
5. Xcode Accessibility Inspector audit + one XCUITest running at an
   accessibility content size as a smoke gate.

## B8. Native-only value (beyond parity)

What makes the native app *better* than the PWA on its home platform —
materially helps the guideline-4.2 impression:

1. **WidgetKit Home-Screen widget** — "time since last ⟨chore⟩" (small +
   medium), fed by `GET /api/logs/latest-per-chore` via a shared app-group
   cache refreshed on app foreground + timeline reloads.
2. **Live Activity** for the running duration timer (lock screen + Dynamic
   Island). *First to drop to v1.1 if the schedule slips; widget and quick
   actions stay.*
3. **Home-Screen quick actions** (`UIApplicationShortcutItem`): Log feed /
   Log chore / Activity — parity with the PWA's manifest shortcuts row.
4. *(Post-v1, explicitly out of scope: Siri/App Shortcuts, Apple Watch.)*

## A5. Privacy & legal metadata

- **Privacy policy URL** — required in App Store Connect; host it and link
  it from the app's Settings (with a working Support URL).
- **App Privacy labels:** data collected — email address, name (optional),
  user content (household activity logs) — *linked to identity*, *not used
  for tracking*. No third-party analytics/ads SDKs; keep it that way for v1.
- **`ITSAppUsesNonExemptEncryption = NO`** in Info.plist (HTTPS-only is
  exempt) so TestFlight builds don't stall.
- No `NSUserTrackingUsageDescription` — the app must not require ATT.

---

## Progress log

- [x] Haptics + spring motion + Reduce Motion fallbacks
- [x] Four-state pass (loading/empty/error/offline) on every screen
- [x] Screen polish PRs: Auth · Home · Log sheet · Activity · Schedule · Stats · Settings · Notifications — targeted pass, see notes
- [x] App icon (light/dark/tinted) + launch screen
- [x] Accessibility: labels, AX3 sweep, contrast, automated audit (green + regression-gated), AX-size XCUITest
- [x] WidgetKit widget · quick actions · Live Activity (**explicit v1.1 deferral — owner sign-off requested**)
- [x] A5 privacy metadata + Settings links
- [x] Snapshot suite covering C4 states (light/dark × AX type size)
- [x] Matrix rows updated
- [ ] Marketing screenshots (6.9″/6.5″, seeded demo household, light+dark) — **owner** (needs demo data + final review; exit-gate item shared with P7 metadata)

### Notes

**2026-07-04 — P6 code complete; marketing screenshots owner-gated.**
Landed across five commits (C3+C4, C5, C6, B8, A5), all suites green
(`NabuTests` incl. new snapshot suites, all four local `NabuUITests`
classes, `make test-go`, `make test-js`, `make e2e` 306 passing):

- *C3*: `Motion` spring helpers (collapse under Reduce Motion /
  `-disableAnimations`); tile tap bounce + jiggle wobble; toast spring
  slide; haptics — success on log, impact on undo/jiggle, warning on
  delete-account and leave-household confirms. Leave Household also gained
  the PWA's confirmation dialog (was a real parity gap).
- *C4*: `SkeletonScreen`/`SkeletonCards` (redacted layouts, no full-screen
  spinners), `ContentUnavailableView` empties with a single CTA per screen,
  Stats inline error retry, global offline banner off the existing
  `NWPathMonitor`. `StateQualitySnapshotTests` covers light/dark + AX1.
- *C5*: Activity → large title; hierarchical chrome symbols; Settings
  reordered Account → Household → Notifications → Data (+ About in A5);
  single-size app icon with generated dark and tinted (grayscale)
  variants; launch screen = `PaperBackground`. Most C5 table items were
  already native from P2–P5 (detents, `.searchable`, swipe actions,
  toolbar add button).
- *C6*: driven by `performAccessibilityAudit` in a new
  `NabuAccessibilityUITests` (kept as a regression gate). Real fixes:
  **BrandPrimary light deepened `#2E86AB` → `#236886`** (old value was
  4.11:1 on white, below the 4.5:1 floor; new is 6.18:1 — snapshots
  re-recorded), pill tab bar rebuilt with true ≥44pt hit targets, tile
  timestamps footnote @ 75% primary (secondaryLabel fails 4.5:1), emoji
  scale with Dynamic Type capped at AX1, chore names wrap at AX sizes,
  VoiceOver custom actions on tiles, chart summary labels. In-code
  exemptions (documented): emoji-only elements; one pixel-verified checker
  artifact on the pill text.
- *B8*: `NabuWidgets` extension — "Last Logged" small+medium widget off an
  app-group snapshot (`group.com.nabu.app`) refreshed with
  latest-per-chore; taps deep-link via `?quicklog=chore:<id>`. Quick
  actions Log Feed / Log Chore / Activity = the PWA manifest shortcuts;
  `DeepLink` now parses all four `?quicklog=` forms. **Live Activity
  deferred to v1.1** (plan-sanctioned; owner sign-off requested).
- *A5*: `/privacy` + `/support` pages served by the Go backend (tested);
  Settings → About links them + version; `ITSAppUsesNonExemptEncryption=NO`.
  App Privacy labels themselves are entered in App Store Connect (owner).
- *Also*: pre-existing broken UI test fixed (`volume-picker` identifier
  was lost in the P2 metrics rework; restored on the shared picker), CSRF
  unit test made hermetic.
- *Owner-gated*: marketing screenshots; App Store Connect privacy labels;
  app group registration on the App ID (widget on device); Live Activity
  deferral sign-off.
