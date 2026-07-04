import UIKit
import UserNotifications

/// UIKit delegate hooks for remote notifications: APNs token callbacks, the
/// notification action categories, and routing of notification taps/actions.
/// Behavioral parity with the PWA service worker's `push`/`notificationclick`
/// handlers (web/static/service-worker.js).
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by ContentView once SwiftUI state exists; a "Log now" tap that
    /// arrives earlier (cold launch from a notification) is buffered.
    weak var appState: AppState?
    private var bufferedQuickLogChoreId: Int?

    enum NotificationIdentifiers {
        /// Must match the `category` field the reminder push carries
        /// (internal/reminder/scheduler.go → aps.category).
        static let reminderCategory = "NABU_REMINDER"
        static let logNowAction = "NABU_LOG_NOW"
        static let snoozeAction = "NABU_SNOOZE_30"
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        return true
    }

    /// Parity with the PWA reminder actions: "✓ Log now" and "⏰ Snooze 30m".
    private func registerNotificationCategories() {
        let logNow = UNNotificationAction(
            identifier: NotificationIdentifiers.logNowAction,
            title: "✓ Log now",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: NotificationIdentifiers.snoozeAction,
            title: "⏰ Snooze 30m",
            options: []
        )
        let reminder = UNNotificationCategory(
            identifier: NotificationIdentifiers.reminderCategory,
            actions: [logNow, snooze],
            intentIdentifiers: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([reminder])
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushRegistrationController.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistrationController.shared.handleRegistrationFailure(error)
        }
    }

    // MARK: - Deep-link buffering

    /// Routes a "Log now" action to the home log sheet, or buffers it until
    /// ContentView attaches the app state on a cold launch.
    @MainActor
    func routeQuickLog(choreId: Int) {
        guard let appState else {
            bufferedQuickLogChoreId = choreId
            return
        }
        appState.currentTab = .home
        appState.homeView = .log
        appState.pendingQuickLogChoreId = choreId
    }

    @MainActor
    func attach(appState: AppState) {
        self.appState = appState
        if let choreId = bufferedQuickLogChoreId {
            bufferedQuickLogChoreId = nil
            routeQuickLog(choreId: choreId)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground presentation: show reminders while the app is open, the
    /// same way the PWA's service worker shows them over an open tab.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let choreId = (userInfo["choreId"] as? NSNumber)?.intValue

        switch response.actionIdentifier {
        case NotificationIdentifiers.snoozeAction:
            // Silently reschedules without opening the app — the endpoint is
            // CSRF-exempt and session-authenticated, exactly like the PWA
            // service worker's snooze fetch.
            guard let choreId else { return }
            let api = APIClient(baseURL: AppEnvironment.resolveBaseURL())
            let body = ReminderSnoozeRequest(choreId: choreId, minutes: 30)
            let _: StatusResponse? = try? await api.post("/api/reminders/snooze", body: body)
        case NotificationIdentifiers.logNowAction:
            // Deep-links to the pre-filled log sheet — parity with the PWA's
            // `/?quicklog=chore:<id>`.
            guard let choreId else { return }
            routeQuickLog(choreId: choreId)
        default:
            // A plain body tap just opens/focuses the app.
            break
        }
    }
}
