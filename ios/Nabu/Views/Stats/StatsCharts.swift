import SwiftUI
import Charts

// Swift Charts components for the Stats tab (P4 C5 migration). Data and
// semantics match the PWA's SVG charts (`stats.js`); presentation is native
// per plan §2.1. Stack/series colors come from `IndicatorColor` so custom
// labels get identical colors on both clients.

// MARK: - Period bar chart (volume / indicator / simple metric)

/// One stacked segment of one period bucket.
struct PeriodBarSegment: Identifiable {
    let id: String        // "\(periodStart)|\(series)"
    let periodStart: String
    let series: String
    let value: Double
}

/// The stacked bar chart over time-series period buckets — the shared shape
/// behind the PWA's `renderVolumeChart`, `renderIndicatorChart`, and
/// `renderSimpleMetricChart`.
struct PeriodBarChart: View {
    /// What one bucket contributes, already split into stack segments in
    /// *display* units (so the axis reads in the active unit).
    let segments: [PeriodBarSegment]
    let periods: [TimeSeriesPeriod]
    /// Bucket grain: "daily" | "weekly" | "monthly" (labels + label thinning).
    let grain: String
    /// Y-axis unit label ("mL", "oz", "min", "count", or a custom unit).
    let unitLabel: String
    /// Series → color. Series not present use the indicator palette.
    let seriesColors: [String: Color]
    /// Renders the tap summary line for a period bucket.
    let summaryText: (TimeSeriesPeriod) -> String

    @State private var selectedPeriodStart: String?

    private var seriesKeys: [String] {
        var seen = Set<String>()
        return segments.map(\.series).filter { seen.insert($0).inserted }
    }

    private var selectedPeriod: TimeSeriesPeriod? {
        guard let start = selectedPeriodStart else { return nil }
        return periods.first { $0.start == start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Tap summary (PWA shows the bar's value label on tap).
            if let p = selectedPeriod {
                Text("\(StatsFormat.periodLabel(p, grain: grain)): \(summaryText(p))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                    .accessibilityIdentifier("chart-tap-summary")
            }
            Chart(segments) { seg in
                BarMark(
                    x: .value("Period", seg.periodStart),
                    y: .value(unitLabel, seg.value)
                )
                .foregroundStyle(by: .value("Series", seg.series))
                .opacity(selectedPeriodStart == nil || selectedPeriodStart == seg.periodStart ? 0.9 : 0.45)
            }
            .chartForegroundStyleScale(domain: seriesKeys, range: seriesKeys.map { seriesColors[$0] ?? IndicatorColor.color(for: $0) })
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedPeriodStart)
            .chartXScale(domain: periods.map(\.start))
            .chartXAxis {
                AxisMarks(values: xTickValues) { value in
                    AxisValueLabel {
                        if let start = value.as(String.self),
                           let p = periods.first(where: { $0.start == start }) {
                            Text(StatsFormat.xLabel(p, grain: grain))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxisLabel(unitLabel, position: .leading)
            .frame(height: 150)
            // VoiceOver summary (C6): totals instead of per-bar mark values.
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        let total = segments.map(\.value).reduce(0, +)
        let totalText = total == total.rounded()
            ? String(Int(total))
            : String(format: "%.1f", total)
        return "\(grain.capitalized) chart, \(periods.count) periods, \(totalText) \(unitLabel) total"
    }

    /// Daily buckets label every other column, like the PWA.
    private var xTickValues: [String] {
        if grain == "daily" {
            return periods.enumerated().compactMap { i, p in i % 2 == 0 ? p.start : nil }
        }
        return periods.map(\.start)
    }
}

/// Small legend row of series totals shown under a stacked chart
/// (PWA: "🍼 12 total" / "unlabeled 60 mL").
struct ChartTotalsLegend: View {
    struct Entry: Identifiable {
        var id: String { label }
        let label: String
        let color: Color
    }
    let entries: [Entry]

    var body: some View {
        if !entries.isEmpty {
            HStack(spacing: 12) {
                ForEach(entries) { entry in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(entry.color)
                            .frame(width: 8, height: 8)
                        Text(entry.label)
                            .font(.system(size: 9))
                            .foregroundStyle(DesignColors.textSecondary)
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Segment builders (PWA stack semantics)

enum PeriodBarData {
    static let unlabeledKey = "unlabeled"

    /// Stack keys in first-seen order across buckets (PWA `extractStackKeys`).
    static func stackKeys(_ periods: [TimeSeriesPeriod], volumeMode: Bool) -> [String] {
        var seen = Set<String>()
        var keys: [String] = []
        for p in periods {
            let source = volumeMode ? (p.volumeByIndicator ?? [:]) : (p.indicators ?? [:])
            // Dictionary order is unstable; sort within a bucket for determinism.
            for k in source.keys.sorted() where seen.insert(k).inserted {
                keys.append(k)
            }
        }
        return keys
    }

    /// Volume chart segments: per-indicator mL plus the unattributed
    /// remainder, converted to the display unit.
    static func volumeSegments(_ periods: [TimeSeriesPeriod], unit: String) -> [PeriodBarSegment] {
        let keys = stackKeys(periods, volumeMode: true)
        var out: [PeriodBarSegment] = []
        for p in periods {
            var attributed = 0
            for key in keys {
                let ml = p.volumeByIndicator?[key] ?? 0
                attributed += ml
                if ml > 0 {
                    out.append(PeriodBarSegment(id: "\(p.start)|\(key)", periodStart: p.start, series: key, value: displayVolume(ml, unit: unit)))
                }
            }
            let unlabeled = (p.totalML ?? 0) - attributed
            if unlabeled > 0 {
                out.append(PeriodBarSegment(id: "\(p.start)|\(unlabeledKey)", periodStart: p.start, series: unlabeledKey, value: displayVolume(unlabeled, unit: unit)))
            }
        }
        return out
    }

    /// Indicator chart segments: per-indicator counts.
    static func indicatorSegments(_ periods: [TimeSeriesPeriod]) -> [PeriodBarSegment] {
        let keys = stackKeys(periods, volumeMode: false)
        var out: [PeriodBarSegment] = []
        for p in periods {
            for key in keys {
                let count = p.indicators?[key] ?? 0
                if count > 0 {
                    out.append(PeriodBarSegment(id: "\(p.start)|\(key)", periodStart: p.start, series: key, value: Double(count)))
                }
            }
        }
        return out
    }

    /// Single-series segments for a generic metric value per bucket.
    static func valueSegments(_ periods: [TimeSeriesPeriod], series: String = "value", valueFn: (TimeSeriesPeriod) -> Double) -> [PeriodBarSegment] {
        periods.compactMap { p in
            let v = valueFn(p)
            guard v > 0 else { return nil }
            return PeriodBarSegment(id: "\(p.start)|\(series)", periodStart: p.start, series: series, value: v)
        }
    }

    static func displayVolume(_ ml: Int, unit: String) -> Double {
        unit == "oz" ? VolumeUnits.mlToOz(ml) : Double(ml)
    }
}

// MARK: - Busy hours

struct BusyHoursChart: View {
    let busyHours: [BusyHour]

    var body: some View {
        Chart(busyHours, id: \.hour) { entry in
            BarMark(
                x: .value("Count", entry.count),
                y: .value("Hour", StatsFormat.hourLabel(entry.hour))
            )
            .foregroundStyle(DesignColors.primary.opacity(0.75))
            .annotation(position: .trailing, spacing: 4) {
                Text("\(entry.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignColors.textSecondary)
            }
        }
        .chartYScale(domain: busyHours.map { StatsFormat.hourLabel($0.hour) })
        .chartXAxis(.hidden)
        .frame(height: CGFloat(busyHours.count) * 16 + 16)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let busiest = busyHours.max(by: { $0.count < $1.count }) else {
            return "Busy hours chart, no data"
        }
        return "Busy hours chart, busiest at \(StatsFormat.hourLabel(busiest.hour)) with \(busiest.count) logs"
    }
}

// MARK: - Activity heatmap

/// GitHub-style activity heatmap as a Swift Charts rectangle plot: columns =
/// Monday-start weeks (matching the server's week definition and the PWA),
/// rows = Mon–Sun.
struct HeatmapChart: View {
    struct Cell: Identifiable {
        var id: String { date }
        let date: String
        let weekStart: String
        let dayIndex: Int // 0 = Mon
        let count: Int
    }

    let heatmap: [HeatmapEntry]
    /// Injectable for deterministic snapshot tests.
    var today: Date = Date()

    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let cells = Self.buildCells(heatmap, today: today)
        let weekStarts = orderedWeekStarts(cells)
        let maxCount = max(heatmap.map(\.count).max() ?? 0, 0)

        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                Chart(cells) { cell in
                    RectangleMark(
                        x: .value("Week", cell.weekStart),
                        y: .value("Day", Self.dayLabels[cell.dayIndex]),
                        width: .ratio(0.85),
                        height: .ratio(0.85)
                    )
                    .foregroundStyle(Self.color(count: cell.count, maxCount: maxCount))
                    .cornerRadius(2)
                }
                .chartXScale(domain: weekStarts)
                .chartYScale(domain: Self.dayLabels) // Mon top row, like the PWA grid
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .leading) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label).font(.system(size: 8))
                            }
                        }
                    }
                }
                .frame(width: CGFloat(weekStarts.count) * 14 + 30, height: 7 * 14 + 8)
                .accessibilityLabel("Activity heatmap, \(heatmap.map(\.count).reduce(0, +)) logs across \(weekStarts.count) weeks")
            }

            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(DesignColors.textSecondary)
                let legendMax = max(4, maxCount)
                ForEach(0..<5) { i in
                    let sample = i == 0 ? 0 : Int(ceil(Double(legendMax) * Double(i) / 4.0))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.color(count: sample, maxCount: legendMax))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(DesignColors.textSecondary)
            }
        }
    }

    private func orderedWeekStarts(_ cells: [Cell]) -> [String] {
        var seen = Set<String>()
        return cells.map(\.weekStart).filter { seen.insert($0).inserted }
    }

    /// PWA `heatmapColor` intensity buckets over the shared ramp.
    static func color(count: Int, maxCount: Int) -> Color {
        if count == 0 { return DesignColors.heatmapEmpty }
        let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0
        if intensity <= 0.25 { return DesignColors.heatmapRamp[0] }
        if intensity <= 0.50 { return DesignColors.heatmapRamp[1] }
        if intensity <= 0.75 { return DesignColors.heatmapRamp[2] }
        return DesignColors.heatmapRamp[3]
    }

    /// 20 Monday-start weeks ending today (PWA `renderHeatmapGrid` range).
    static func buildCells(_ heatmap: [HeatmapEntry], today: Date = Date()) -> [Cell] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday, matching the server's wkStart
        let startOfToday = cal.startOfDay(for: today)
        // Days since the most recent Monday (weekday: Sun=1..Sat=7).
        let mondayIndex = (cal.component(.weekday, from: startOfToday) + 5) % 7
        guard let start = cal.date(byAdding: .day, value: -(mondayIndex + 19 * 7), to: startOfToday) else { return [] }

        let counts = Dictionary(heatmap.map { ($0.date, $0.count) }, uniquingKeysWith: { a, _ in a })
        var cells: [Cell] = []
        var current = start
        var weekStart = StatsModel.dateString(start)
        var dayIndex = 0
        while current <= startOfToday {
            if dayIndex == 0 { weekStart = StatsModel.dateString(current) }
            let ds = StatsModel.dateString(current)
            cells.append(Cell(date: ds, weekStart: weekStart, dayIndex: dayIndex, count: counts[ds] ?? 0))
            dayIndex = (dayIndex + 1) % 7
            current = cal.date(byAdding: .day, value: 1, to: current) ?? startOfToday.addingTimeInterval(1)
        }
        return cells
    }
}

// MARK: - Cluster feeding scatter

/// Inter-feed gap scatter (PWA `renderClusterGapScatter`): each dot is one
/// gap, positioned by hour of day and gap length, colored by the shared
/// classification; a red rule marks the 2-hour cluster-feeding threshold.
struct FeedingGapsScatter: View {
    struct Point: Identifiable {
        let id: Int
        let gap: FeedingGap
        let x: Double       // hour + deterministic jitter
        let y: Double       // gap minutes clamped to the 5h axis
        let kind: Kind
    }

    enum Kind {
        case fullFeed, closeFeed, smallTopOff

        var color: Color {
            switch self {
            case .fullFeed: return Color(hexUnsafe: "2E86AB")
            case .closeFeed: return Color(hexUnsafe: "F97316")
            case .smallTopOff: return Color(hexUnsafe: "EC4899")
            }
        }

        var label: String {
            switch self {
            case .fullFeed: return "full feed"
            case .closeFeed: return "close feed"
            case .smallTopOff: return "small top-off"
            }
        }
    }

    let gaps: [FeedingGap]
    let volumeUnit: String

    @State private var selected: Point?

    private static let maxY = 300.0

    var body: some View {
        let points = Self.classify(gaps)

        VStack(alignment: .leading, spacing: 4) {
            if let sel = selected {
                Text("\(StatsFormat.mediumDate(sel.gap.date)): \(volumeLabel(sel.gap))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignColors.textPrimary)
                    .accessibilityIdentifier("scatter-tap-summary")
            }
            Chart {
                RuleMark(y: .value("2h", 120))
                    .foregroundStyle(Color(hexUnsafe: "EF4444"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                ForEach(points) { point in
                    PointMark(
                        x: .value("Hour", point.x),
                        y: .value("Gap", point.y)
                    )
                    .foregroundStyle(point.kind.color)
                    .opacity(selected == nil || selected?.id == point.id ? 0.7 : 0.3)
                    .symbolSize(selected?.id == point.id ? 90 : 50)
                }
            }
            .chartXScale(domain: 0...24)
            .chartYScale(domain: 0...Self.maxY)
            .chartXAxis {
                AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            Text(StatsFormat.hourLabel(h)).font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 60, 120, 180, 240, 300]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let m = value.as(Int.self) {
                            Text(m == 0 ? "0" : "\(m / 60)h").font(.system(size: 8))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            selected = nearestPoint(points, to: location, proxy: proxy, geo: geo)
                        }
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Feeding gaps scatter plot, \(gaps.count) feeds, red line marks the two hour gap")

            ChartTotalsLegend(entries: [
                .init(label: Kind.fullFeed.label, color: Kind.fullFeed.color),
                .init(label: Kind.closeFeed.label, color: Kind.closeFeed.color),
                .init(label: Kind.smallTopOff.label, color: Kind.smallTopOff.color),
            ])
        }
    }

    private func volumeLabel(_ g: FeedingGap) -> String {
        "\(VolumeUnits.formatVolume(g.precedingVolume, unit: volumeUnit)) → \(VolumeUnits.formatVolume(g.followUpVolume, unit: volumeUnit))"
    }

    private func nearestPoint(_ points: [Point], to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> Point? {
        let origin = geo[proxy.plotFrame!].origin
        let plotPoint = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        guard let (hour, minutes) = proxy.value(at: plotPoint, as: (Double, Double).self) else { return nil }
        let best = points.min {
            let da = pow($0.x - hour, 2) + pow(($0.y - minutes) / 12.5, 2)
            let db = pow($1.x - hour, 2) + pow(($1.y - minutes) / 12.5, 2)
            return da < db
        }
        guard let best else { return nil }
        // Ignore taps far from any dot; a repeat tap on the same dot clears.
        let dist = pow(best.x - hour, 2) + pow((best.y - minutes) / 12.5, 2)
        if dist > 4 { return nil }
        return selected?.id == best.id ? nil : best
    }

    /// Ports the PWA's dot classification exactly, including the
    /// preceding-top-off carry-over and the deterministic jitter.
    static func classify(_ gaps: [FeedingGap]) -> [Point] {
        func smallTopOff(_ g: FeedingGap) -> Bool {
            g.precedingVolume > 0 && Double(g.followUpVolume) <= Double(g.precedingVolume) * 0.5
        }
        return gaps.enumerated().map { i, g in
            let isPink = smallTopOff(g)
            let isPrecedingTopOff = i > 0 && smallTopOff(gaps[i - 1])
            let isOrange = !isPink && g.precedingVolume > 0 && g.gapMinutes <= 180
                && (g.followUpVolume <= g.precedingVolume || isPrecedingTopOff)
            let kind: Kind = isPink ? .smallTopOff : (isOrange ? .closeFeed : .fullFeed)
            let seed = Double(g.hour * 1000 + g.gapMinutes)
            let jitter = ((seed * 137.508).truncatingRemainder(dividingBy: 1) - 0.5) * 0.65
            return Point(
                id: i,
                gap: g,
                x: Double(g.hour) + 0.5 + jitter,
                y: min(Double(g.gapMinutes), maxY),
                kind: kind
            )
        }
    }
}

// MARK: - Shared formatting

enum StatsFormat {
    /// "12a" / "3p" hour labels (PWA `formatHour`).
    static func hourLabel(_ h: Int) -> String {
        if h == 0 { return "12a" }
        if h < 12 { return "\(h)a" }
        if h == 12 { return "12p" }
        return "\(h - 12)p"
    }

    /// Short x-axis label per bucket grain (PWA `formatXLabel`).
    static func xLabel(_ p: TimeSeriesPeriod, grain: String) -> String {
        guard let date = StatsModel.parseDate(p.start) else { return "" }
        let f = DateFormatter()
        switch grain {
        case "weekly":
            f.dateFormat = "MMM d"
            return f.string(from: date)
        case "monthly":
            f.dateFormat = "MMM"
            return f.string(from: date)
        default:
            return "\(Calendar.current.component(.day, from: date))"
        }
    }

    /// Full period label for tap summaries (PWA `formatPeriodLabel`).
    static func periodLabel(_ p: TimeSeriesPeriod, grain: String) -> String {
        guard let start = StatsModel.parseDate(p.start) else { return "" }
        let f = DateFormatter()
        switch grain {
        case "weekly":
            f.dateFormat = "MMM d"
            let endLabel: String
            if let end = StatsModel.parseDate(p.end),
               let inclusive = Calendar.current.date(byAdding: .day, value: -1, to: end) {
                endLabel = f.string(from: inclusive)
            } else {
                endLabel = ""
            }
            return "\(f.string(from: start))–\(endLabel)"
        case "monthly":
            f.dateFormat = "MMM yyyy"
            return f.string(from: start)
        default:
            f.dateFormat = "MMM d"
            return f.string(from: start)
        }
    }

    /// "Jul 2" from "2026-07-02" (PWA `formatScatterDate`).
    static func mediumDate(_ s: String) -> String {
        guard let d = StatsModel.parseDate(String(s.prefix(10))) else { return s }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    /// "Jun 26 – Jul 3" range label (PWA `formatRangeLabel`).
    static func rangeLabel(_ start: String, _ end: String) -> String {
        guard let s = StatsModel.parseDate(start), let e = StatsModel.parseDate(end) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: s)) – \(f.string(from: e))"
    }
}
