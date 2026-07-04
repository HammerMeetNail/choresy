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

- [ ] Apple developer setup: bundle ID + capabilities + `.p8` provisioned (unblocks everything here) — **owner**
- [x] Permission pre-prompt screen
- [x] APNs registration lifecycle + unregister on logout
- [x] Notification categories: Log now (deep link) + Snooze 30m
- [x] APNsContractTests + state-machine unit tests
- [ ] Physical-device sandbox test · production test on TestFlight build — **owner**
- [x] AASA + universal links (verify, magic link, invite)
- [x] Verification fallback via `/api/me` foreground refresh + Settings resend
- [x] SignInWithAppleButton on login + register (iOS); PWA button or N/A exception — **both shipped: PWA web-SIWA landed 2026-07-04 (see p7-release.md notes), no exception needed**
- [x] Matrix rows updated (APNs → Built; email verification, Log now, Snooze → Built; SIWA → Built (iOS)) — promotion to Done follows CI + device verification

### Notes

**2026-07-03 — P5 code complete; owner-gated items remain.** Everything
buildable without Apple portal access landed and is green (app build,
`NabuTests` incl. new suites on iPhone 17 Pro / iOS 26.0, `make test-go`,
`make test-js`, SIWA UI render tests):

- *APNs client*: `Support/PushRegistration.swift` (pure token/environment
  helpers + `PushRegistrationPhase` state machine),
  `App/PushRegistrationController.swift` (authorization → register → backend
  POST, silent launch re-register when already authorized, unregister-on-logout
  wired into `AuthStore.logout()` before the session is destroyed),
  `App/AppDelegate.swift` (token callbacks, foreground presentation,
  `NABU_REMINDER` category with Log now/Snooze 30m). Push Notifications
  entitlement + `remote-notification` background mode +
  `Nabu/Resources/Nabu.entitlements` (aps-environment, SIWA, associated
  domains) added; `CODE_SIGN_ENTITLEMENTS` set on both configs.
- *Pre-prompt*: `Views/PushPrePromptView.swift`, shown from the notification
  settings screen only when the push pref is toggled on with system
  authorization `.notDetermined`; snapshot-tested light/dark. A denied system
  permission surfaces as a section footer pointing at iOS Settings.
- *Backend*: reminder pushes now carry `category: NABU_REMINDER`
  (`internal/reminder/scheduler.go`, tested) so the iOS actions attach — the
  APNs sender already mapped `category` → `aps.category`; the SW ignores it.
  `/.well-known/apple-app-site-association` served when
  `APNS_TEAM_ID`+`APNS_BUNDLE_ID` are set (`internal/app/server.go`, tested).
- *Universal links*: `Support/DeepLink.swift` parses `/verify-email`,
  `/magic-login`, `/join`, and `/?quicklog=chore:<id>`; handled in
  `ContentView.handleIncomingURL` via `onOpenURL` + `NSUserActivity`, calling
  the same endpoints as the PWA. `/join` while logged out stashes the code and
  prefills Onboarding's Join tab. `foregroundRefresh()` now re-fetches
  `/api/me` (cross-device verification fallback).
- *SIWA*: `Auth/SignInWithAppleCoordinator.swift` (hex random nonce, identity
  token → `POST /api/auth/apple/native`); `SignInWithAppleButton` above the
  Google button on Login (`.signIn`) and Register (`.signUp`), black/white per
  color scheme; UI tests assert render on both screens.
- *Decisions*: notification-permission surface is settings-triggered only for
  now (P6 can add an onboarding touchpoint); reset-password links deliberately
  not in the AASA (web flow works, no in-app reset screen); `deviceName` sends
  `UIDevice.current.name` (generic "iPhone" on iOS 16+, no PII).
- *Still owner-gated*: portal capabilities (Push, SIWA, Associated Domains) on
  `com.nabu.app`, `.p8` provisioning + `APNS_*`/`APPLE_CLIENT_IDS` prod config,
  physical-device sandbox/TestFlight push verification, PWA web-SIWA or N/A
  exception.
