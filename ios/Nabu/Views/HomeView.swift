import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var environment: AppEnvironment
    @State private var showingQuickLog = false
    @State private var selectedChore: Chore?   // non-nil drives the log sheet
    @State private var editingChore: Chore?    // non-nil drives the chore editor
    @State private var editingLog: ChoreLog?
    @State private var undoLogId: Int?
    @State private var undoChoreName: String?
    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerTabs
                if state.homeView == .manage {
                    ManageChoresView(choreStore: ChoreStore(api: environment.apiClient))
                } else {
                    homeGridContent
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if state.homeView == .log {
                        Button {
                            showingQuickLog = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .accessibilityIdentifier("quick-log-button")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if state.homeView == .log {
                        Button {
                            state.jiggleMode.toggle()
                        } label: {
                            Image(systemName: state.jiggleMode ? "checkmark" : "pencil")
                        }
                        .accessibilityIdentifier("jiggle-button")
                    }
                }
            }
            .sheet(isPresented: $showingQuickLog) {
                QuickLogSheet(state: state, logStore: logStore)
            }
            .sheet(item: $editingChore) { chore in
                ChoreEditView(chore: chore, choreStore: ChoreStore(api: environment.apiClient))
            }
            // Use .sheet(item:) so the chore is always non-nil in the closure — no
            // if-let race between selectedChore being set and the closure being evaluated.
            .sheet(item: $selectedChore) { chore in
                LogSheet(
                    state: state,
                    chore: chore,
                    log: editingLog,
                    logStore: logStore,
                    onUndo: { logId, choreName in
                        undoLogId = logId
                        undoChoreName = choreName
                        selectedChore = nil   // dismisses the sheet
                    }
                )
            }
            // Haptics (C3): success when a log lands (the undo toast appears),
            // light impact entering/leaving jiggle mode.
            .sensoryFeedback(.success, trigger: undoLogId) { _, new in new != nil }
            .sensoryFeedback(.impact(weight: .light), trigger: state.jiggleMode)
            // Notification "Log now" deep link: open the log sheet pre-filled
            // for the reminder's chore (parity with /?quicklog=chore:<id>).
            .onAppear { consumePendingQuickLog() }
            .onChange(of: state.pendingQuickLog) { _, _ in consumePendingQuickLog() }
            .onChange(of: state.chores) { _, _ in consumePendingQuickLog() }
            .overlay(alignment: .bottom) {
                if let logId = undoLogId, let name = undoChoreName {
                    UndoToast(choreName: name) {
                        Task {
                            do {
                                let _: StatusResponse = try await logStore.deleteLog(logId: logId)
                                state.todayLogs.removeAll { $0.id == logId }
                                state.latestLogs.removeValue(forKey: logId)
                            } catch {
                                // Silent failure
                            }
                            undoLogId = nil
                            undoChoreName = nil
                        }
                    } onDismiss: {
                        undoLogId = nil
                        undoChoreName = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var headerTabs: some View {
        PillTabBar(
            selection: $state.homeView,
            tabs: Array(HomeViewMode.allCases),
            labelFor: { $0.title }
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var homeGridContent: some View {
        let chores = sortedChores()
        if chores.isEmpty {
            return AnyView(
                ContentUnavailableView {
                    Label("No chores yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("Add the chores your household tracks and they'll appear here as one-tap tiles.")
                } actions: {
                    Button("Add Chores") {
                        state.homeView = .manage
                    }
                    .buttonStyle(.borderedProminent)
                }
            )
        }
        return AnyView(
            ScrollView {
                HomeGrid(
                    chores: chores,
                    latestLogs: state.latestLogs,
                    isJiggling: state.jiggleMode,
                    onTap: { chore in
                        editingLog = nil
                        selectedChore = chore
                    },
                    onEdit: { chore in
                        editingChore = chore
                    },
                    onHide: { chore in
                        hideFromHome(chore)
                    }
                )
                .padding()
            }
            .refreshable {
                await refreshHome()
            }
        )
    }

    /// Opens the log sheet for a pending quick-log target once the chore
    /// list is loaded. A target that doesn't resolve just lands on the grid,
    /// one tap from logging — same fallback as the PWA.
    private func consumePendingQuickLog() {
        guard let target = state.pendingQuickLog, !state.chores.isEmpty else { return }
        state.pendingQuickLog = nil
        let chore: Chore?
        switch target {
        case .chore(let id):
            chore = state.chores.first { $0.id == id }
        case .predefined(let key):
            chore = state.chores.first { $0.predefinedKey == key }
                ?? state.chores.first { $0.name == key }
        }
        guard let chore else { return }
        editingLog = nil
        selectedChore = chore
    }

    /// Hides a chore's tile from Home (context-menu action), persisting the
    /// same preference the Manage list's eye toggle writes.
    private func hideFromHome(_ chore: Chore) {
        var hidden = Set(state.hiddenHomeChoreIDs)
        hidden.insert(chore.id)
        let newHidden = Array(hidden)
        state.hiddenHomeChoreIDs = newHidden
        let patch = PatchUserPreferencesRequest(hiddenHomeChoreIds: newHidden)
        Task {
            let _: UserPreferencesResponse? = try? await environment.apiClient.patch("/api/preferences", body: patch)
        }
    }

    /// Pull-to-refresh: refetch the tiles' data (today's logs + latest-per-chore).
    private func refreshHome() async {
        let loader = LogDataLoader(api: environment.apiClient, state: state)
        await loader.loadTodayData()
        await loader.loadLatestLogsData()
    }

    private func sortedChores() -> [Chore] {
        let visible = state.chores.filter { !state.hiddenHomeChoreIDs.contains($0.id) }
        if state.choreOrder.isEmpty {
            return visible.sorted { $0.id < $1.id }
        }
        let orderMap = Dictionary(uniqueKeysWithValues: state.choreOrder.enumerated().map { ($1, $0) })
        return visible.sorted {
            (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max)
        }
    }
}
