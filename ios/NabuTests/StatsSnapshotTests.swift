import XCTest
import SwiftUI
import SnapshotTesting
@testable import Nabu

/// Snapshot coverage for every Stats chart state, light and dark (P4 exit
/// gate). Snapshots are recorded on the iOS major named below; other
/// runtimes skip instead of failing so the CI unit lane (which may carry an
/// older simulator runtime) stays meaningful without pixel-matching across
/// OS renderers.
@MainActor
final class StatsSnapshotTests: XCTestCase {

    /// The iOS major version the reference snapshots were recorded on.
    private static let recordedOSMajor = "26"

    private func skipUnlessRecordedOS() throws {
        try XCTSkipUnless(
            UIDevice.current.systemVersion.hasPrefix(Self.recordedOSMajor + "."),
            "Snapshots recorded on iOS \(Self.recordedOSMajor); rendering differs across OS majors"
        )
    }

    /// Asserts a light and a dark snapshot of the view at a fixed layout.
    private func assertLightAndDark(
        _ view: some View,
        width: CGFloat = 370,
        height: CGFloat,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let framed = view
            .frame(width: width, height: height)
            .background(Color(UIColor.systemBackground))
        assertSnapshot(
            of: framed,
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: width, height: height), traits: UITraitCollection(userInterfaceStyle: .light)),
            named: "light",
            file: file, testName: testName, line: line
        )
        assertSnapshot(
            of: framed,
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: width, height: height), traits: UITraitCollection(userInterfaceStyle: .dark)),
            named: "dark",
            file: file, testName: testName, line: line
        )
    }

    // MARK: - Fixtures

    /// Daily buckets with stacked volume-by-indicator data, mirroring the
    /// PWA volume chart's shape.
    private func volumePeriods() -> [TimeSeriesPeriod] {
        (0..<7).map { i in
            TimeSeriesPeriod(
                start: String(format: "2026-06-%02d", 20 + i),
                end: String(format: "2026-06-%02d", 21 + i),
                count: i == 3 ? 0 : 2 + i % 3,
                totalML: i == 3 ? 0 : 120 + i * 40,
                totalDuration: nil,
                indicators: i == 3 ? nil : ["🍼 formula": 1 + i % 2, "🤱 breast": i % 3],
                volumeByIndicator: i == 3 ? nil : ["🍼 formula": 80 + i * 20, "🤱 breast": i % 3 == 0 ? 0 : 30]
            )
        }
    }

    private func indicatorPeriods() -> [TimeSeriesPeriod] {
        (0..<7).map { i in
            TimeSeriesPeriod(
                start: String(format: "2026-06-%02d", 20 + i),
                end: String(format: "2026-06-%02d", 21 + i),
                count: 3 + i % 4,
                totalML: nil,
                totalDuration: nil,
                indicators: ["💩 poo": 1 + i % 2, "💛 pee": 2 + i % 3],
                volumeByIndicator: nil
            )
        }
    }

    private func valuePeriods(duration: Bool = false) -> [TimeSeriesPeriod] {
        (0..<6).map { i in
            TimeSeriesPeriod(
                start: String(format: "2026-0%d-01", 1 + i),
                end: String(format: "2026-0%d-01", 2 + i),
                count: 2 + i,
                totalML: 100 + i * 55,
                totalDuration: duration ? (10 + i * 7) * 60 : nil,
                indicators: nil,
                volumeByIndicator: nil
            )
        }
    }

    // MARK: - Charts

    func testVolumeChartDaily() throws {
        try skipUnlessRecordedOS()
        assertLightAndDark(
            VolumePeriodChart(periods: volumePeriods(), grain: "daily", volumeUnit: "ml"),
            height: 210
        )
    }

    func testVolumeChartWeeklyOunces() throws {
        try skipUnlessRecordedOS()
        assertLightAndDark(
            VolumePeriodChart(periods: volumePeriods(), grain: "weekly", volumeUnit: "oz"),
            height: 210
        )
    }

    func testVolumeChartMonthly() throws {
        try skipUnlessRecordedOS()
        assertLightAndDark(
            VolumePeriodChart(periods: valuePeriods(), grain: "monthly", volumeUnit: "ml"),
            height: 210
        )
    }

    func testVolumeChartEmptyBuckets() throws {
        try skipUnlessRecordedOS()
        let empty = (0..<7).map { i in
            TimeSeriesPeriod(start: String(format: "2026-06-%02d", 20 + i),
                             end: String(format: "2026-06-%02d", 21 + i),
                             count: 0, totalML: 0, totalDuration: nil,
                             indicators: nil, volumeByIndicator: nil)
        }
        assertLightAndDark(
            VolumePeriodChart(periods: empty, grain: "daily", volumeUnit: "ml"),
            height: 190
        )
    }

    func testIndicatorChartStacked() throws {
        try skipUnlessRecordedOS()
        assertLightAndDark(
            IndicatorPeriodChart(periods: indicatorPeriods(), grain: "daily"),
            height: 210
        )
    }

    func testIndicatorChartCustomLabels() throws {
        try skipUnlessRecordedOS()
        // Custom labels exercise the hash→palette mapping shared with the PWA.
        let periods = (0..<5).map { i in
            TimeSeriesPeriod(start: String(format: "2026-06-%02d", 20 + i),
                             end: String(format: "2026-06-%02d", 21 + i),
                             count: 2, totalML: nil, totalDuration: nil,
                             indicators: ["am": 1 + i % 2, "pm": 1],
                             volumeByIndicator: nil)
        }
        assertLightAndDark(
            IndicatorPeriodChart(periods: periods, grain: "daily"),
            height: 210
        )
    }

    func testSimpleMetricChartAmountDurationCount() throws {
        try skipUnlessRecordedOS()
        let amount = PeriodBarChart(
            segments: PeriodBarData.valueSegments(valuePeriods()) { Double($0.totalML ?? 0) },
            periods: valuePeriods(), grain: "monthly", unitLabel: "g",
            seriesColors: ["value": DesignColors.primary],
            summaryText: { "\($0.totalML ?? 0) g" }
        )
        let duration = PeriodBarChart(
            segments: PeriodBarData.valueSegments(valuePeriods(duration: true)) { (Double($0.totalDuration ?? 0) / 60.0).rounded() },
            periods: valuePeriods(duration: true), grain: "monthly", unitLabel: "min",
            seriesColors: ["value": DesignColors.primary],
            summaryText: { "\(($0.totalDuration ?? 0) / 60) min" }
        )
        let count = PeriodBarChart(
            segments: PeriodBarData.valueSegments(valuePeriods()) { Double($0.count) },
            periods: valuePeriods(), grain: "monthly", unitLabel: "count",
            seriesColors: ["value": DesignColors.primary],
            summaryText: { "\($0.count)" }
        )
        assertLightAndDark(VStack(spacing: 12) { amount; duration; count }, height: 500)
    }

    func testBusyHoursChart() throws {
        try skipUnlessRecordedOS()
        let hours = (0..<24).map { BusyHour(hour: $0, count: ($0 * 7) % 11) }
        assertLightAndDark(BusyHoursChart(busyHours: hours), height: 420)
    }

    func testHeatmapChart() throws {
        try skipUnlessRecordedOS()
        let today = StatsModel.parseDate("2026-07-03")!
        let entries: [HeatmapEntry] = (0..<120).compactMap { back in
            guard back % 3 != 0 else { return nil }
            let d = Calendar.current.date(byAdding: .day, value: -back, to: today)!
            return HeatmapEntry(date: StatsModel.dateString(d), count: (back % 5) + 1)
        }
        assertLightAndDark(HeatmapChart(heatmap: entries, today: today), height: 150)
    }

    func testHeatmapChartEmpty() throws {
        try skipUnlessRecordedOS()
        let today = StatsModel.parseDate("2026-07-03")!
        assertLightAndDark(HeatmapChart(heatmap: [], today: today), height: 150)
    }

    func testFeedingGapsScatter() throws {
        try skipUnlessRecordedOS()
        // Covers all three classifications: full feed, close feed, small top-off.
        let gaps = [
            FeedingGap(hour: 3, gapMinutes: 95, precedingVolume: 120, followUpVolume: 40, date: "2026-07-01"),  // top-off
            FeedingGap(hour: 7, gapMinutes: 150, precedingVolume: 100, followUpVolume: 90, date: "2026-07-01"), // close
            FeedingGap(hour: 12, gapMinutes: 240, precedingVolume: 100, followUpVolume: 150, date: "2026-07-02"), // full
            FeedingGap(hour: 18, gapMinutes: 60, precedingVolume: 150, followUpVolume: 60, date: "2026-07-02"), // top-off
            FeedingGap(hour: 21, gapMinutes: 320, precedingVolume: 90, followUpVolume: 120, date: "2026-07-02"), // clamped full
        ]
        assertLightAndDark(FeedingGapsScatter(gaps: gaps, volumeUnit: "ml"), height: 210)
    }

    // MARK: - Widgets

    private func widgetModel() -> StatsModel {
        let model = StatsModel()
        model.widgetSummaries["w1"] = [
            ChoreSummary(choreId: 1, count: 9, totalML: 720, totalDuration: 0,
                         byMember: [LeaderboardEntry(userId: 1, count: 6), LeaderboardEntry(userId: 2, count: 3)],
                         metricType: "amount", metricUnit: "mL"),
        ]
        model.widgetTimeSeries["w2"] = [
            ChoreTimeSeries(choreId: 1, choreName: "Feed Baby", choreIcon: "🍼",
                            metricType: "amount", metricUnit: "mL",
                            byMember: [TimeSeriesByMember(userId: 1, count: 4)],
                            periods: valuePeriods()),
        ]
        return model
    }

    private var widgetMembers: [Member] {
        [
            Member(userId: 1, email: "a@t.com", displayName: "Alice", avatarColor: "#2E86AB", emailVerified: true, role: "owner"),
            Member(userId: 2, email: "b@t.com", displayName: "Bob", avatarColor: "#A23B72", emailVerified: true, role: "member"),
        ]
    }

    private func widgetChore() -> Chore {
        Chore(id: 1, householdId: 1, name: "Feed Baby", icon: "🍼", color: "#EC4899",
              sortOrder: 0, category: "feeding", isPredefined: true, predefinedKey: "Feed Baby",
              createdBy: nil, createdAt: Date(timeIntervalSince1970: 0),
              indicatorLabels: [], indicatorDefaults: [], hasVolumeML: true,
              metricType: "amount", metricUnit: "mL")
    }

    func testWidgetTotalBigNumber() throws {
        try skipUnlessRecordedOS()
        let widget = makeWidget(id: "w1", type: "total", choreIds: [1], metric: "amount", title: "Bottles this week")
        assertLightAndDark(
            WidgetCard(model: widgetModel(), widget: widget, chores: [widgetChore()],
                       members: widgetMembers, latestLogs: [:]),
            height: 140
        )
    }

    func testWidgetMemberSplit() throws {
        try skipUnlessRecordedOS()
        let widget = makeWidget(id: "w1", type: "member-split", choreIds: [1], title: "Who fed")
        assertLightAndDark(
            WidgetCard(model: widgetModel(), widget: widget, chores: [widgetChore()],
                       members: widgetMembers, latestLogs: [:]),
            height: 160
        )
    }

    func testWidgetTimeseries() throws {
        try skipUnlessRecordedOS()
        let widget = makeWidget(id: "w2", type: "timeseries", choreIds: [1], metric: "amount", period: "month", title: "Volume trend")
        assertLightAndDark(
            WidgetCard(model: widgetModel(), widget: widget, chores: [widgetChore()],
                       members: widgetMembers, latestLogs: [:]),
            height: 260
        )
    }

    /// Widget titles are user data. The PWA's XSS spec feeds markup through
    /// the title; the iOS equivalent must render it as inert plain text —
    /// exactly the characters, no interpretation.
    func testWidgetHostileTitleRendersAsPlainText() throws {
        try skipUnlessRecordedOS()
        let widget = makeWidget(
            id: "w1", type: "total", choreIds: [1],
            title: #"<script>alert(1)</script><b>bold</b>"#
        )
        assertLightAndDark(
            WidgetCard(model: widgetModel(), widget: widget, chores: [widgetChore()],
                       members: widgetMembers, latestLogs: [:]),
            height: 140
        )
    }

    /// Interval/top-list are schema-valid but have no dedicated renderer;
    /// like the PWA they fall back to the big-number presentation.
    func testWidgetIntervalFallsBackToTotal() throws {
        try skipUnlessRecordedOS()
        let widget = makeWidget(id: "w1", type: "interval", choreIds: [1], title: "Interval widget")
        assertLightAndDark(
            WidgetCard(model: widgetModel(), widget: widget, chores: [widgetChore()],
                       members: widgetMembers, latestLogs: [:]),
            height: 140
        )
    }
}
