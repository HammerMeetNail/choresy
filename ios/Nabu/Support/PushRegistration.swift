import Foundation

/// Which APNs environment this build's device tokens belong to. Debug builds
/// run under the development provisioning profile and receive sandbox tokens;
/// TestFlight/App Store builds receive production tokens. The backend stores
/// the environment per device and routes each push to the matching APNs host.
enum APNsEnvironment {
    static let sandbox = "sandbox"
    static let production = "production"

    static func select(isDebugBuild: Bool) -> String {
        isDebugBuild ? sandbox : production
    }

    static var current: String {
        #if DEBUG
        return select(isDebugBuild: true)
        #else
        return select(isDebugBuild: false)
        #endif
    }
}

enum PushRegistration {
    /// UserDefaults key holding the last token successfully registered with
    /// the backend, so logout can unregister exactly what was registered.
    static let storedTokenKey = "nabuAPNsRegisteredToken"

    /// APNs hands the app a raw token; the backend stores it hex-encoded.
    static func hexToken(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }
}

/// The token-registration lifecycle, modeled as a pure state machine so the
/// transitions are unit-testable without UIKit or the network:
///
///     idle → awaitingAuthorization → awaitingToken → registering → registered
///                    ↘ denied                ↘ failed ↙
///
/// `denied` and `failed` are re-enterable — the user can retry from the
/// notification settings screen.
enum PushRegistrationPhase: Equatable {
    case idle
    /// Pre-prompt accepted; the system permission dialog is up.
    case awaitingAuthorization
    /// Authorized; `registerForRemoteNotifications()` is in flight.
    case awaitingToken
    /// APNs delivered a token; the backend register call is in flight.
    case registering(token: String)
    case registered(token: String)
    /// The user declined the system dialog (recoverable only in iOS Settings).
    case denied
    /// Registration failed (non-fatal; push simply stays off).
    case failed(String)

    enum Event: Equatable {
        case enableRequested
        case authorizationGranted
        case authorizationDenied
        case tokenReceived(String)
        case registerSucceeded
        case registerFailed(String)
        case unregistered
    }

    func applying(_ event: Event) -> PushRegistrationPhase {
        switch event {
        case .enableRequested:
            // Re-enterable from any non-registered state (retry after
            // denial/failure); an already-registered device stays put.
            if case .registered = self { return self }
            return .awaitingAuthorization
        case .authorizationGranted:
            return .awaitingToken
        case .authorizationDenied:
            return .denied
        case .tokenReceived(let token):
            return .registering(token: token)
        case .registerSucceeded:
            if case .registering(let token) = self { return .registered(token: token) }
            return self
        case .registerFailed(let message):
            return .failed(message)
        case .unregistered:
            return .idle
        }
    }
}
