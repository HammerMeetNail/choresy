import XCTest
@testable import Nabu

/// Mirrors the PWA's `recentVolumesForChore` (app.js): up to three distinct
/// recent amounts in canonical mL, most-recent-first, from logs already in
/// state.
final class RecentVolumesTests: XCTestCase {

    private func log(id: Int, choreId: Int = 1, minutesAgo: Double,
                     volumeML: Int? = nil,
                     indicatorVolumes: [String: Int]? = nil) -> ChoreLog {
        let at = Date().addingTimeInterval(-minutesAgo * 60)
        return ChoreLog(
            id: id, householdId: 1, userId: 1, choreId: choreId,
            completedAt: at, note: "", indicators: [], slotHour: nil,
            createdAt: at, volumeML: volumeML, indicatorVolumes: indicatorVolumes
        )
    }

    func testNewestFirstDistinctCappedAtThree() {
        let sources = [
            log(id: 1, minutesAgo: 10, volumeML: 120),
            log(id: 2, minutesAgo: 20, volumeML: 90),
            log(id: 3, minutesAgo: 30, volumeML: 120), // duplicate, skipped
            log(id: 4, minutesAgo: 40, volumeML: 60),
            log(id: 5, minutesAgo: 50, volumeML: 45),  // beyond cap
        ]
        XCTAssertEqual(recentVolumes(forChore: 1, latest: nil, sources: sources), [120, 90, 60])
    }

    func testFiltersByChore() {
        let sources = [
            log(id: 1, choreId: 1, minutesAgo: 10, volumeML: 120),
            log(id: 2, choreId: 2, minutesAgo: 5, volumeML: 999),
        ]
        XCTAssertEqual(recentVolumes(forChore: 1, latest: nil, sources: sources), [120])
    }

    func testIncludesIndicatorVolumes() {
        let sources = [
            log(id: 1, minutesAgo: 10, indicatorVolumes: ["🍼 formula": 90, "🤱 breast": 0]),
        ]
        XCTAssertEqual(recentVolumes(forChore: 1, latest: nil, sources: sources), [90])
    }

    func testExcludesZeroAndNil() {
        let sources = [
            log(id: 1, minutesAgo: 10, volumeML: 0),
            log(id: 2, minutesAgo: 20),
        ]
        XCTAssertEqual(recentVolumes(forChore: 1, latest: nil, sources: sources), [])
    }

    func testLatestLogIncluded() {
        let latest = log(id: 9, minutesAgo: 1, volumeML: 150)
        let sources = [log(id: 1, minutesAgo: 10, volumeML: 120)]
        XCTAssertEqual(recentVolumes(forChore: 1, latest: latest, sources: sources), [150, 120])
    }

    func testEmptyState() {
        XCTAssertEqual(recentVolumes(forChore: 1, latest: nil, sources: []), [])
    }
}
