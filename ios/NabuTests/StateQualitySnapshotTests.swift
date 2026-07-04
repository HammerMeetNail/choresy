import XCTest
import SwiftUI
import SnapshotTesting
@testable import Nabu

/// Snapshot coverage for the C4 state-quality components (P6): loading
/// skeletons, inline error, and the offline banner — light/dark at the
/// default type size, plus an accessibility type size (AX1) to prove the
/// layouts survive Dynamic Type. Same recorded-OS convention as
/// StatsSnapshotTests.
@MainActor
final class StateQualitySnapshotTests: XCTestCase {

    private static let recordedOSMajor = "26"

    private func skipUnlessRecordedOS() throws {
        try XCTSkipUnless(
            UIDevice.current.systemVersion.hasPrefix(Self.recordedOSMajor + "."),
            "Snapshots recorded on iOS \(Self.recordedOSMajor); rendering differs across OS majors"
        )
    }

    /// Light/dark at default size, plus dark at accessibilityLarge.
    private func assertStates(
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
        let variants: [(String, UITraitCollection)] = [
            ("light", UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(preferredContentSizeCategory: .large),
            ])),
            ("dark", UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .dark),
                UITraitCollection(preferredContentSizeCategory: .large),
            ])),
            ("ax1", UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                UITraitCollection(preferredContentSizeCategory: .accessibilityMedium),
            ])),
        ]
        for (name, traits) in variants {
            assertSnapshot(
                of: framed,
                as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: width, height: height), traits: traits),
                named: name,
                file: file, testName: testName, line: line
            )
        }
    }

    func testSkeletonScreen() throws {
        try skipUnlessRecordedOS()
        assertStates(SkeletonScreen(), height: 500)
    }

    func testSkeletonCards() throws {
        try skipUnlessRecordedOS()
        assertStates(SkeletonCards(), height: 500)
    }

    func testInlineError() throws {
        try skipUnlessRecordedOS()
        assertStates(
            InlineErrorView(message: "Stats couldn't be loaded. Check your connection and try again.") {},
            height: 420
        )
    }

    func testOfflineBanner() throws {
        try skipUnlessRecordedOS()
        assertStates(OfflineBanner(), height: 120)
    }

    func testEmptyStateWithCTA() throws {
        try skipUnlessRecordedOS()
        let empty = ContentUnavailableView {
            Label("No chores yet", systemImage: "square.grid.2x2")
        } description: {
            Text("Add the chores your household tracks and they'll appear here as one-tap tiles.")
        } actions: {
            Button("Add Chores") {}
                .buttonStyle(.borderedProminent)
        }
        assertStates(empty, height: 420)
    }
}
