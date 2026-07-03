# P3 — Activity, Schedule & Settings parity

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). Read the index's
§2 decisions and §2.1 governing rule first. Requires **P1** (models, A1
backend). Update the **Progress log** below as work lands.

**Exit gate:** Rows Built; search/notes/export UI tests pass; account
deletion reachable in Settings on both clients.

---

## B3. Activity

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

## B4. Schedule

1. **For-date overlay.** The one pending schedule row: consume `GET
   /api/schedules/for-date` wherever the PWA's `schedule.js` uses it, so
   scheduled-occurrence context matches. Verify actual PWA call sites first
   and mirror them — do not invent a new surface for it.

## B6. Settings & data

1. **CSV export.** Settings action → `GET /api/logs/export?start&end&choreId`
   → native share sheet (`ShareLink`/`UIActivityViewController`) with a
   `.csv` file. Date-range + chore pickers matching the PWA's options.
2. **Account section:** delete-account flow (uses P1's `DELETE /api/me`;
   destructive styling, typed confirmation, sole-owner transfer guidance) on
   **both** clients; resend verification; privacy-policy and support links
   (see P6/A5 for the URLs themselves).

## C2 (list slice). Native list affordances

While these screens are open: swipe-to-delete on logs/notifications, swipe
actions for mark-read, context menus (long-press a home tile → Log…, Edit
chore, Hide from Home; long-press a schedule row → Edit, Delete),
confirmation dialogs for destructive actions. Replace custom pill/segment
controls with segmented `Picker`s unless a screen truly needs the custom
look.

---

## Progress log

- [x] History search (`?q=`)
- [x] Per-day diary notes (read + edit sheet)
- [x] Infinite scroll + day count chips
- [x] `.refreshable` on all tabs
- [x] Schedule for-date overlay → **Deferred** (see note)
- [x] CSV export + share sheet
- [x] Account deletion UI (iOS **and** PWA) → flip matrix row from Not built
- [x] List affordances (swipe/context menus/dialogs)
- [x] Matrix rows updated

### Notes

- **2026-07-03** — Phase complete in one pass.
  - **Activity**: `.searchable` with 300 ms debounce → `?q=`; search mode
    hides the chore filter, pending rows, and pagination (PWA semantics).
    Day headers gained count chips and the shared note affordance
    (`DayNoteSheet`, 500-char cap, empty clears). Tail-row `onAppear`
    sentinel auto-loads the next page with the Load-more button kept as
    fallback. Swipe-to-delete on log rows behind a confirmation dialog.
  - **For-date overlay: Deferred, not built.** Per the doc's instruction to
    verify PWA call sites first: `loadSchedulesForDate`'s only consumer is
    `loadTodayWithSchedules` in the unrouted calendar-era code, so there is
    no live surface to mirror. Matrix row moved to Deferred.
  - **Settings**: CSV export downloads the same all-history window as the
    PWA's link and hands `nabu-logs.csv` to a native share sheet.
    `DeleteAccountSheet` (typed DELETE, destructive styling, 409
    transfer-ownership guidance surfaced verbatim); resend-verification
    button for unverified accounts. PWA got the equivalent delete-account
    flow in its Account card (`settings-delete-account.spec.js`, 3 tests).
  - **Backend fix**: Postgres `DeleteUser` referenced `household_invites`
    but the table is `invites` — deletion 500ed against a real database.
    The in-memory-store unit tests couldn't catch it; the new e2e spec runs
    the flow against Postgres and now passes.
  - **List affordances**: home tiles got a context menu (Log… / Edit chore /
    Hide from Home — replacing the old long-press-duplicates-tap gesture);
    schedule rows got swipe Edit/Delete + context menu with confirmation
    dialog; notification rows got leading swipe mark-read. `.refreshable`
    on all five tabs plus Notifications.
  - Suites green: Go (20 pkgs), JS (76), iOS NabuTests (217), targeted e2e
    (search/notes/export/settings-auth/delete-account: 14 tests).
