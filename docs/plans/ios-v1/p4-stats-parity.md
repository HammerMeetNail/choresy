# P4 — Stats parity

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). Read the index's
§2 decisions and §2.1 governing rule first. Requires **P1** (StatsWidget /
ChoreSummary models). The largest phase — also where Swift Charts lands.
Update the **Progress log** below as work lands.

**Exit gate:** All stats rows Built; snapshot tests for every chart state.

---

## Swift Charts migration (from C5)

Replace hand-drawn `Canvas` charts with `Chart` (bar/line/heatmap-style
plots), brand-tinted, with `.chartXSelection` scrubbing where useful. §2.1
allows presentation divergence from PWA charts — keep data/semantics
identical and document per-chart differences in the matrix. Adopt
`swift-snapshot-testing` in this phase (first big need): snapshot every chart
state, light/dark.

## B5. Stats features

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
   plain `Text` — never as attributed/markdown content; port the PWA's
   hostile-title XSS spec intent into a snapshot test.
6. **Period toggles convergence (#84/#85).** The PWA's categories/chores
   sections carry day/week/month toggles and send `?period=`; iOS's stats
   design diverged. Converge on the PWA's *semantics* (period scoping, what
   data each section shows) using native segmented controls; the visual
   treatment is free per §2.1.
7. **Customize panel.** Section reorder/hide (`statsSections` prefs) covering
   static keys, `chore:<id>`, and `widget:<uuid>` — required for widgets and
   generalized sections to be manageable.

---

## Progress log

- [x] `swift-snapshot-testing` adopted; harness in place
- [x] Swift Charts migration of existing charts
- [x] Breakdown / Streaks / Recap / Feeding gaps / Last done sections
- [x] `colorForIndicator` port + hash-output tests
- [x] Generalized `chore:<id>` sections; baby = saved config
- [x] Interval analysis (`choreId` param)
- [x] Custom widgets: decode, render all six types, per-card period toggle, wizard
- [x] Period-toggle convergence (#84/#85)
- [x] Customize panel (reorder/hide, all key kinds)
- [x] Matrix rows updated

### Notes

- **2026-07-03 — Phase complete.** Landed in one pass:
  - **Architecture:** `StatsView` is now registry-driven — `StatsModel`
    (`Views/Stats/StatsModel.swift`) mirrors `app.js`'s stats loading
    (same endpoints/params/caches, `MAX_ANALYTICS_FETCHES=15` cap) and
    `Support/StatsSections.swift` ports `resolveStatsLayout` + dynamic
    `chore:<id>`/`widget:<uuid>` keys. Section/chart views split into
    `Views/Stats/` (charts, sections, widgets/customize).
  - **Swift Charts:** all plots are `Chart`-based (`StatsCharts.swift`):
    stacked period bars with `.chartXSelection` tap summaries, busy-hours
    bars, heatmap `RectangleMark` grid (Monday-start, asset-catalog
    `Heatmap*` ramp from the PWA CSS tokens), cluster-feeding scatter with
    the 2h rule and ported dot classification.
  - **Snapshot testing:** `swift-snapshot-testing` 1.17+ added to the
    project; 16 chart/widget states × light/dark recorded on iOS 26
    (`NabuTests/__Snapshots__/`). Tests `XCTSkipUnless` on other iOS majors
    so the CI runner's older simulator skips rather than pixel-mismatches.
    Includes the hostile-widget-title XSS-intent snapshot (plain `Text`).
  - **Found & fixed a latent P1 bug:** `Assets.xcassets` was wired into the
    Xcode project as a *folder group* whose only resource was the top-level
    `Contents.json` — no `Assets.car` was ever compiled into the app, so
    every named color (`BrandPrimary`, `Surface`, …) silently resolved to
    clear at runtime. The first snapshot recordings exposed it (invisible
    bars/numbers). The catalog is now a `folder.assetcatalog` reference in
    the Resources phase; `Assets.car` verified present in the built app.
  - **Interval analysis:** the `?choreId=` generalization is server-side;
    the PWA UI never sends `choreId` today, so iOS intentionally matches
    (default Feed Baby). Revisit only if the PWA grows a chore picker.
  - **Presentation choices** (allowed by §2.1, recorded in the matrix):
    segmented pickers for all period toggles, native sheet + `Form` wizard,
    `List` drag-reorder in the customize panel, no per-heatmap-cell tap
    tooltip, top-chores pills keep the PWA's default-to-current-user with
    no deselect.
  - Verified: iOS build + full `NabuTests` green on iPhone 17 (iOS 26.5)
    simulator; `make test-go` green; `make test-js` 76/76.
