# P2 — Logging parity

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). Read the index's
§2 decisions and §2.1 governing rule first. Requires **P1** (models decode
the new fields). Update the **Progress log** below as work lands.

**Exit gate:** All B2 matrix rows Built with unit/contract tests; log-sheet
UI tests pass.

For each item: read the PWA module and spec listed in the matrix row first;
port behavior, not markup.

---

## B2. Logging surfaces

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
   localStorage behavior). *Native bonus (P6/B8): surface it as a Live
   Activity.*
4. **Subject tagging (multi-baby).** If the chore declares `subjects`, the
   log sheet shows a single-select subject chip row; history rows show the
   tag.
5. **Recent-value chips.** Last 3 distinct volumes as tappable chips above
   the volume picker (PWA Phase 5.3).
6. **Offline log queue + idempotency.** Queue failed `POST /api/logs` bodies
   (with a client-generated `idempotencyKey`) in the app's store; replay on
   foreground and on connectivity restore (`NWPathMonitor`); show queued
   logs inline in Activity with a subtle non-tappable **pending** badge,
   reconciled on replay — exactly the PWA's shipped semantics. Unit-test
   replay, de-dup, and reconciliation against a mock server.

## C2 (log-sheet slice). Native sheet presentation

The log sheet and pick-chore sheet move to native sheets with detents
(`.presentationDetents([.medium, .large])`, drag indicator) as part of this
phase, since every B2 item touches the sheet anyway. Preserve the When-picker
invariants: minutes preserved, never rounded to `:00`; `completedAt`, `date`,
and `hour` derived from the selected value (see `ios/AGENTS.md` invariants).

---

## Progress log

- [ ] Volume unit conversion util + settings toggle + LogSheet/history/stats adoption
- [ ] "Track a value" metric picker in ChoreEditView
- [ ] Duration timer (start/chip/stop→`durationSeconds`, relaunch-safe)
- [ ] Subject picker + history tag
- [ ] Recent-value chips
- [ ] Offline log queue + idempotency + pending badge
- [ ] Log sheet on native detents, invariants re-tested
- [ ] Matrix rows updated (Built + test refs)

### Notes

*(append dated entries here)*
