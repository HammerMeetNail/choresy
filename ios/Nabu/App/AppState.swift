import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var user: User?
    @Published var household: Household?
    @Published var userHouseholds: [HouseholdWithRole] = []
    @Published var activeHouseholdId: Int?
    @Published var members: [Member] = []
    @Published var invites: [Invite] = []
    @Published var chores: [Chore] = []
    @Published var todayLogs: [ChoreLog] = []
    @Published var schedules: [ChoreSchedule] = []
    @Published var latestLogs: [Int: ChoreLog] = [:]
    @Published var notifications: [AppNotification] = []
    @Published var unreadNotifications = 0
    @Published var notificationPrefs: ReminderPreference?
    @Published var availableNotificationTypes: [NotificationTypeInfo] = []
    @Published var choreReminderPrefs: [ChoreReminderPref] = []
    @Published var choreOrder: [Int] = []
    @Published var hiddenHomeChoreIDs: [Int] = []
    @Published var currentTab: MainTab = .home
    @Published var homeView: HomeViewMode = .log
    @Published var activeSheet: ActiveSheet?
    @Published var toast: Toast?
    @Published var jiggleMode = false
    @Published var historyChoreFilter: [Int]?
    @Published var historyFilterOpen = false
    /// Per-user volume display/input unit ("ml" | "oz"); volumes stay mL in the API.
    @Published var volumeUnit: String = "ml"
    /// The single running duration timer (persisted via `DurationTimer`).
    @Published var activeTimer: ActiveTimer?
    /// Offline-queued logs shown inline in Activity with a "pending" badge
    /// until the queue replays.
    @Published var pendingLogs: [PendingLog] = []
    /// Shared per-day diary notes keyed by "YYYY-MM-DD" (Phase 5.4).
    @Published var dayNotes: [String: String] = [:]
    /// Deep-link target from a notification "Log now" action (parity with the
    /// PWA's `/?quicklog=chore:<id>`); HomeView consumes it once chores exist.
    @Published var pendingQuickLogChoreId: Int?
    /// Invite code from a `/join?code=…` universal link opened while logged
    /// out; OnboardingView prefills its Join tab from it.
    @Published var pendingInviteCode: String?
    /// Connectivity from DataLoader's NWPathMonitor; drives the global
    /// offline banner (C4). Not reset on logout — it's device state.
    @Published var isOffline = false
    /// Stats customization (P4): stored section order/hidden sets and the
    /// user-defined widgets, synced via `/api/preferences`.
    @Published var statsSectionOrder: [String] = []
    @Published var statsSectionHidden: [String] = []
    @Published var statsWidgets: [StatsWidget] = []

    func reset() {
        user = nil
        household = nil
        userHouseholds = []
        activeHouseholdId = nil
        members = []
        invites = []
        chores = []
        todayLogs = []
        schedules = []
        latestLogs = [:]
        notifications = []
        unreadNotifications = 0
        notificationPrefs = nil
        availableNotificationTypes = []
        choreReminderPrefs = []
        choreOrder = []
        hiddenHomeChoreIDs = []
        currentTab = .home
        homeView = .log
        activeSheet = nil
        toast = nil
        jiggleMode = false
        historyChoreFilter = nil
        historyFilterOpen = false
        volumeUnit = "ml"
        // activeTimer intentionally survives reset: the PWA's localStorage
        // timer is device-scoped, not session-scoped.
        pendingLogs = []
        dayNotes = [:]
        pendingQuickLogChoreId = nil
        pendingInviteCode = nil
        statsSectionOrder = []
        statsSectionHidden = []
        statsWidgets = []
    }

    func resetHouseholdScoped() {
        household = nil
        activeHouseholdId = nil
        members = []
        invites = []
        chores = []
        todayLogs = []
        schedules = []
        latestLogs = [:]
        choreOrder = []
        hiddenHomeChoreIDs = []
        historyChoreFilter = nil
        historyFilterOpen = false
        dayNotes = [:]
        statsSectionOrder = []
        statsSectionHidden = []
        statsWidgets = []
    }
}
