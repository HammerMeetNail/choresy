import Foundation

/// Incoming URLs the app handles: universal links from the auth emails
/// (verification, magic link) and invite shares, plus the PWA's
/// `/?quicklog=chore:<id>` deep link used by the notification "Log now"
/// action. Paths must stay in sync with the backend's
/// apple-app-site-association components (internal/app/server.go).
enum DeepLink: Equatable {
    case verifyEmail(token: String)
    case magicLogin(token: String)
    case joinHousehold(code: String)
    case quickLog(QuickLogTarget)
    /// `?quicklog=activity` — the Activity manifest shortcut.
    case showActivity
    /// `?quicklog=chore` (no id) — land on the home log grid.
    case showHomeLog

    static func parse(_ url: URL) -> DeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        func query(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name == name })?.value
        }
        switch components.path {
        case "/verify-email":
            if let token = query("token"), !token.isEmpty {
                return .verifyEmail(token: token)
            }
        case "/magic-login":
            if let token = query("token"), !token.isEmpty {
                return .magicLogin(token: token)
            }
        case "/join":
            if let code = query("code"), !code.isEmpty {
                return .joinHousehold(code: code)
            }
        case "", "/":
            // The PWA's ?quicklog= targets (manifest shortcuts + the
            // notification "Log now" deep link), handled identically.
            switch query("quicklog") {
            case let quicklog? where quicklog.hasPrefix("chore:"):
                if let id = Int(quicklog.dropFirst("chore:".count)) {
                    return .quickLog(.chore(id: id))
                }
            case "feed-baby":
                return .quickLog(.predefined(key: "Feed Baby"))
            case "activity":
                return .showActivity
            case "chore":
                return .showHomeLog
            default:
                break
            }
        default:
            break
        }
        return nil
    }
}
