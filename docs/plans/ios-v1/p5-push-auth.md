# P5 — Push & auth completion

Part of the [iOS App Store v1 plan](../ios-appstore-v1.md). Read the index's
§2 decisions and §2.1 governing rule first. Requires **P1** (A2/A3 backend)
and Apple developer credentials (bundle ID with Push Notifications, Sign in
with Apple, Associated Domains capabilities; APNs `.p8` key provisioned).
Update the **Progress log** below as work lands.

**Exit gate:** Physical-device APNs test passed; auth rows Done.

---

## A3 (client half). APNs iOS client + notification actions

Per [`docs/apns-implementation-plan.md`](../../apns-implementation-plan.md):

1. Push Notifications capability + remote-notification background mode.
2. **Permission pre-prompt** — never fire the system dialog cold. One-screen
   explanation ("Get reminded when it's time to feed…") with an explicit
   button; request `UNUserNotificationCenter` authorization only on tap.
3. Registration lifecycle: authorization →
   `registerForRemoteNotifications`; `didRegisterForRemoteNotifications…` →
   hex token → `POST /api/mobile/apns/register` (`environment` = `sandbox`
   for debug builds, `production` otherwise); unregister on logout;
   `didFailToRegister…` → non-fatal surfaced state.
4. Foreground/background presentation via `UNUserNotificationCenterDelegate`.
5. **Notification action categories** (parity with the PWA's reminder
   actions — the reminder push already carries `choreId`/`type`):
   - **"Log now"** → deep-link into the app with the log sheet pre-filled
     for that chore (parity with `/?quicklog=chore:<id>`).
   - **"Snooze 30m"** → background `POST /api/reminders/snooze` (endpoint
     already shipped).
6. Tests: `APNsContractTests.swift` for register/unregister body encoding;
   unit test for sandbox/production selection; token-registration state
   machine unit tests.

**Release-gating verification (simulator cannot receive remote push):**
physical device — register, trigger a schedule reminder, receive it,
exercise both actions, logout, confirm unregister. Sandbox **and**
production (TestFlight).

## A4. Email verification + universal links

1. `applinks:` associated domain + AASA file served by the Go backend.
2. Handle verify (`/api/auth/email/verify?...`) and magic-link consume URLs
   in `onOpenURL` / `NSUserActivity`, calling the same endpoints the PWA
   does.
3. Fallback path (ship regardless — it's also the cross-device behavior):
   verification completes in the browser; the app refreshes `/api/me` on
   foreground and picks up verified state.
4. "Resend verification" action in Settings → Account (endpoint exists).
5. Wire invite links (`/join?code=…`) through the same AASA plumbing while
   it's fresh.

## A2 (client half). Sign in with Apple button

Native `SignInWithAppleButton` / `ASAuthorizationController` on the login
and register screens, styled per Apple's button rules (at least as prominent
as the Google button). PWA web-SIWA button ships whenever convenient before
P7 (or record an explicit N/A parity exception).

UI test: the button renders on both auth screens.

---

## Progress log

- [ ] Apple developer setup: bundle ID + capabilities + `.p8` provisioned (unblocks everything here)
- [ ] Permission pre-prompt screen
- [ ] APNs registration lifecycle + unregister on logout
- [ ] Notification categories: Log now (deep link) + Snooze 30m
- [ ] APNsContractTests + state-machine unit tests
- [ ] Physical-device sandbox test · production test on TestFlight build
- [ ] AASA + universal links (verify, magic link, invite)
- [ ] Verification fallback via `/api/me` foreground refresh + Settings resend
- [ ] SignInWithAppleButton on login + register (iOS); PWA button or N/A exception
- [ ] Matrix rows updated (APNs → Built → Done; email verification → Done)

### Notes

*(append dated entries here)*
