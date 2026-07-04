# iOS App Store v1 — Parity & Polish Plan (index)

**Status:** Active — P1–P4 complete; P5 and P6 code complete; P7 test sweep done and PWA web-SIWA shipped (2026-07-04), `check-parity.sh --strict` passes — everything left is owner-gated (Apple portal setup incl. web Services ID, physical-device verification, TestFlight, screenshots/metadata, submission) ·
**Drafted:** 2026-07-02 · **Owner decisions recorded:** 2026-07-02

This is the **index** for the App Store v1 effort. The detailed, executable
content lives in one document per phase under [`ios-v1/`](./ios-v1/); each
phase doc carries its own scope, exit gate, and a **progress log** that
sessions update as work lands — read the current phase's doc (and its log)
before starting work, and append to the log when you finish.

| Phase | Doc | Contents | Exit gate |
|-------|-----|----------|-----------|
| **P1 Foundations** | [`ios-v1/p1-foundations.md`](./ios-v1/p1-foundations.md) | B1 model catch-up · A1/A2/A3 backend track · C1 design tokens · D5 CI fix | Models decode everything; account-delete + SIWA + APNs endpoints live behind tests; app builds on semantic colors |
| **P2 Logging parity** | [`ios-v1/p2-logging-parity.md`](./ios-v1/p2-logging-parity.md) | Volume unit, metric config, duration timer, subjects, recent chips, offline queue · log-sheet detents | B2 rows Built with tests; log-sheet UI tests pass |
| **P3 Activity + Schedule + Settings** | [`ios-v1/p3-activity-schedule-settings.md`](./ios-v1/p3-activity-schedule-settings.md) | Search, day notes, infinite scroll, pull-to-refresh, for-date, CSV export, account-deletion UI · list affordances | Rows Built; search/notes/export UI tests pass |
| **P4 Stats parity** | [`ios-v1/p4-stats-parity.md`](./ios-v1/p4-stats-parity.md) | All pending stats sections, widgets, color palette · Swift Charts + snapshot testing | All stats rows Built; snapshots for every chart state |
| **P5 Push + auth completion** | [`ios-v1/p5-push-auth.md`](./ios-v1/p5-push-auth.md) | APNs client + actions, universal links + email verification, SIWA button | Physical-device APNs test passed; auth rows Done |
| **P6 Beauty pass** | [`ios-v1/p6-beauty.md`](./ios-v1/p6-beauty.md) | Haptics/motion, four-state screens, per-screen polish, accessibility, widget/quick actions/Live Activity, privacy metadata | Accessibility audit clean; snapshot suite green; screenshots taken |
| **P7 Release** | [`ios-v1/p7-release.md`](./ios-v1/p7-release.md) | Device checklist, TestFlight, metadata, submission · Definition of Done | Every matrix row Done or owner-signed exception; submitted |

Rough sizing: P1 and P4 are large; P2/P3/P5/P6 medium; P7 small plus review
latency. The backend track inside P1 (A1/A2/A3) has no iOS dependencies —
parallelize it. Phase gates are hard: tests green (`make test-go`,
`make test-js`, `make e2e`, iOS lane) and the parity matrix updated before
the next phase starts.

This plan supersedes [`docs/plans/ios.md`](./ios.md) (the original
conversion plan, archived). Companions:

- [`docs/plans/client-parity.md`](./client-parity.md) — the living feature
  matrix; **source of truth for per-feature status**.
- [`docs/apns-implementation-plan.md`](../apns-implementation-plan.md) — the
  APNs work breakdown, executed across P1 (backend) and P5 (client).
- [`ios/AGENTS.md`](../../ios/AGENTS.md) — agent rules for the iOS codebase.

---

## 1. Where we are (audited 2026-07-02)

The native SwiftUI app is real: ~45 Swift source files under `ios/Nabu/`,
11 unit/contract test files, one XCUITest file, an iOS CI lane, and a parity
matrix re-baselined against the code on 2026-06-28. Phases 0–12 of the
original conversion plan are **Built**. What remains falls into four
buckets:

| Bucket | Summary | Addressed in |
|--------|---------|--------------|
| **A. Admission blockers** | Things App Review rejects without: in-app **account deletion** (no backend endpoint exists at all), **Sign in with Apple** (we offer Google OAuth → guideline 4.8), working **push** (APNs entirely unbuilt end-to-end), complete privacy metadata. | P1 (backend), P3 (deletion UI), P5 (client push/SIWA), P6 (privacy) |
| **B. Parity gaps** | ~24 **iOS pending** rows in the matrix from recent PWA work: generalized metrics, custom stats widgets, duration timer, subject tagging, day notes, history search, CSV export, volume units, offline queue, several stats sections. | P1 (models), P2–P4 (features) |
| **C. Beauty gaps** | The app pixel-copies PWA CSS. No pull-to-refresh, no haptics, no Swift Charts, almost no accessibility labels, sparse SF Symbols, hardcoded hex colors. | P1 (tokens), P4 (charts), P6 (everything visible) |
| **D. Confidence gaps** | Most matrix rows are **Built**, not **Done** (no CI-run coverage); the iOS CI lane is not a release gate on tag pushes. | P1 (CI fix), tests land with each phase, P7 (strict gate) |

---

## 2. Product decisions for v1

Recorded from the owner on 2026-07-02:

| Question | Decision |
|----------|----------|
| Parity bar for v1 | **Full parity + polish.** Every **iOS pending** row in the matrix ships before submission. |
| Native push | **APNs ships in v1.** Reminders are core to a baby-tracking app. |
| Design direction | **Native-first with brand accents.** iOS idiom for structure; the Nabu palette as the accent voice, not the literal skin. |
| Plan layout | This index + per-phase docs in `ios-v1/`; `docs/plans/ios.md` archived. |

Standing decisions carried forward from the original plan (unchanged):

- Native SwiftUI, no WebView shell. The PWA remains a first-class client.
- Existing Go backend and JSON API; session-cookie + CSRF auth (no bearer
  tokens without a security review).
- Online-first with a lightweight read cache; **no offline writes beyond the
  idempotent log queue** (P2), which mirrors the PWA's shipped behavior.
- Business authority stays on the server.

New defaults set by this plan (revisit only with an owner decision):

- **Minimum iOS: 17.0.** iPhone-first; the app may run scaled on iPad but
  iPad-optimized layout is out of scope for v1.
- **Charts move to Swift Charts** (P4) rather than hand-drawn `Canvas`.

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

## 3. Working across sessions

1. Find the current phase (first row of the table above whose exit gate
   isn't met — the **Status** line at the top of this file should say, keep
   it fresh).
2. Read that phase's doc, including its **Progress log** and **Notes**.
3. Do the work per the doc + §2.1; keep `docs/plans/client-parity.md` rows
   in sync (the CI parity gate enforces this).
4. Before ending the session: tick completed checklist items, append a
   dated note with state/decisions/surprises, and update this file's Status
   line if the phase changed.

---

## 4. Risks

| Risk | Mitigation |
|------|------------|
| APNs unverifiable until Apple credentials + physical device exist | Provision the developer account during P1, not P5; backend sender is testable with a fake APNs server meanwhile |
| Account-deletion cascade subtleties (owner households, log attribution) | Reuse existing remove-member/transfer semantics; audit FKs before writing the handler; owner sign-off on the chosen behavior |
| "Full parity" scope creep — the PWA keeps moving while we build | The CI parity gate forces matrix rows for new PWA work; new rows land in the phase backlog; P7's gate is *matrix-driven* (`check-parity.sh --strict`), not list-driven |
| Swift Charts can't reproduce a PWA chart exactly | §2.1 allows presentation divergence; document per-chart differences in the matrix; keep data/semantics identical |
| Widget-builder rendering of user titles | Render titles only as SwiftUI `Text` (never attributed/markdown); port the PWA's XSS spec intent into a snapshot test with a hostile title |
| XCUITest suite runtime balloons | Flows only in XCUITest; edge cases stay unit/contract; UI suite nightly + release, unit lane on every PR |
| Cookie/CSRF quirks resurface with new endpoints | Every new endpoint gets a contract test in the local-Go-server mode before its UI is built |
| App Review surprises | External TestFlight beta first; review notes with demo account; respond-and-resubmit budgeted into P7; risk register in `ios-v1/p7-release.md` |

The **Definition of Done** for v1 submission lives in
[`ios-v1/p7-release.md`](./ios-v1/p7-release.md).
