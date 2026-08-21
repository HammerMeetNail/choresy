import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var environment: AppEnvironment
    @StateObject private var auth = AuthStore(api: APIClient(baseURL: URL(string: "http://localhost:8080")!))
    @StateObject private var dataLoader = DataLoader()
    @State private var hasCheckedSession = false
    @State private var hasLoadedData = false

    var body: some View {
        Group {
            if !hasCheckedSession {
                SkeletonScreen()
            } else if state.user == nil {
                LoginView(auth: auth, apiBaseURL: environment.baseURL)
                    .onAppear { auth.configure(api: environment.apiClient) }
            } else if state.household == nil {
                OnboardingView(auth: auth)
                    .onAppear { auth.configure(api: environment.apiClient) }
                    .onChange(of: state.household) { _, newHousehold in
                        if newHousehold != nil {
                            Task { await loadAppData() }
                        }
                    }
            } else if !hasLoadedData {
                SkeletonScreen()
                    .task { await loadAppData() }
            } else {
                MainTabView(dataLoader: dataLoader)
            }
        }
        .pageBackground()
        .task {
            if !hasCheckedSession {
                let args = ProcessInfo.processInfo.arguments
                dataLoader.configure(api: environment.apiClient, state: state)
                auth.configure(api: environment.apiClient)
                // Restore a duration timer that survived relaunch, and show
                // any still-queued offline logs as pending rows.
                state.activeTimer = DurationTimer.load()
                state.pendingLogs = OfflineLogQueue.shared.items.map {
                    PendingLog(body: $0.body, fallbackUserId: nil)
                }
                if TestHooks.seedHomeForUITest {
                    hasCheckedSession = true
                    hasLoadedData = true
                } else if let (email, password) = parseTestCreds(args) {
                    // Pre-flight GET to obtain a CSRF cookie before the register POST.
                    let _: StatusResponse? = try? await auth.api.get("/api/me")
                    if let user = await auth.register(email: email, password: password) {
                        state.user = user
                        if let hh = await auth.createHousehold(name: "E2E Home", initials: "EH") {
                            state.household = hh
                            _ = await auth.seedDefaults()
                            await loadAppData()
                        }
                    } else {
                        // Registration failed — show login screen
                        await auth.logout()
                    }
                    hasCheckedSession = true
                } else {
                    state.user = await auth.loadSession()
                    hasCheckedSession = true
                    NSLog("[Nabu] ContentView: user=\(state.user?.email ?? "nil") householdId=\(state.user?.householdId ?? -1)")
                    if state.user?.householdId != nil {
                        await loadAppData()
                    }
                }
            }
        }
        .onChange(of: state.user) { oldUser, newUser in
            if newUser == nil {
                state.reset()
                hasLoadedData = false
                Task { await auth.logout() }
            } else if newUser?.householdId != nil {
                Task { await loadAppData() }
            }
            if oldUser == nil, newUser != nil {
                // Fresh sign-in: re-register the push token if permission was
                // already granted (mirrors the PWA's maybeSubscribePush after
                // login), and consume a /join link that arrived logged-out.
                Task { await PushRegistrationController.shared.syncIfAuthorized() }
                if let code = state.pendingInviteCode, newUser?.householdId == nil {
                    Task { await consumePendingInvite(code) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await dataLoader.foregroundRefresh() }
        }
        // Universal links (verify email, magic login, invite) and the
        // quicklog deep link. SwiftUI delivers universal links through
        // onOpenURL; the NSUserActivity path covers hand-off style delivery.
        .onOpenURL { url in
            Task { await handleIncomingURL(url) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                Task { await handleIncomingURL(url) }
            }
        }
    }

    /// Handles a universal link or deep link — same endpoints and outcomes as
    /// the PWA's route handling for /verify-email, /magic-login, and /join.
    func handleIncomingURL(_ url: URL) async {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .verifyEmail(let token):
            let _: StatusResponse? = try? await environment.apiClient.get(
                "/api/auth/email/verify", query: [URLQueryItem(name: "token", value: token)])
            // Refresh the session so emailVerified flips in Settings.
            if let user = await auth.loadSession() {
                state.user = user
            }
        case .magicLogin(let token):
            do {
                let response: UserResponse = try await environment.apiClient.get(
                    "/api/auth/magic-link/consume", query: [URLQueryItem(name: "token", value: token)])
                if let user = response.user {
                    state.user = user
                }
            } catch {
                // Invalid/expired link: stay where we are, like the PWA.
            }
        case .joinHousehold(let code):
            if state.user == nil {
                // Consumed after sign-in; OnboardingView also prefills from it.
                state.pendingInviteCode = code
            } else if state.household == nil {
                await consumePendingInvite(code)
            }
            // Already in a household: the link just opens the app (PWA parity).
        case .quickLog(let target):
            state.currentTab = .home
            state.homeView = .log
            state.pendingQuickLog = target
        case .showHomeLog:
            state.currentTab = .home
            state.homeView = .log
        case .showActivity:
            state.currentTab = .activity
        }
    }

    private func consumePendingInvite(_ code: String) async {
        if let household = await auth.joinHousehold(code: code) {
            state.pendingInviteCode = nil
            _ = await auth.seedDefaults()
            state.household = household
            state.activeHouseholdId = household.id
        }
    }

    func loadAppData() async {
        guard state.user != nil else { return }
        NSLog("[Nabu] ContentView.loadAppData calling reloadAfterAuth")
        await dataLoader.reloadAfterAuth()
        hasLoadedData = state.household != nil
        NSLog("[Nabu] ContentView.loadAppData done. hasLoadedData=\(hasLoadedData)")
    }

    private func parseTestCreds(_ args: [String]) -> (String, String)? {
        // Format: -nabuAutoRegister email password (three consecutive args)
        if let idx = args.firstIndex(of: "-nabuAutoRegister"), idx + 2 < args.count {
            return (args[idx + 1], args[idx + 2])
        }
        // Format: -NabuEmail email -NabuPassword password
        if let ei = args.firstIndex(of: "-NabuEmail"), ei + 1 < args.count,
           let pi = args.firstIndex(of: "-NabuPassword"), pi + 1 < args.count {
            return (args[ei + 1], args[pi + 1])
        }
        return nil
    }
}

struct MainTabView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var environment: AppEnvironment
    @ObservedObject var dataLoader: DataLoader

    var body: some View {
        tabs
            .overlay(alignment: .top) {
                VStack(spacing: 6) {
                    TimerChipView()
                    if state.isOffline {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 4)
                .animation(Motion.slide ?? Motion.fade, value: state.isOffline)
            }
    }

    private var tabs: some View {
        TabView(selection: $state.currentTab) {
            StatsView()
                .tabItem {
                    Label(MainTab.stats.title, systemImage: MainTab.stats.systemImage)
                }
                .tag(MainTab.stats)

            ActivityView(activityStore: ActivityStore(api: environment.apiClient),
                         logStore: LogStore(api: environment.apiClient))
                .tabItem {
                    Label(MainTab.activity.title, systemImage: MainTab.activity.systemImage)
                }
                .tag(MainTab.activity)

            HomeView(logStore: LogStore(api: environment.apiClient))
                .tabItem {
                    Label(MainTab.home.title, systemImage: MainTab.home.systemImage)
                }
                .tag(MainTab.home)

            ScheduleView(scheduleStore: ScheduleStore(api: environment.apiClient))
                .tabItem {
                    Label(MainTab.schedule.title, systemImage: MainTab.schedule.systemImage)
                }
                .tag(MainTab.schedule)

            HouseholdView()
                .tabItem {
                    Label(MainTab.settings.title, systemImage: MainTab.settings.systemImage)
                }
                // badge(0) renders nothing, so the hidden preference simply
                // suppresses the count; notifications still accumulate.
                .badge(state.hideNotificationBadge ? 0 : state.unreadNotifications)
                .tag(MainTab.settings)
        }
        .tint(DesignColors.primary)
    }
}
