import XCTest
@testable import Nabu

/// Pins `IndicatorColor` against the PWA's `colorForIndicator`
/// (`web/static/js/stats.js`, cases in `tests/runner.js`) so custom chore
/// labels get identical colors on both clients. The hash expectations were
/// computed by running the JS implementation directly.
final class IndicatorColorTests: XCTestCase {

    func testPredefinedLabelsKeepHistoricalColors() {
        XCTAssertEqual(IndicatorColor.hexColor(for: "🍼 formula"), "#EC4899")
        XCTAssertEqual(IndicatorColor.hexColor(for: "🤱 breast"), "#F59E0B")
        XCTAssertEqual(IndicatorColor.hexColor(for: "💩 poo"), "#8B4513")
        XCTAssertEqual(IndicatorColor.hexColor(for: "💛 pee"), "#FACC15")
    }

    /// JS hashLabel outputs for the same strings (UTF-16 code units through
    /// Math.imul(h, 31) + charCodeAt, |0, Math.abs).
    func testHashMatchesJSOutputs() {
        XCTAssertEqual(IndicatorColor.hashLabel("🌙 night"), 1_268_157_589)
        XCTAssertEqual(IndicatorColor.hashLabel("💊 vitamin"), 20_773_055)
        XCTAssertEqual(IndicatorColor.hashLabel("🌡️ temp"), 1_080_923_626)
        XCTAssertEqual(IndicatorColor.hashLabel(""), 0)
        XCTAssertEqual(IndicatorColor.hashLabel("am"), 3116)
        XCTAssertEqual(IndicatorColor.hashLabel("pm"), 3581)
        XCTAssertEqual(IndicatorColor.hashLabel("left"), 3_317_767)
        XCTAssertEqual(IndicatorColor.hashLabel("right"), 108_511_772)
        XCTAssertEqual(IndicatorColor.hashLabel("🍎 solids"), 1_313_316_746)
        XCTAssertEqual(IndicatorColor.hashLabel("water"), 112_903_447)
    }

    /// Palette colors resolved for custom labels, matching the JS results.
    func testCustomLabelColorsMatchJS() {
        XCTAssertEqual(IndicatorColor.hexColor(for: "🌙 night"), "#A23B72")
        XCTAssertEqual(IndicatorColor.hexColor(for: "💊 vitamin"), "#059669")
        XCTAssertEqual(IndicatorColor.hexColor(for: "🌡️ temp"), "#7C3AED")
        XCTAssertEqual(IndicatorColor.hexColor(for: "am"), "#D97706")
        XCTAssertEqual(IndicatorColor.hexColor(for: "pm"), "#0EA5E9")
        XCTAssertEqual(IndicatorColor.hexColor(for: "nap"), "#A23B72")
        XCTAssertEqual(IndicatorColor.hexColor(for: "tummy time"), "#0EA5E9")
    }

    func testStableAcrossCallsAndDistinctForRegressionPair() {
        XCTAssertEqual(IndicatorColor.hexColor(for: "🌙 night"), IndicatorColor.hexColor(for: "🌙 night"))
        // Regression (from the JS suite): previously both fell through to one gray.
        XCTAssertNotEqual(IndicatorColor.hexColor(for: "💊 vitamin"), IndicatorColor.hexColor(for: "🌡️ temp"))
    }

    func testNilAndEmptyNeverUndefined() {
        XCTAssertEqual(IndicatorColor.hexColor(for: nil), "#2E86AB")
        XCTAssertEqual(IndicatorColor.hexColor(for: ""), "#2E86AB")
    }
}
