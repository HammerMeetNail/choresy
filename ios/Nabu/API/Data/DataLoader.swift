import Foundation
import Network

@MainActor
final class DataLoader: ObservableObject {
    private(set) var api: APIClient
    private(set) var state: AppState

    private(set) var household: HouseholdDataLoader!
    private(set) var chores: ChoreDataLoader!
    private(set) var logs: LogDataLoader!
    private(set) var schedules: ScheduleDataLoader!
    private(set) var notifs: NotificationDataLoader!
    private(set) var preferences: PreferencesDataLoader!

    private var pathMonitor: NWPathMonitor?

    init() {
        self.api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
        self.state = AppState()
    }

    func configure(api: APIClient, state: AppState) {
        self.api = api
        self.state = state
        self.household = HouseholdDataLoader(api: api, state: state)
        self.chores = ChoreDataLoader(api: api, state: state)
        self.logs = LogDataLoader(api: api, state: state)
        self.schedules = ScheduleDataLoader(api: api, state: state)
        self.notifs = NotificationDataLoader(api: api, state: state)
        self.preferences = PreferencesDataLoader(api: api, state: state)
        startConnectivityMonitor()
    }

    /// Replays the offline log queue when connectivity returns (the
    /// foreground path is `foregroundRefresh`). Mirrors the PWA's
    /// `online` listener.
    private func startConnectivityMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                await self?.flushOfflineQueue()
            }
        }
        monitor.start(queue: DispatchQueue(label: "nabu.offline-queue.path-monitor"))
        pathMonitor = monitor
    }

    /// Replays queued offline logs; on success clears the synthetic pending
    /// rows and refetches so Activity shows the server's copies.
    func flushOfflineQueue() async {
        guard state.user != nil else { return }
        let logStore = LogStore(api: api)
        let synced = await logStore.replayOfflineQueue()
        if synced > 0 {
            state.pendingLogs = []
            await logs.loadTodayData()
            await logs.loadLatestLogsData()
        }
    }

    // Called after initial auth (login/register/onboarding)
    func reloadAfterAuth() async {
        NSLog("[Nabu] DataLoader.reloadAfterAuth starting")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.household.loadHouseholdData() }
            group.addTask { await self.preferences.loadPreferences() }
            group.addTask { await self.notifs.loadNotificationPreferences() }
        }
        await preferences.syncTimezone()

        guard state.household != nil else {
            NSLog("[Nabu] DataLoader: no household, aborting second task group")
            return
        }

        NSLog("[Nabu] DataLoader: loading chores/logs/schedules/notifs")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.chores.loadChoreData() }
            group.addTask { await self.logs.loadTodayData() }
            group.addTask { await self.logs.loadLatestLogsData() }
            group.addTask { await self.schedules.loadSchedules() }
            group.addTask { await self.notifs.loadNotifData() }
        }
        NSLog("[Nabu] DataLoader.reloadAfterAuth complete. schedules=\(state.schedules.count) chores=\(state.chores.count)")

        // Replay anything left in the offline queue from a previous session.
        await flushOfflineQueue()
    }

    // Called on foreground / visibility change
    func foregroundRefresh() async {
        guard state.user != nil else { return }
        await flushOfflineQueue()
        await notifs.loadNotifData()
        if state.household != nil {
            await household.loadHouseholdData()
        }
    }
}
