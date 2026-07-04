import XCTest
import SwiftUI
import SnapshotTesting
@testable import Nabu

/// Snapshot coverage for the notification permission pre-prompt (P5) — the
/// one new full screen this phase adds. Follows the StatsSnapshotTests
/// convention: recorded on the iOS major below, skipped elsewhere.
@MainActor
final class PushPrePromptSnapshotTests: XCTestCase {

    private static let recordedOSMajor = "26"

    private func skipUnlessRecordedOS() throws {
        try XCTSkipUnless(
            UIDevice.current.systemVersion.hasPrefix(Self.recordedOSMajor + "."),
            "Snapshots recorded on iOS \(Self.recordedOSMajor); rendering differs across OS majors"
        )
    }

    func testPrePromptScreen() throws {
        try skipUnlessRecordedOS()
        let view = PushPrePromptView(onEnable: {})
            .frame(width: 370, height: 640)
        assertSnapshot(
            of: view,
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: 370, height: 640), traits: UITraitCollection(userInterfaceStyle: .light)),
            named: "light"
        )
        assertSnapshot(
            of: view,
            as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .fixed(width: 370, height: 640), traits: UITraitCollection(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }
}
