# Nabu — Mobile UI/UX Review & Improvement Plan

**Date:** 2026-07-01
**Reviewer:** Claude (Fable 5), commissioned via Claude Code
**Scope:** Mobile UI/UX of the PWA — interaction gaps, visual issues, stats enhancements, user-defined custom stats, quality-of-life features
**Commit reviewed:** `bca6c09` (main)
**Audience priorities (confirmed with owner):** Baby care tracking + household chores are co-primary. PWA first; each item carries an iOS-parity note. **No gamification** (no badges/challenges/confetti). Widget builder for custom stats is wanted **if it can be done securely**.

This is an implementation plan for a later Opus session. Items are grouped into phases; each finding cites the code it refers to. Phases 1–2 are polish/fixes with small blast radius; Phase 3 is the stats generalization; Phase 4 is the widget builder; Phase 5 is larger quality-of-life features.

---

## 0. What's already good (don't regress these)

- Touch ergonomics: 44–48px min tap targets, `touch-action: manipulation`, `:focus-visible` styles, `prefers-reduced-motion` support (`web/static/css/app.css:543-556`).
- Safe-area handling for iOS notch/home-indicator (`--safe-bottom`, `env(safe-area-inset-*)`, `app.css:21,110,3464`), including the recent standalone cold-open gap fix.
- Bottom-sheet pattern is consistent across log/edit/schedule flows, with backdrop + handle + Cancel.
- Log flow is genuinely fast: tap home card → sheet pre-filled with indicator defaults, cached volumes (`cachedIndicatorVolumes`), current time, self as member → one tap to Log. Undo toast after logging (`app.js:856 showToastWithUndo`).
- Stats sections are already user-reorderable/hideable with a canonical registry (`stats.js:7-50`, `internal/userprefs/sections.go`) — the foundation the widget builder can extend.
- Dark mode exists via CSS custom properties (`app.css:3009`), morphdom-style DOM updates preserve focus/scroll, SW offline caching + update toast, notification badging.

---

## 1. Phase 1 — Visual/correctness fixes (small, high confidence)

### 1.1 Dark-mode breaks in Stats charts and Home header
All SVG charts hard-code light-theme hex colors, so in dark mode gridlines glow and empty heatmap cells render as light tiles:

- Heatmap: empty-cell color `#e8e5df` and the GitHub-green ramp are hard-coded (`stats.js:334-341 heatmapColor`). On dark backgrounds the empty cell is a bright tile.
- Volume/indicator/scatter charts: gridlines `#e5e7eb`, axis `#d1d5db`, labels `#9ca3af`/`#6b7280` hard-coded (`stats.js:733,886,946,1047` etc.).
- Home Log/Manage segmented control: active tab is hard-coded `background:#fff`, and the container uses `var(--color-surface, #E8E2D6)` — a variable that **doesn't exist** (the app's token is `--surface`), so the fallback always wins in both themes (`app.css:3075-3095`).

**Fix:** introduce chart color tokens (`--chart-grid`, `--chart-axis`, `--chart-label`, `--heatmap-empty`, heatmap ramp steps) in `:root` + dark override, and reference them from the SVG builders (SVG accepts `fill="var(--chart-grid)"`). Replace `--color-surface`/`--color-text*` with the real tokens.
*iOS note: StatsView colors should come from asset-catalog semantic colors; verify parity.*

### 1.2 Hard-coded indicator colors keyed on exact label text
Chart stack colors are dictionaries keyed on literal strings `"🍼 formula"`, `"🤱 breast"`, `"💩 poo"`, `"💛 pee"` (`stats.js:892,1027`). Any user-customized label (the chore editor allows arbitrary labels, `chores.js:143-156`) falls through to gray, and two custom labels get the *same* gray, making stacked bars unreadable.

**Fix:** assign colors per label from a stable palette (hash of label → palette index), with the four known labels keeping their current colors for continuity. This also unblocks Phase 3 (generalized metrics for any chore).
*iOS note: same mapping function should be ported so charts match across clients.*

### 1.3 Heatmap tooltips don't work on touch
Heatmap cells only have `title` attributes (`stats.js:387`) — invisible on iOS/Android. The feeding-gaps scatter already solved this with `data-action="scatter-tap"` tap-to-reveal tooltips.

**Fix:** reuse the scatter's tap-tooltip pattern for heatmap cells (show `date · N chores` on tap; tap elsewhere dismisses). Also add `aria-label` per cell.

### 1.4 Inconsistent/hard-coded locale + date formatting
`toLocaleDateString("en-US", …)` is hard-coded in `today.js:26`, `stats.js:129,141`, history chunk labels (`today.js:366`), while other spots pass `undefined` (`stats.js:1150`). Week is computed Monday-start in `currentWeekLabel` (`stats.js:134-143`) but the heatmap grid is Sunday-start (`stats.js:353-374`).

**Fix:** drop the explicit `"en-US"` everywhere (use the device locale), and pick one week-start convention (recommend deriving from locale, or a single constant) used by heatmap, leaderboard ranges, and history chunks.

### 1.5 Volume unit is mL-only
Baby feeding volumes are mL end-to-end (inputs, charts, history rows: `today.js:326-327`, `stats.js` throughout). US caregivers think in oz.

**Fix:** per-user preference `volumeUnit: "ml" | "oz"` in `user_preferences` (same pattern as timezone). Store canonical mL in the DB; convert at render and at input (accept oz input, round to mL). One shared `formatVolume(ml, unit)` util.
*iOS note: needs the same pref surfaced in Settings and respected in HomeView/LogSheet/StatsView.*

### 1.6 Manifest polish
`manifest.webmanifest` is missing:
- `shortcuts` — long-press app icon → "Log feed", "Log chore", "Activity". Cheap and very high value for the baby use case (one gesture from home screen to the log sheet). Add `start_url` query params (e.g. `/?quicklog=feed-baby`) handled in `app.js` boot.
- `id` field (stable identity), `description`, and `screenshots` (better install sheet on Android).

---

## 2. Phase 2 — Interaction & ergonomics gaps

### 2.1 Offline logging queue (highest-value item in this phase)
The SW only caches **GET** requests (`service-worker.js:131-133`). A `POST /api/logs` on flaky reception (3am feed, walking the pram) fails with a toast and **the log is lost** — worst possible failure for the baby use case where the timestamp matters.

**Plan:**
- Queue failed/offline log mutations (POST/PATCH/DELETE on `/api/logs`) in IndexedDB with their intended `completedAt` (already captured at tap time, `schedule.js:544`).
- Replay on `online` event + app foreground; Background Sync where available (Chromium; iOS Safari lacks it, so the foreground replay path is the primary mechanism there).
- UI: mark queued-but-unsent logs in Today/Activity with a subtle "pending" state; toast "Saved — will sync when online".
- Server: logging is already idempotent per chore/day for simple logs; add a client-generated idempotency key on `POST /api/logs` to make replay safe for multi-log chores (feeds happen multiple times/day).
*iOS note: native app should get the same queue semantics via its stores; flag in parity matrix.*

### 2.2 "Time since last feed" glanceability
`formatTimeAgo` already puts "2h ago" on every home card (`home.js:80-85`) — good. But for the baby use case the single most-checked datum is *time since last feed/change*, and today it's one card among many with no prominence, and the Stats overview cards (Today / This Week / Day Streak / Top Chore, `stats.js:313-331`) don't include it.

**Plan:** add an optional **"Last done" overview stat** on the Stats page and (Phase 4) as a widget: per selected chore, big "3h 20m since 🍼 Feed Baby", tinted when the gap exceeds a user-set threshold (this is a *utility* alert, not gamification). Live-update the relative times on Home once a minute while visible (currently they only refresh on re-render).

### 2.3 Undo/confirm consistency
- Tap-to-log from **Today** view logs instantly with `showToastWithUndo` (good). Home-grid taps open the full sheet always. For simple chores with no indicators/volume/rating, consider **tap = instant log + undo toast** on Home too, with long-press (or a small ⋯) opening the sheet. This matches the "grandmother-fast" goal; the sheet remains for feed/change chores which need data.
- "Remove log" in the edit sheet (`schedule.js:533-537`) deletes with no confirm and no undo toast. Route it through the same undo-toast path.

### 2.4 History/Activity improvements
- **Infinite scroll**: replace/augment the "Load more" button (`today.js:250-252`) with an IntersectionObserver sentinel (keep the button as fallback). Filtered views already keep Load more visible — same logic drives auto-load.
- **Search**: no way to find "when did we last change the filter" — add a text search across note/title in the history endpoint (`GET /api/logs/history?q=`) with a debounced input next to the filter FAB.
- **Day summaries**: the day header (`today.js:345`) could carry a per-day count chip ("Tue, Jul 1 · 7") for free scanability.

### 2.5 Pull-to-refresh
In iOS standalone mode there's no browser refresh, and data refresh relies on the 30s notification poll + visibilitychange (`app.js:3216`). Add a lightweight pull-to-refresh on scrollable tab roots (overscroll gesture → refetch the active tab's data). CSS `overscroll-behavior` is already the hook point; implement with a small touch handler, honoring `prefers-reduced-motion`.

### 2.6 Notification actions
`notificationclick` only focuses/opens the app (`service-worker.js:112-129`). For chore reminders, add notification **action buttons**: "✓ Log now" (fires the log POST from the SW with the stored CSRF-exempt push token or deep-links to the pre-filled sheet) and "Snooze 30m". Deep-link payload should carry `choreId` so the app opens straight into the log sheet.
*iOS note: web push actions work on iOS 16.4+; native APNs actions are part of the (unbuilt) APNs plan.*

### 2.7 Small a11y/ergonomics list
- Star rating widget is `role="slider"` but has no keyboard handling (`schedule.js:490`); add arrow-key support or switch to 5 radio buttons visually styled as stars.
- Rating display `renderStarRatingDisplay` renders "4.5 ⭐" (`today.js:360-363`) — fine, but ensure `rating/10` half-star semantics are labeled in `aria-valuetext` (they are in the input; mirror in display `aria-label`).
- Haptic tick on successful log via `navigator.vibrate(10)` where supported (Android; harmless no-op on iOS).
- The feeding-gaps explainer (`stats.js:690-696`) is a dense paragraph; convert to a 3-row legend table with the colored dots inline.

---

## 3. Phase 3 — Generalized per-chore metrics (removes the "Baby" special case)

Today the rich analytics are hard-wired to two predefined chores (feed/change) via a dedicated `baby` section, `feeding-gaps` endpoint, and label-keyed colors. But the *data model already generalizes*: any chore can have indicator labels, `hasVolumeML`, `hasRating`, follow-ups (`internal/chore/store.go:8-26`). The stats layer is what's special-cased.

**Plan — make "metrics" a first-class chore concept:**

1. **Chore editor**: replace the implicit `hasVolumeML`/`hasRating` flags with an explicit "Track a value" picker per chore: `none | amount (unit: mL/oz/g/min/custom label) | rating | duration`. Existing flags migrate 1:1 (`hasVolumeML → amount(mL)`, `hasRating → rating`). Indicators stay as-is (they're already generic).
2. **Stats**: a per-chore analytics section is auto-available for **any** chore with a metric — time-series bar chart (reuse `renderVolumeChart` with unit label), indicator stacking (reuse `renderIndicatorChart` with Phase-1.2 palette), per-member split (reuse `renderMemberList`). The existing `GET /api/stats/chores/{id}/time-series` endpoint already serves most of this.
3. **Baby section becomes a saved configuration** of the generic machinery (two chore analytics columns + the gap scatter), not special code. Gap/cluster analysis (`feeding-gaps`) generalizes to "interval analysis" available for any chore where intervals matter (feeds, medication, watering plants) — parameterize the 2h threshold.
4. **Section registry**: per-chore sections get keys like `chore:<id>` appended to `STATS_SECTIONS` resolution (registry logic at `stats.js:35-50` and `internal/userprefs/sections.go` needs to accept the dynamic prefix; unknown-key dropping already handles deleted chores).

*iOS note: this is a schema-level change (chore metric config) — must land in the parity matrix and iOS `Models` before iOS ships stats.*

---

## 4. Phase 4 — User-defined stats: secure widget builder

Owner wants this **if secure**. It is, provided we build it as **declarative configuration, not expressions**:

### Security model (the important part)
- A widget is a **typed JSON document validated server-side against a closed schema** — no formulas, no user-supplied code, no free-text that ever renders unescaped:
  ```json
  {
    "type": "timeseries | total | last-done | interval | member-split | top-list",
    "choreIds": [12, 34],
    "metric": "count | amount | rating | duration",
    "agg": "sum | avg | min | max",
    "period": "day | week | month | all",
    "grain": "daily | weekly | monthly",
    "title": "Bottles this week"
  }
  ```
- Server validates: enum fields against allowlists; `choreIds` must belong to the caller's household (same ownership checks the stats handlers already do, e.g. `handlers/stats.go`); `title` length-capped and stored as data (always rendered through `escapeHTML`, per the project's existing XSS discipline).
- **No new query surface**: every widget type maps onto the existing stats endpoints (`/api/stats/chores/{id}/time-series`, `/leaderboard`, `/top-chores`, `/busy-hours`, latest-per-chore). The widget layer is a *presentation* layer; it cannot express a query the API doesn't already answer. This is what keeps it secure — there is no user-controlled SQL/aggregation path.
- Storage: `stats_widgets JSONB` on `user_preferences` (same migration pattern as `033_stats_section_prefs.sql`), size-capped (e.g. max 20 widgets, 4KB).

### UX
- "Customize Stats" panel (already exists, `stats.js:281-311`) gains an "+ Add widget" flow: bottom-sheet wizard — pick chore(s) → pick metric (only metrics that chore actually has) → pick presentation (big number / bar chart / list) → pick period → name it.
- Widgets appear in the section registry as `widget:<uuid>` keys, so reorder/hide/drag come for free from the existing customize panel.
- Rendering reuses the chart primitives from Phase 3 (tokenized colors from Phase 1.1).
- E2E: extend `security-escape.spec.js` discipline — a spec that creates a widget titled `<img src=x onerror=…>` and asserts it renders inert.

*iOS note: widget definitions are per-user server data, so iOS can render the same list; flag as a parity-matrix row from day one.*

### Stats worth adding as built-in widget types (no gamification)
- **Last done / time since** (per chore, with optional threshold tint) — the baby killer feature (see 2.2).
- **Interval distribution** (generalized feeding-gap): median/min/max gap for a chore over a period.
- **Rolling 7-day average** overlay on amount time-series (smooths noisy daily volumes).
- **Night vs day split** for a chore (counts/volume 10pm–6am vs day) — very useful for feeds.
- **Schedule adherence**: scheduled occurrences vs logged, per chore (plain utility, not a score).
- **Member split** for a specific chore over a period (exists for baby; generalize).
- **Neglected chores list**: chores whose last log is older than N days — actionable, calm, replaces any need for streak pressure.

---

## 5. Phase 5 — Bigger quality-of-life features (candidates, pick per appetite)

1. **CSV/export of logs** (date range, per chore) — pediatrician visits, spreadsheets. `GET /api/logs/export?start&end&choreId` returning CSV; button in Settings. Low effort, high trust value.
2. **Duration timer mode** (pairs with Phase 3 `duration` metric): "Start" on the log sheet records start time, persistent chip in the top bar while running, "Stop & log" completes with duration. Needed for breastfeeding/naps where duration matters more than count. Survives reload via localStorage.
3. **Amount steppers + presets** on the volume input: −10/+10 buttons and tappable recent values (last 3 distinct volumes). Data is already cached (`cachedIndicatorVolumes`); this removes the number-keyboard round-trip at 3am.
4. **Per-day notes / diary line** on Activity day headers (e.g. "first solid food!") — one text field per day, household-shared.
5. **Multi-baby / subject tagging**: if a household has twins, "Feed Baby" can't distinguish them today. Cheapest path: indicator labels per baby name; proper path: an optional `subject` field on chores. Decide before the widget builder bakes in per-chore assumptions.
6. **iOS Home-Screen widget + Live Activity** (native only): "time since last feed" widget; feeds directly off `GET /api/logs/latest-per-chore`. High value, native-only — belongs on the iOS roadmap after parity items.

---

## 6. Suggested implementation order

| Order | Item | Size | Risk |
|---|---|---|---|
| 1 | 1.1–1.4 dark mode/colors/tooltips/locale | S | Low |
| 2 | 1.5 mL/oz preference | S–M | Low |
| 3 | 1.6 manifest shortcuts | S | Low |
| 4 | 2.2 last-done stat + live "ago" refresh | S | Low |
| 5 | 2.3 undo consistency, 2.7 a11y list | S | Low |
| 6 | 2.1 offline log queue | M–L | Medium (idempotency) |
| 7 | 2.4 history search/infinite scroll, 2.5 PTR | M | Low |
| 8 | 2.6 notification actions | M | Medium (iOS push quirks) |
| 9 | Phase 3 generalized metrics | L | Medium (migration) |
| 10 | Phase 4 widget builder | L | Medium (schema validation) |
| 11 | Phase 5 picks (export → steppers → timer → …) | M each | Low–Medium |

Every phase that touches API/schema must update `docs/plans/client-parity.md` per the CI parity gate.
