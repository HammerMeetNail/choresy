import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// One chore's "time since last log" snapshot, shared with the widget
/// extension through the app-group container. Compiled into both the app and
/// NabuWidgets targets.
struct WidgetChoreSnapshot: Codable, Identifiable {
    let id: Int
    let name: String
    let icon: String
    let lastCompletedAt: Date?
}

/// Writes the widget's data through the app group. The app refreshes it
/// whenever the latest-per-chore data loads (launch + foreground), which is
/// exactly when the numbers a widget shows could have changed.
enum WidgetDataCache {
    static let appGroupID = "group.com.nabu.app"
    static let snapshotKey = "widgetChoreSnapshots"

    static func write(chores: [WidgetChoreSnapshot]) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(chores) else { return }
        defaults.set(data, forKey: snapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func read() -> [WidgetChoreSnapshot] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let chores = try? JSONDecoder().decode([WidgetChoreSnapshot].self, from: data) else {
            return []
        }
        return chores
    }

}
