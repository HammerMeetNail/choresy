import Foundation
import UIKit
import UserNotifications

/// Orchestrates the APNs registration lifecycle around the pure
/// `PushRegistrationPhase` state machine: system authorization, token
/// registration with the backend, and unregistration on logout.
///
/// A singleton because UIKit's remote-notification callbacks land on the app
/// delegate, which exists before any SwiftUI state.
@MainActor
final class PushRegistrationController: ObservableObject {
    static let shared = PushRegistrationController()

    @Published private(set) var phase: PushRegistrationPhase = .idle

    private var api: APIClient?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configure(api: APIClient) {
        self.api = api
    }

    /// Silent launch-time sync: if the user already granted notification
    /// permission, refresh the token registration (tokens can change, so
    /// Apple recommends re-registering on every launch). Never prompts —
    /// mirrors the PWA's `maybeSubscribePush()` after login.
    func syncIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
        apply(.authorizationGranted)
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// The pre-prompt's "Enable" button: this is the only place the system
    /// permission dialog is fired (never cold — the pre-prompt explains why
    /// first). Returns whether the user granted permission.
    @discardableResult
    func requestAuthorizationAndRegister() async -> Bool {
        apply(.enableRequested)
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                apply(.authorizationGranted)
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                apply(.authorizationDenied)
            }
            return granted
        } catch {
            apply(.authorizationDenied)
            return false
        }
    }

    var authorizationStatus: UNAuthorizationStatus {
        get async {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
    }

    /// `didRegisterForRemoteNotificationsWithDeviceToken` → hex-encode and
    /// register with the backend. Failure is non-fatal: push stays off and
    /// the phase records why.
    func handleDeviceToken(_ deviceToken: Data) async {
        let token = PushRegistration.hexToken(from: deviceToken)
        apply(.tokenReceived(token))
        guard let api else {
            apply(.registerFailed("API not configured"))
            return
        }
        let body = APNsRegisterRequest(
            token: token,
            environment: APNsEnvironment.current,
            bundleId: Bundle.main.bundleIdentifier ?? "com.nabu.app",
            deviceName: UIDevice.current.name
        )
        do {
            let _: StatusResponse = try await api.post("/api/mobile/apns/register", body: body)
            defaults.set(token, forKey: PushRegistration.storedTokenKey)
            apply(.registerSucceeded)
        } catch {
            apply(.registerFailed((error as? APIError)?.errorDescription ?? "registration failed"))
        }
    }

    /// `didFailToRegisterForRemoteNotificationsWithError` — expected on
    /// simulators and when offline; surfaced as state, never as an alert.
    func handleRegistrationFailure(_ error: Error) {
        apply(.registerFailed(error.localizedDescription))
    }

    /// Removes this device's token server-side. Must run while the session
    /// cookie is still valid, i.e. before `POST /api/auth/logout`.
    func unregisterForLogout() async {
        defer {
            defaults.removeObject(forKey: PushRegistration.storedTokenKey)
            apply(.unregistered)
        }
        guard let token = defaults.string(forKey: PushRegistration.storedTokenKey),
              let api else { return }
        let body = APNsUnregisterRequest(token: token, environment: APNsEnvironment.current)
        let _: StatusResponse? = try? await api.post("/api/mobile/apns/unregister", body: body)
    }

    private func apply(_ event: PushRegistrationPhase.Event) {
        phase = phase.applying(event)
    }
}
