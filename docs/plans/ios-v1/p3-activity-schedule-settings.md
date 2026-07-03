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

- [ ] History search (`?q=`)
- [ ] Per-day diary notes (read + edit sheet)
- [ ] Infinite scroll + day count chips
- [ ] `.refreshable` on all tabs
- [ ] Schedule for-date overlay
- [ ] CSV export + share sheet
- [ ] Account deletion UI (iOS **and** PWA) → flip matrix row from Not built
- [ ] List affordances (swipe/context menus/dialogs)
- [ ] Matrix rows updated

### Notes

*(append dated entries here)*
