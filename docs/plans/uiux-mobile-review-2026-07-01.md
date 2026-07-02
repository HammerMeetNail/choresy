# Nabu — Mobile UI/UX Review & Improvement Plan (outstanding work)

**Original review date:** 2026-07-01 · **Trimmed:** 2026-07-02
**Scope:** Mobile UI/UX of the PWA — remaining stats generalization, custom-stat widget builder, and quality-of-life features.
**Audience priorities:** Baby care tracking + household chores are co-primary. PWA first; each item carries an iOS-parity note. **No gamification** (no badges/challenges/confetti). Widget builder for custom stats is wanted **if it can be done securely**.

> This document has been trimmed to the **outstanding** items only. Phases 1
> and 2 (visual/correctness fixes and interaction/ergonomics gaps) and Phase 5.1
> (CSV export) are implemented, tested, and shipped — see git history and
> `docs/plans/client-parity.md` for what landed.
>
> **Update (branch `feat/uiux-mobile-review-phases`):** Phase 3 (generalized
> metrics), Phase 4 (secure widget builder), Phase 5.2 (duration timer), 5.3
> (recent-value chips), 5.4 (per-day notes), 5.5 (subject tagging), and the
> carry-overs 2.1 (offline pending badge) and 2.6 (snooze endpoint + SW action)
> are now implemented and tested on the PWA/backend (migrations 036–039). Phase
> 5.6 (iOS Home-Screen widget) is native-only and remains on the iOS roadmap.
> Each shipped item has iOS-parity rows in `docs/plans/client-parity.md`.

---

## 0. Carry-over deferrals (small, from the shipped phases)

- **Inline "pending" state for offline-queued logs** (was 2.1): the offline log
  queue (`offline-queue.js`) reliably queues and replays logs, but a
  queued-but-unsent log is not yet shown inline in Today/Activity with a
  subtle "pending" badge. The log is safe and appears on sync; this is a
  purely visual nicety. Would require synthesizing a placeholder log in state
  and reconciling it on replay.
- **"Snooze 30m" notification action** (was 2.6): the "✓ Log now" web-push
  action ships and deep-links to the pre-filled sheet. A real snooze needs a
  **server-side reminder reschedule endpoint** (re-emit the reminder in 30
  min, idempotently) — build that before adding the SW action button.

---

## 3. Phase 3 — Generalized per-chore metrics (removes the "Baby" special case)

Today the rich analytics are hard-wired to two predefined chores (feed/change) via a dedicated `baby` section, `feeding-gaps` endpoint, and label-keyed colors. But the *data model already generalizes*: any chore can have indicator labels, `hasVolumeML`, `hasRating`, follow-ups (`internal/chore/store.go:8-26`). The stats layer is what's special-cased. (Note: label→color is now already generalized via `colorForIndicator` in `stats.js`, shipped in Phase 1.2 — Phase 3 can build on it.)

**Plan — make "metrics" a first-class chore concept:**

1. **Chore editor**: replace the implicit `hasVolumeML`/`hasRating` flags with an explicit "Track a value" picker per chore: `none | amount (unit: mL/oz/g/min/custom label) | rating | duration`. Existing flags migrate 1:1 (`hasVolumeML → amount(mL)`, `hasRating → rating`). Indicators stay as-is (they're already generic). The mL/oz preference (shipped Phase 1.5, `utils.js` `formatVolume`/`volumeOptions`) should be reused for the `amount` unit rendering.
2. **Stats**: a per-chore analytics section is auto-available for **any** chore with a metric — time-series bar chart (reuse `renderVolumeChart` with unit label), indicator stacking (reuse `renderIndicatorChart` with the `colorForIndicator` palette), per-member split (reuse `renderMemberList`). The existing `GET /api/stats/chores/{id}/time-series` endpoint already serves most of this.
3. **Baby section becomes a saved configuration** of the generic machinery (two chore analytics columns + the gap scatter), not special code. Gap/cluster analysis (`feeding-gaps`) generalizes to "interval analysis" available for any chore where intervals matter (feeds, medication, watering plants) — parameterize the 2h threshold.
4. **Section registry**: per-chore sections get keys like `chore:<id>` appended to `STATS_SECTIONS` resolution (registry logic at `stats.js` `resolveStatsLayout` and `internal/userprefs/sections.go` needs to accept the dynamic prefix; unknown-key dropping already handles deleted chores). Note the registry now also contains the shipped `last-done` section — keep both static and dynamic keys working.

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
- Storage: `stats_widgets JSONB` on `user_preferences` (same migration pattern as `033_stats_section_prefs.sql` / the shipped `034`/`035`), size-capped (e.g. max 20 widgets, 4KB).

### UX
- "Customize Stats" panel (already exists, `stats.js`) gains an "+ Add widget" flow: bottom-sheet wizard — pick chore(s) → pick metric (only metrics that chore actually has) → pick presentation (big number / bar chart / list) → pick period → name it.
- Widgets appear in the section registry as `widget:<uuid>` keys, so reorder/hide/drag come for free from the existing customize panel.
- Rendering reuses the chart primitives from Phase 3 (tokenized colors from the shipped Phase 1.1 `--chart-*` tokens).
- E2E: extend `security-escape.spec.js` discipline — a spec that creates a widget titled `<img src=x onerror=…>` and asserts it renders inert.

*iOS note: widget definitions are per-user server data, so iOS can render the same list; flag as a parity-matrix row from day one.*

### Stats worth adding as built-in widget types (no gamification)
- **Last done / time since** (per chore, with optional threshold tint) — a basic `last-done` **section** already ships (see git history); the widget version adds per-chore selection + threshold tint.
- **Interval distribution** (generalized feeding-gap): median/min/max gap for a chore over a period.
- **Rolling 7-day average** overlay on amount time-series (smooths noisy daily volumes).
- **Night vs day split** for a chore (counts/volume 10pm–6am vs day) — very useful for feeds.
- **Schedule adherence**: scheduled occurrences vs logged, per chore (plain utility, not a score).
- **Member split** for a specific chore over a period (exists for baby; generalize).
- **Neglected chores list**: chores whose last log is older than N days — actionable, calm, replaces any need for streak pressure.

---

## 5. Phase 5 — Bigger quality-of-life features (candidates, pick per appetite)

*(5.1 CSV export shipped — see git history.)*

2. **Duration timer mode** (pairs with Phase 3 `duration` metric): "Start" on the log sheet records start time, persistent chip in the top bar while running, "Stop & log" completes with duration. Needed for breastfeeding/naps where duration matters more than count. Survives reload via localStorage.
3. **Amount steppers + presets** on the volume input: −10/+10 buttons and tappable recent values (last 3 distinct volumes). Note the current volume input is already a tap-friendly preset dropdown (`renderIndicatorVolumeRow`, unit-aware via `volumeOptions`), so scope this to the "recent values" chips + optional steppers; the number-keyboard round-trip the original review assumed no longer applies.
4. **Per-day notes / diary line** on Activity day headers (e.g. "first solid food!") — one text field per day, household-shared. Needs a small backend store (per household+date note) + endpoints; render on the shipped day headers (which already carry a count chip).
5. **Multi-baby / subject tagging**: if a household has twins, "Feed Baby" can't distinguish them today. Cheapest path: indicator labels per baby name; proper path: an optional `subject` field on chores. Decide before the widget builder bakes in per-chore assumptions.
6. **iOS Home-Screen widget + Live Activity** (native only): "time since last feed" widget; feeds directly off `GET /api/logs/latest-per-chore`. High value, native-only — belongs on the iOS roadmap after parity items.

---

## 6. Suggested implementation order (remaining)

| Order | Item | Size | Risk |
|---|---|---|---|
| 1 | Phase 3 generalized metrics | L | Medium (migration) |
| 2 | Phase 4 widget builder | L | Medium (schema validation) |
| 3 | Phase 5.3 amount steppers / recent-value chips | S–M | Low |
| 4 | Phase 5.4 per-day notes | M | Low (small store) |
| 5 | Phase 5.2 duration timer (after Phase 3 `duration`) | M | Low |
| 6 | Phase 5.5 multi-baby / subject tagging | M–L | Medium (data model) |
| 7 | 2.1 inline pending styling · 2.6 snooze endpoint | S each | Low |
| 8 | Phase 5.6 iOS widget (native) | M | Low (iOS-only) |

Every phase that touches API/schema must update `docs/plans/client-parity.md` per the CI parity gate.
