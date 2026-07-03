import Foundation

/// The single active duration timer, ported from the PWA's
/// `web/static/js/timer.js`. Persisted in `UserDefaults` (the PWA uses
/// localStorage) so it survives relaunch; the elapsed-time chip and
/// stop-and-log wiring live in the views.
struct ActiveTimer: Codable, Equatable {
    let choreId: Int
    let choreName: String
    let choreIcon: String
    /// Wall-clock start. Stored as milliseconds since epoch, matching the
    /// PWA's `Date.now()` shape.
    let startedAt: Date

    enum CodingKeys: String, CodingKey {
        case choreId, choreName, choreIcon, startedAt
    }

    init(choreId: Int, choreName: String, choreIcon: String, startedAt: Date) {
        self.choreId = choreId
        self.choreName = choreName
        self.choreIcon = choreIcon
        self.startedAt = startedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choreId = try container.decode(Int.self, forKey: .choreId)
        choreName = try container.decodeIfPresent(String.self, forKey: .choreName) ?? ""
        choreIcon = try container.decodeIfPresent(String.self, forKey: .choreIcon) ?? "⏱"
        let ms = try container.decode(Double.self, forKey: .startedAt)
        startedAt = Date(timeIntervalSince1970: ms / 1000)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(choreId, forKey: .choreId)
        try container.encode(choreName, forKey: .choreName)
        try container.encode(choreIcon, forKey: .choreIcon)
        try container.encode(startedAt.timeIntervalSince1970 * 1000, forKey: .startedAt)
    }
}

enum DurationTimer {
    static let defaultsKey = "nabu_active_timer"

    /// Returns the persisted active timer, or nil. Validates shape so a
    /// corrupt/partial value never crashes the caller.
    static func load(from defaults: UserDefaults = .standard) -> ActiveTimer? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ActiveTimer.self, from: data)
    }

    /// Persists (or clears, when nil) the active timer.
    static func save(_ timer: ActiveTimer?, to defaults: UserDefaults = .standard) {
        if let timer = timer, let data = try? JSONEncoder().encode(timer) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    /// Whole seconds elapsed since the timer started.
    static func elapsedSeconds(_ timer: ActiveTimer, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(timer.startedAt)))
    }

    /// Renders seconds as m:ss (or h:mm:ss past an hour).
    static func formatElapsed(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let ss = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, ss)
        }
        return String(format: "%d:%02d", m, ss)
    }
}
