# P7 — Release

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). The final phase:
verification sweep, TestFlight, submission. Update the **Progress log**
below as work lands.

**Exit gate:** Every matrix row **Done** or an owner-signed exception; App
Review submitted.

---

## D6. Physical-device release checklist (manual, per release candidate)

- APNs end-to-end (sandbox + production): register → reminder → receive →
  Log now → Snooze → logout → unregister.
- Universal links: verify email, magic link, invite link.
- Dynamic Type sweep (through AX sizes) on real hardware.
- VoiceOver smoke pass on the five tabs + log sheet.
- Widget timeline refresh; Live Activity (if shipped).

## E. Submission mechanics

1. **TestFlight:** internal testing throughout; external beta once parity
   phases close, with the device checklist run on every release candidate.
2. **App Store Connect metadata:**
   - Name, subtitle, description, keywords; category **Lifestyle** (or
     **Health & Fitness** — decide at submission); age rating 4+.
   - **Screenshots** for 6.9″ and 6.5″ classes, taken from the polished app
     with a seeded demo household (light + dark). Do them after P6, not
     before.
   - Privacy labels + privacy policy URL, support URL (prepared in P6/A5).
   - **Review notes:** demo account credentials on a production household
     seeded with realistic data; one paragraph explaining the household
     model; note that push requires the demo account's reminders (reviewers
     often test push).
3. **Full test sweep before archive:** `make test-go`, `make test-js`,
   `make e2e`, iOS unit/contract/snapshot/UI suites — all green in CI, iOS
   lane confirmed running on the tag push.
4. **Review-risk register** (what a rejection would cite, and our answer):

   | Guideline | Risk | Mitigation |
   |-----------|------|------------|
   | 4.2 minimum functionality / web-port feel | Medium | Native-first design (P6), widget + quick actions + Live Activity, haptics/motion |
   | 5.1.1(v) account deletion | Certain rejection if absent | P1 backend + P3 UI |
   | 4.8 login services | High (Google OAuth present) | Sign in with Apple (P1 backend + P5 button) |
   | 2.1 completeness (dead/empty screens, broken states) | Medium | P6 four-state pass + snapshot tests |
   | 5.1.1 permission requests | Low-medium | P5 pre-prompt; request only on user intent |
   | 2.3 accurate metadata/screenshots | Low | Screenshots after P6 |

5. Budget a respond-and-resubmit round into the timeline; App Review
   surprises beyond the register above are absorbed here.

## Definition of Done — v1 submission

Submit to App Review only when **all** of the following hold:

1. Every row in `docs/plans/client-parity.md` is **Done**, **N/A**, or
   **Deferred with an owner-signed justification** — zero **iOS pending**,
   zero **Not built**. (`bash scripts/check-parity.sh --strict` is the
   release gate.)
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

---

## Progress log

- [ ] External TestFlight beta live — **owner**
- [ ] Metadata complete (screenshots, description, privacy, review notes) — **owner** (privacy/support URLs are live: `/privacy`, `/support`)
- [x] Full test sweep green (2026-07-04, local): `make test-go` · `make test-js` · `make e2e` (306) · `NabuTests` (unit/contract/snapshot) · all four local `NabuUITests` classes incl. the accessibility audit
- [ ] D6 device checklist signed off — **owner** (physical device)
- [ ] `check-parity.sh --strict` passes (or owner-signed exceptions recorded)
- [ ] Submitted to App Review — **owner**

### Notes

**2026-07-04 — non-owner-gated P7 groundwork done during the P6 session.**

- Full test sweep run and green (see checklist). The iOS CI lane running on
  every `v*` tag push was verified in `.github/workflows/ci.yaml` (the
  `changes` job forces `ios: true` on tag refs — P1/D5).
- `check-parity.sh` is well-formed; `--strict` will keep failing by design
  until rows are promoted from **Built** to **Done** (CI-run coverage) and
  the two open pendings resolve: **Sign in with Apple** (PWA web-SIWA or
  owner-signed N/A exception) and nothing else — the widget row flipped to
  Built in P6.
- Everything else in this phase needs the Apple developer account: portal
  capabilities (Push, SIWA, Associated Domains, App Group on
  `com.nabu.app`), `.p8` + prod env (`APNS_*`, `APPLE_CLIENT_IDS`),
  TestFlight, the D6 physical-device checklist (APNs end-to-end sandbox +
  production, universal links, Dynamic Type/VoiceOver on hardware, widget
  timeline), marketing screenshots, App Store Connect metadata + privacy
  labels, and submission itself.
