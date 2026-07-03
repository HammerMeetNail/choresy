import Foundation

/// View model for the Stats tab. Mirrors the PWA's stats data-loading and
/// interaction semantics (`app.js` loadAllStatsData / loadWidgetData /
/// loadChoreAnalyticsData / loadBabyTimeSeries and the stats-* action
/// handlers): same endpoints, same query parameters, same caching keys, same
/// fetch caps. Presentation is native (§2.1); behavior must not diverge.
@MainActor
final class StatsModel: ObservableObject {

    /// Bounds the per-chore/per-widget time-series fan-out on a single Stats
    /// load, so a household with many metric/indicator chores can't trigger
    /// an unbounded burst of full-year-scan requests (PWA
    /// MAX_ANALYTICS_FETCHES).
    static let maxAnalyticsFetches = 15

    private(set) var api: APIClient?
    private(set) var state: AppState?
    private(set) var preferences: PreferencesDataLoader?

    @Published var isLoading = true

    // Overview
    @Published var overview: StatsOverview?

    // Heatmap
    @Published var heatmap: [HeatmapEntry] = []

    // Busy hours (+ filters)
    @Published var busyHours: [BusyHour] = []
    @Published var busyHoursStart = ""
    @Published var busyHoursEnd = ""
    @Published var bhChoreId: Int?
    @Published var bhUserId: Int?
    @Published var bhFilterStart = ""
    @Published var bhFilterEnd = ""

    // Leaderboard
    @Published var leaderboardPeriod = "week"
    @Published var leaderboardByPeriod: [String: LeaderboardResponse] = [:]

    // Top chores
    @Published var topChoresPeriod = "month"
    @Published var topChoresUserId: Int = 0
    @Published var topChoresByUserAndPeriod: [String: [TopChore]] = [:]

    // Categories (breakdown endpoint, period-scoped — #84/#85 convergence)
    @Published var categoriesPeriod = "week"
    @Published var categoriesBreakdown: [BreakdownEntry] = []

    // Chores section (period-scoped)
    @Published var choreStatsPeriod = "month"
    @Published var choreStats: [ChoreStat] = []
    @Published var choreStatsStart = ""
    @Published var choreStatsEnd = ""

    // Baby care
    @Published var feedBabyPeriod = "daily"
    @Published var changeBabyPeriod = "daily"
    @Published var feedBabyTS: ChoreTimeSeries?
    @Published var changeBabyTS: ChoreTimeSeries?

    // Feeding gaps (cluster feeding)
    @Published var feedingGaps: [FeedingGap] = []
    @Published var feedingGapsStart = ""
    @Published var feedingGapsEnd = ""
    @Published var feedingGapsExplainerVisible = false

    // Generalized per-chore analytics (chore:<id> sections)
    @Published var choreTimeSeries: [Int: ChoreTimeSeries] = [:]
    @Published var choreAnalyticsPeriod: [Int: String] = [:]

    // Widget data, keyed by widget id. Each entry is the per-chore results
    // the widget renders from (time-series or summary, by widget type).
    @Published var widgetTimeSeries: [String: [ChoreTimeSeries]] = [:]
    @Published var widgetSummaries: [String: [ChoreSummary]] = [:]

    // Customize panel
    @Published var customizeOpen = false
    @Published var widgetWizardOpen = false

    func configure(api: APIClient, state: AppState) {
        self.api = api
        self.state = state
        self.preferences = PreferencesDataLoader(api: api, state: state)
    }

    // MARK: - Derived

    var chores: [Chore] { state?.chores ?? [] }

    private var feedBabyChore: Chore? { chores.first { $0.name == "Feed Baby" } }
    private var changeBabyChore: Chore? { chores.first { $0.name == "Change Baby" } }

    /// The ordered, visible section keys for the current preferences +
    /// eligible dynamic sections.
    var sectionLayout: [String] {
        let dynamicKeys = StatsSections.eligibleChoreSectionKeys(chores)
            + (state?.statsWidgets ?? []).map { StatsSections.widgetSectionKey($0.id) }
        return StatsSections.resolveLayout(
            userOrder: state?.statsSectionOrder ?? [],
            userHidden: state?.statsSectionHidden ?? [],
            dynamicKeys: dynamicKeys
        )
    }

    /// All section keys (visible and hidden) in customize-panel order.
    var customizeKeys: [String] {
        let dynamicKeys = StatsSections.eligibleChoreSectionKeys(chores)
            + (state?.statsWidgets ?? []).map { StatsSections.widgetSectionKey($0.id) }
        return StatsSections.resolveLayout(
            userOrder: state?.statsSectionOrder ?? [],
            userHidden: [],
            dynamicKeys: dynamicKeys
        )
    }

    var currentLeaderboard: [LeaderboardEntry] {
        if let resp = leaderboardByPeriod[leaderboardPeriod] { return resp.leaderboard }
        if leaderboardPeriod == "week", let ov = overview { return ov.leaderboard }
        return []
    }

    var currentTopChores: [TopChore] {
        topChoresByUserAndPeriod["\(topChoresUserId)-\(topChoresPeriod)"] ?? []
    }

    // MARK: - Load

    /// `showSpinner: false` refreshes in place (pull-to-refresh) without
    /// flipping the whole tab back to the loading state.
    func loadAll(showSpinner: Bool = true) async {
        guard api != nil else { return }
        if showSpinner { isLoading = true }
        if topChoresUserId == 0 { topChoresUserId = state?.user?.id ?? 0 }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadOverview() }
            group.addTask { await self.loadHeatmap() }
            group.addTask { await self.loadBusyHours() }
            group.addTask { await self.loadChoreStats() }
            group.addTask { await self.loadCategories() }
            group.addTask { await self.loadTopChores() }
            group.addTask { await self.loadLeaderboard() }
            group.addTask { await self.loadBabyTimeSeries() }
            group.addTask { await self.loadFeedingGaps() }
            group.addTask { await self.loadChoreAnalytics() }
            group.addTask { await self.loadWidgetData() }
            await group.waitForAll()
        }

        isLoading = false
    }

    private func loadOverview() async {
        guard let api else { return }
        if let data: OverviewResponse = try? await api.get("/api/stats/overview") {
            overview = data.overview
        }
    }

    private func loadHeatmap() async {
        guard let api else { return }
        if let data: HeatmapResponse = try? await api.get("/api/stats/heatmap") {
            heatmap = data.heatmap
        }
    }

    func loadBusyHours() async {
        guard let api else { return }
        var query: [URLQueryItem] = []
        if let cid = bhChoreId { query.append(URLQueryItem(name: "choreId", value: "\(cid)")) }
        if let uid = bhUserId { query.append(URLQueryItem(name: "userId", value: "\(uid)")) }
        if !bhFilterStart.isEmpty { query.append(URLQueryItem(name: "start", value: bhFilterStart)) }
        if !bhFilterEnd.isEmpty { query.append(URLQueryItem(name: "end", value: bhFilterEnd)) }
        if let data: BusyHoursResponse = try? await api.get("/api/stats/busy-hours", query: query) {
            busyHours = data.busyHours
            busyHoursStart = data.start
            busyHoursEnd = data.end
        }
    }

    private func loadChoreStats() async {
        guard let api else { return }
        if let data: ChoreStatsResponse = try? await api.get(
            "/api/stats/chores",
            query: [URLQueryItem(name: "period", value: choreStatsPeriod)]
        ) {
            choreStats = data.choreStats
            choreStatsStart = data.start
            choreStatsEnd = data.end
        }
    }

    private func loadCategories() async {
        guard let api else { return }
        if let data: BreakdownResponse = try? await api.get(
            "/api/stats/breakdown",
            query: [URLQueryItem(name: "period", value: categoriesPeriod)]
        ) {
            categoriesBreakdown = data.breakdown
        }
    }

    private func loadTopChores() async {
        guard let api else { return }
        let key = "\(topChoresUserId)-\(topChoresPeriod)"
        var query = [URLQueryItem(name: "period", value: topChoresPeriod)]
        if topChoresUserId != 0 {
            query.insert(URLQueryItem(name: "userId", value: "\(topChoresUserId)"), at: 0)
        }
        if let data: TopChoresResponse = try? await api.get("/api/stats/top-chores", query: query) {
            topChoresByUserAndPeriod[key] = data.topChores
        }
    }

    private func loadLeaderboard() async {
        guard let api else { return }
        guard leaderboardByPeriod[leaderboardPeriod] == nil else { return }
        if let data: LeaderboardResponse = try? await api.get(
            "/api/stats/leaderboard",
            query: [URLQueryItem(name: "period", value: leaderboardPeriod)]
        ) {
            leaderboardByPeriod[leaderboardPeriod] = data
        }
    }

    func loadBabyTimeSeries() async {
        guard let api else { return }
        if let fb = feedBabyChore {
            if let data: TimeSeriesResponse = try? await api.get(
                "/api/stats/chores/\(fb.id)/time-series",
                query: [URLQueryItem(name: "period", value: feedBabyPeriod)]
            ) {
                feedBabyTS = data.timeSeries
            }
        }
        if let cb = changeBabyChore {
            if let data: TimeSeriesResponse = try? await api.get(
                "/api/stats/chores/\(cb.id)/time-series",
                query: [URLQueryItem(name: "period", value: changeBabyPeriod)]
            ) {
                changeBabyTS = data.timeSeries
            }
        }
    }

    /// Loads the cluster-feeding gap scatter. The stored end date is
    /// inclusive (what the pickers show); the API gets an exclusive end one
    /// day later (PWA `apiExclusiveEnd`). Defaults to the last 7 days.
    func loadFeedingGaps() async {
        guard let api, feedBabyChore != nil else { return }
        let today = Date()
        if feedingGapsEnd.isEmpty { feedingGapsEnd = Self.dateString(today) }
        if feedingGapsStart.isEmpty {
            feedingGapsStart = Self.dateString(Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today)
        }
        let query = [
            URLQueryItem(name: "start", value: feedingGapsStart),
            URLQueryItem(name: "end", value: Self.exclusiveEnd(feedingGapsEnd)),
        ]
        if let data: FeedingGapsResponse = try? await api.get("/api/stats/feeding-gaps", query: query) {
            feedingGaps = data.feedingGaps
        }
    }

    /// Quick-range buttons on the cluster feeding column: Day / Week / 2 Weeks.
    func setFeedingGapsQuickRange(days: Int) async {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        feedingGapsEnd = Self.dateString(end)
        feedingGapsStart = Self.dateString(start)
        await loadFeedingGaps()
    }

    /// Whether a quick-range button is the active one for the current dates
    /// (PWA `isQuickActive`).
    func isFeedingGapsQuickActive(days: Int) -> Bool {
        if feedingGapsStart.isEmpty || feedingGapsEnd.isEmpty { return days == 7 }
        guard let end = Self.parseDate(feedingGapsEnd) else { return false }
        let expected = Calendar.current.date(byAdding: .day, value: -(days - 1), to: end)
        return expected.map { Self.dateString($0) == feedingGapsStart } ?? false
    }

    /// Fetches daily time-series for chores with a generalized analytics
    /// section, skipping hidden sections, capped at `maxAnalyticsFetches`.
    func loadChoreAnalytics() async {
        guard let api else { return }
        let hidden = Set(state?.statsSectionHidden ?? [])
        let eligible = chores
            .filter { StatsSections.choreHasAnalytics($0) }
            .filter { !hidden.contains(StatsSections.choreSectionKey($0.id)) }
            .prefix(Self.maxAnalyticsFetches)
        guard !eligible.isEmpty else { return }
        await withTaskGroup(of: (Int, ChoreTimeSeries?).self) { group in
            for chore in eligible {
                let grain = StatsSections.choreAnalyticsGrain(choreAnalyticsPeriod[chore.id] ?? "day")
                group.addTask {
                    let data: TimeSeriesResponse? = try? await api.get(
                        "/api/stats/chores/\(chore.id)/time-series",
                        query: [URLQueryItem(name: "period", value: grain)]
                    )
                    return (chore.id, data?.timeSeries)
                }
            }
            for await (id, ts) in group {
                if let ts { choreTimeSeries[id] = ts }
            }
        }
    }

    /// Day/week/month toggle on a per-chore analytics card: the period picks
    /// the chart's bucket grain and refetches that chore's series.
    func setChoreAnalyticsPeriod(_ period: String, choreId: Int) async {
        guard let api else { return }
        guard choreAnalyticsPeriod[choreId] ?? "day" != period else { return }
        choreAnalyticsPeriod[choreId] = period
        if let data: TimeSeriesResponse = try? await api.get(
            "/api/stats/chores/\(choreId)/time-series",
            query: [URLQueryItem(name: "period", value: StatsSections.choreAnalyticsGrain(period))]
        ) {
            choreTimeSeries[choreId] = data.timeSeries
        }
    }

    /// Fetches the data each visible user-defined widget renders from:
    /// timeseries widgets read the time-series endpoint at the widget's
    /// grain; total/member-split (and any other type) read the period-scoped
    /// summary so the widget's period actually bounds the numbers.
    /// last-done reads latest-per-chore already in app state — no fetch.
    func loadWidgetData() async {
        guard let api else { return }
        let hidden = Set(state?.statsSectionHidden ?? [])
        let widgets = (state?.statsWidgets ?? [])
            .filter { !hidden.contains(StatsSections.widgetSectionKey($0.id)) }
            .prefix(Self.maxAnalyticsFetches)
        guard !widgets.isEmpty else { return }
        for widget in widgets {
            await loadData(for: widget, api: api)
        }
    }

    func loadData(for widget: StatsWidget, api: APIClient) async {
        if widget.type == "last-done" { return }
        if widget.type == "timeseries" {
            let grain = StatsSections.widgetGrain(widget)
            var results: [ChoreTimeSeries] = []
            for cid in widget.choreIds {
                if let data: TimeSeriesResponse = try? await api.get(
                    "/api/stats/chores/\(cid)/time-series",
                    query: [URLQueryItem(name: "period", value: grain)]
                ) {
                    results.append(data.timeSeries)
                }
            }
            widgetTimeSeries[widget.id] = results
            return
        }
        var results: [ChoreSummary] = []
        let period = widget.period.isEmpty ? "week" : widget.period
        for cid in widget.choreIds {
            if let data: ChoreSummaryResponse = try? await api.get(
                "/api/stats/chores/\(cid)/summary",
                query: [URLQueryItem(name: "period", value: period)]
            ) {
                results.append(data.summary)
            }
        }
        widgetSummaries[widget.id] = results
    }

    // MARK: - Period toggles

    func setLeaderboardPeriod(_ period: String) async {
        guard period != leaderboardPeriod else { return }
        leaderboardPeriod = period
        await loadLeaderboard()
    }

    func setTopChoresPeriod(_ period: String) async {
        guard period != topChoresPeriod else { return }
        topChoresPeriod = period
        if currentTopChores.isEmpty { await loadTopChores() }
    }

    func setTopChoresUser(_ userId: Int) async {
        guard userId != topChoresUserId else { return }
        topChoresUserId = userId
        if topChoresByUserAndPeriod["\(userId)-\(topChoresPeriod)"] == nil {
            await loadTopChores()
        }
    }

    func setCategoriesPeriod(_ period: String) async {
        guard period != categoriesPeriod else { return }
        categoriesPeriod = period
        await loadCategories()
    }

    func setChoreStatsPeriod(_ period: String) async {
        guard period != choreStatsPeriod else { return }
        choreStatsPeriod = period
        await loadChoreStats()
    }

    func setBabyPeriod(_ period: String, type: String) async {
        if type == "feed" {
            guard period != feedBabyPeriod else { return }
            feedBabyPeriod = period
        } else {
            guard period != changeBabyPeriod else { return }
            changeBabyPeriod = period
        }
        await loadBabyTimeSeries()
    }

    // MARK: - Widgets (customize)

    /// Adds a widget from the wizard. The server assigns the id and echoes
    /// the normalized list; new widgets default to period "week" and expose
    /// a day/week/month toggle on the card.
    func addWidget(title: String, type: String, metric: String, choreIds: [Int]) async -> Bool {
        guard let state, let preferences else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let widget = StatsWidget(
            id: "", type: type, choreIds: choreIds, metric: metric,
            agg: "", period: "week", grain: "",
            title: trimmed.isEmpty ? "Widget" : trimmed
        )
        let saved = await preferences.saveStatsWidgets(state.statsWidgets + [widget])
        guard saved else { return false }
        await loadWidgetData()
        return true
    }

    func removeWidget(id: String) async -> Bool {
        guard let state, let preferences else { return false }
        let widgets = state.statsWidgets.filter { $0.id != id }
        return await preferences.saveStatsWidgets(widgets)
    }

    /// Day/week/month toggle on a widget card: persists the new period into
    /// the stored widget, then refetches that widget's data.
    func setWidgetPeriod(_ period: String, widgetId: String) async -> Bool {
        guard let api, let state, let preferences else { return false }
        guard let current = state.statsWidgets.first(where: { $0.id == widgetId }),
              current.period != period else { return true }
        let widgets = state.statsWidgets.map { w in
            w.id == widgetId
                ? StatsWidget(id: w.id, type: w.type, choreIds: w.choreIds, metric: w.metric,
                              agg: w.agg, period: period, grain: w.grain, title: w.title)
                : w
        }
        let saved = await preferences.saveStatsWidgets(widgets)
        guard saved else { return false }
        if let updated = state.statsWidgets.first(where: { $0.id == widgetId }) {
            await loadData(for: updated, api: api)
        }
        return true
    }

    // MARK: - Sections (customize)

    /// Persists a reorder from the customize panel. Saves the full ordered
    /// key list (visible + hidden + dynamic) plus any missing canonical keys,
    /// like the PWA's drop handler.
    func moveSections(from source: IndexSet, to destination: Int) async {
        guard let preferences else { return }
        var keys = customizeKeys
        keys.move(fromOffsets: source, toOffset: destination)
        var seen = Set<String>()
        let all = (keys + StatsSections.all).filter { seen.insert($0).inserted }
        await preferences.saveStatsSectionOrder(all)
    }

    func setSectionVisible(_ key: String, visible: Bool) async {
        guard let state, let preferences else { return }
        var hidden = state.statsSectionHidden
        if visible {
            hidden.removeAll { $0 == key }
        } else if !hidden.contains(key) {
            hidden.append(key)
        }
        let saved = await preferences.saveStatsSectionHidden(hidden)
        // Newly-revealed sections may have never fetched their data.
        if saved && visible {
            if StatsSections.isChoreSectionKey(key) { await loadChoreAnalytics() }
            if StatsSections.isWidgetSectionKey(key) { await loadWidgetData() }
        }
    }

    // MARK: - Date helpers

    nonisolated static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    /// The stats date pickers show an inclusive end date; the feeding-gaps
    /// API takes an exclusive end (PWA `apiExclusiveEnd`).
    nonisolated static func exclusiveEnd(_ inclusiveEnd: String) -> String {
        guard let d = parseDate(inclusiveEnd),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: d) else {
            return inclusiveEnd
        }
        return dateString(next)
    }
}
