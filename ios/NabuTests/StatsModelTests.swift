import XCTest
@testable import Nabu

/// Behavioral contract tests for `StatsModel` against a recording mock API:
/// the same endpoints, query parameters, and preference PATCH bodies the PWA
/// sends (`app.js` stats handlers) — behavior parity per plan §2.1.
@MainActor
final class StatsModelTests: XCTestCase {
    var state: AppState!
    var api: APIClient!
    var model: StatsModel!
    /// All request URLs seen by the mock, in order.
    var requests: RequestRecorder!

    final class RequestRecorder: @unchecked Sendable {
        var urls: [URL] = []
        var bodies: [String: Data] = [:]  // keyed by "METHOD path"
        private let lock = NSLock()
        func record(_ request: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            if let url = request.url { urls.append(url) }
            if let url = request.url, let body = request.httpBody {
                bodies["\(request.httpMethod ?? "") \(url.path)"] = body
            }
        }
        func urlStrings() -> [String] {
            lock.lock(); defer { lock.unlock() }
            return urls.map(\.absoluteString)
        }
    }

    override func setUp() {
        super.setUp()
        state = AppState()
        state.user = User(id: 7, householdId: 1, email: "t@t.com", displayName: "T",
                          avatarColor: "#000000", emailVerified: true, role: "owner", createdAt: Date())
        api = APIClient(baseURL: URL(string: "http://localhost:9999")!)
        requests = RequestRecorder()
        model = StatsModel()
    }

    /// Installs a mock that records every request and answers with canned
    /// JSON per path prefix.
    private func installMock(preferencesResponse: String? = nil) {
        let recorder = requests!
        api.mockHandler = { request in
            recorder.record(request)
            guard let url = request.url else { return nil }
            let path = url.path
            func ok(_ json: String) -> (Data, URLResponse) {
                (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                                  headerFields: ["Content-Type": "application/json"])!)
            }
            switch true {
            case path == "/api/stats/overview":
                return ok(#"{"overview":{"leaderboard":[],"streaks":{"current":2,"longest":5},"breakdown":[],"recap":{"totalChores":3,"topPerformer":null,"mostActiveDay":"Monday","byCategory":[]}}}"#)
            case path == "/api/stats/heatmap":
                return ok(#"{"heatmap":[{"date":"2026-07-01","count":3}]}"#)
            case path == "/api/stats/busy-hours":
                return ok(#"{"busyHours":[{"hour":9,"count":4}],"start":"2026-06-26","end":"2026-07-03"}"#)
            case path == "/api/stats/breakdown":
                return ok(#"{"breakdown":[{"category":"feeding","count":9}],"start":"2026-06-29","end":"2026-07-06"}"#)
            case path == "/api/stats/chores" && !path.contains("time-series"):
                return ok(#"{"choreStats":[{"choreId":1,"choreName":"Feed Baby","choreIcon":"🍼","totalThisWeek":4,"totalThisMonth":10,"totalInRange":6,"hasVolume":true,"hasIndicators":false}],"start":"2026-06-03","end":"2026-07-03"}"#)
            case path == "/api/stats/top-chores":
                return ok(#"{"topChores":[{"choreId":1,"choreName":"Feed Baby","choreIcon":"🍼","count":6}]}"#)
            case path == "/api/stats/leaderboard":
                return ok(#"{"leaderboard":[{"userId":7,"count":6}],"start":"2026-06-29","end":"2026-07-05"}"#)
            case path == "/api/stats/feeding-gaps":
                return ok(#"{"feedingGaps":[{"hour":3,"gapMinutes":95,"precedingVolume":120,"followUpVolume":40,"date":"2026-07-02"}]}"#)
            case path.hasSuffix("/time-series"):
                return ok(#"{"timeSeries":{"choreId":1,"choreName":"Feed Baby","choreIcon":"🍼","byMember":[{"userId":7,"count":3}],"periods":[{"start":"2026-07-01","end":"2026-07-02","count":2,"totalML":150}]}}"#)
            case path.hasSuffix("/summary"):
                return ok(#"{"summary":{"choreId":1,"count":5,"totalML":600,"totalDuration":0,"byMember":[{"userId":7,"count":5}]}}"#)
            case path == "/api/preferences" && request.httpMethod == "PATCH":
                return ok(preferencesResponse ?? #"{"preferences":{"choreOrder":[],"hiddenHomeChoreIds":[],"timezone":"UTC","statsSectionOrder":[],"statsSectionHidden":[],"statsWidgets":[]}}"#)
            default:
                return nil
            }
        }
        model.configure(api: api, state: state)
    }

    private func makeFeedBaby() -> Chore {
        Chore(id: 1, householdId: 1, name: "Feed Baby", icon: "🍼", color: "#EC4899",
              sortOrder: 0, category: "feeding", isPredefined: true, predefinedKey: "Feed Baby",
              createdBy: nil, createdAt: Date(), indicatorLabels: ["🍼 formula"],
              indicatorDefaults: [], hasVolumeML: true, metricType: "amount", metricUnit: "mL")
    }

    private func makeMedsChore(id: Int = 3) -> Chore {
        Chore(id: id, householdId: 1, name: "Meds", icon: "💊", color: "#EF4444",
              sortOrder: 1, category: "health", isPredefined: false, predefinedKey: nil,
              createdBy: nil, createdAt: Date(), indicatorLabels: ["am", "pm"],
              indicatorDefaults: [], hasVolumeML: false)
    }

    // MARK: - loadAll request semantics

    func testLoadAllSendsPeriodScopedRequests() async {
        state.chores = [makeFeedBaby()]
        installMock()
        await model.loadAll()

        let urls = requests.urlStrings()
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/breakdown?period=week") })
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/chores?period=month") })
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/leaderboard?period=week") })
        // Top chores default to the signed-in user, like the PWA.
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/top-chores?userId=7&period=month") })
        // Feeding gaps: last 7 days with an exclusive API end (inclusive + 1).
        let start = StatsModel.dateString(Calendar.current.date(byAdding: .day, value: -7, to: Date())!)
        let apiEnd = StatsModel.exclusiveEnd(StatsModel.dateString(Date()))
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/feeding-gaps?start=\(start)&end=\(apiEnd)") })

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.overview?.streaks.current, 2)
        XCTAssertEqual(model.choreStats.first?.totalInRange, 6)
        XCTAssertEqual(model.feedingGaps.first?.gapMinutes, 95)
        XCTAssertEqual(model.categoriesBreakdown.first?.count, 9)
    }

    func testPeriodTogglesRefetchWithNewPeriod() async {
        installMock()
        await model.setCategoriesPeriod("day")
        await model.setChoreStatsPeriod("week")
        await model.setLeaderboardPeriod("all")
        let urls = requests.urlStrings()
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/breakdown?period=day") })
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/chores?period=week") })
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/leaderboard?period=all") })
    }

    func testSamePeriodDoesNotRefetch() async {
        installMock()
        await model.setCategoriesPeriod("week") // already the default
        XCTAssertTrue(requests.urlStrings().isEmpty)
    }

    func testChoreAnalyticsUsesGrainAndSkipsHiddenAndCaps() async {
        state.chores = [makeMedsChore(id: 3), makeMedsChore(id: 4)]
        state.statsSectionHidden = ["chore:4"]
        installMock()
        await model.loadChoreAnalytics()
        let urls = requests.urlStrings()
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/chores/3/time-series?period=daily") })
        XCTAssertFalse(urls.contains { $0.contains("/api/stats/chores/4/") })

        await model.setChoreAnalyticsPeriod("month", choreId: 3)
        XCTAssertTrue(requests.urlStrings().contains { $0.contains("/api/stats/chores/3/time-series?period=monthly") })
    }

    // MARK: - Widgets

    func testWidgetDataFetchesSummaryForTotalAndTimeSeriesForCharts() async {
        state.statsWidgets = [
            makeWidget(id: "w1", type: "total", choreIds: [1], period: "month"),
            makeWidget(id: "w2", type: "timeseries", choreIds: [1], period: "month"),
            makeWidget(id: "w3", type: "last-done", choreIds: [1]),
        ]
        installMock()
        await model.loadWidgetData()
        let urls = requests.urlStrings()
        // total → period-scoped summary
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/chores/1/summary?period=month") })
        // timeseries at the widget grain (month → monthly)
        XCTAssertTrue(urls.contains { $0.contains("/api/stats/chores/1/time-series?period=monthly") })
        // last-done fetches nothing
        XCTAssertEqual(urls.filter { $0.contains("summary") }.count, 1)
        XCTAssertEqual(model.widgetSummaries["w1"]?.first?.count, 5)
        XCTAssertEqual(model.widgetTimeSeries["w2"]?.first?.periods.count, 1)
    }

    func testAddWidgetSendsEmptyIdAndWeekDefaultAndAdoptsServerEcho() async {
        let echo = #"{"preferences":{"choreOrder":[],"hiddenHomeChoreIds":[],"timezone":"UTC","statsSectionOrder":[],"statsSectionHidden":[],"statsWidgets":[{"id":"srv1","type":"total","choreIds":[1],"metric":"count","agg":"","period":"week","grain":"","title":"Bottles"}]}}"#
        installMock(preferencesResponse: echo)

        let ok = await model.addWidget(title: "  Bottles  ", type: "total", metric: "count", choreIds: [1])
        XCTAssertTrue(ok)

        let body = requests.bodies["PATCH /api/preferences"]
        XCTAssertNotNil(body)
        let json = try! JSONSerialization.jsonObject(with: body!) as! [String: Any]
        let widgets = json["statsWidgets"] as! [[String: Any]]
        XCTAssertEqual(widgets.count, 1)
        XCTAssertEqual(widgets[0]["id"] as? String, "")       // server assigns
        XCTAssertEqual(widgets[0]["period"] as? String, "week") // default; chosen on the card
        XCTAssertEqual(widgets[0]["title"] as? String, "Bottles") // trimmed
        // Server echo (with assigned id) wins.
        XCTAssertEqual(state.statsWidgets.map(\.id), ["srv1"])
    }

    func testSetWidgetPeriodPersistsAndRefetches() async {
        state.statsWidgets = [makeWidget(id: "w1", type: "total", choreIds: [1], period: "week")]
        let echo = #"{"preferences":{"choreOrder":[],"hiddenHomeChoreIds":[],"timezone":"UTC","statsSectionOrder":[],"statsSectionHidden":[],"statsWidgets":[{"id":"w1","type":"total","choreIds":[1],"metric":"count","agg":"sum","period":"day","grain":"daily","title":"Widget"}]}}"#
        installMock(preferencesResponse: echo)

        let ok = await model.setWidgetPeriod("day", widgetId: "w1")
        XCTAssertTrue(ok)

        let body = requests.bodies["PATCH /api/preferences"]!
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let widgets = json["statsWidgets"] as! [[String: Any]]
        XCTAssertEqual(widgets[0]["period"] as? String, "day")
        // Refetched the widget's summary at the persisted period.
        XCTAssertTrue(requests.urlStrings().contains { $0.contains("/api/stats/chores/1/summary?period=day") })
    }

    func testRemoveWidgetPatchesFilteredList() async {
        state.statsWidgets = [makeWidget(id: "w1"), makeWidget(id: "w2")]
        installMock()
        _ = await model.removeWidget(id: "w1")
        let body = requests.bodies["PATCH /api/preferences"]!
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let widgets = json["statsWidgets"] as! [[String: Any]]
        XCTAssertEqual(widgets.map { $0["id"] as? String }, ["w2"])
    }

    // MARK: - Customize (order / hidden)

    func testSetSectionHiddenPersists() async {
        installMock()
        await model.setSectionVisible("recap", visible: false)
        let body = requests.bodies["PATCH /api/preferences"]!
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(json["statsSectionHidden"] as? [String], ["recap"])
    }

    func testMoveSectionsSavesFullOrderedList() async {
        installMock()
        // Move "recap" (last) to the front.
        await model.moveSections(from: IndexSet(integer: StatsSections.all.count - 1), to: 0)
        let body = requests.bodies["PATCH /api/preferences"]!
        let json = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
        let order = json["statsSectionOrder"] as? [String]
        XCTAssertEqual(order?.first, "recap")
        XCTAssertEqual(Set(order ?? []), Set(StatsSections.all))
    }

    // MARK: - Feeding gaps quick ranges

    func testFeedingGapsQuickRange() async {
        state.chores = [makeFeedBaby()]
        installMock()
        await model.setFeedingGapsQuickRange(days: 14)
        XCTAssertTrue(model.isFeedingGapsQuickActive(days: 14))
        XCTAssertFalse(model.isFeedingGapsQuickActive(days: 7))
        let expectedStart = StatsModel.dateString(Calendar.current.date(byAdding: .day, value: -13, to: Date())!)
        XCTAssertEqual(model.feedingGapsStart, expectedStart)
        XCTAssertTrue(requests.urlStrings().contains { $0.contains("/api/stats/feeding-gaps?start=\(expectedStart)") })
    }

    func testFeedingGapsDefaultQuickActiveIsWeek() {
        installMock()
        XCTAssertTrue(model.isFeedingGapsQuickActive(days: 7))
    }
}
