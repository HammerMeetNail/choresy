import XCTest
@testable import Nabu

/// Replay/de-dup/reconciliation semantics for the offline log queue, mirroring
/// the PWA's `offline-queue.js` contract: 2xx removes, permanent 4xx (except
/// 429) removes, 5xx/429 keeps and continues, network failure stops the pass.
@MainActor
final class OfflineLogQueueTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline-queue-tests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func makeQueue() -> OfflineLogQueue {
        OfflineLogQueue(fileURL: fileURL)
    }

    private func body(key: String?, choreId: Int = 1, note: String = "") -> CreateLogRequest {
        CreateLogRequest(
            choreId: choreId, note: note, indicators: nil, date: nil, hour: nil,
            completedAt: "2026-07-03T09:00:00Z", volumeML: nil, userId: nil,
            indicatorVolumes: nil, followUpMinutes: nil, followUpTime: nil,
            idempotencyKey: key
        )
    }

    // MARK: - Enqueue

    func testEnqueueRequiresIdempotencyKey() {
        let queue = makeQueue()
        XCTAssertFalse(queue.enqueue(body(key: nil)))
        XCTAssertFalse(queue.enqueue(body(key: "")))
        XCTAssertEqual(queue.count, 0)
    }

    func testEnqueueStoresItem() {
        let queue = makeQueue()
        XCTAssertTrue(queue.enqueue(body(key: "k1")))
        XCTAssertEqual(queue.count, 1)
    }

    func testReEnqueueSameKeyOverwrites() {
        let queue = makeQueue()
        queue.enqueue(body(key: "k1", note: "first"))
        queue.enqueue(body(key: "k1", note: "second"))
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.items.first?.body.note, "second")
    }

    func testPersistsAcrossInstances() {
        let queue = makeQueue()
        queue.enqueue(body(key: "k1"))
        queue.enqueue(body(key: "k2"))

        let reloaded = makeQueue()
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.items.map { $0.body.idempotencyKey }, ["k1", "k2"])
    }

    // MARK: - Replay

    func testReplaySuccessRemovesAndCounts() async {
        let queue = makeQueue()
        queue.enqueue(body(key: "k1"))
        queue.enqueue(body(key: "k2"))

        var posted: [String?] = []
        let synced = await queue.replay { body in
            posted.append(body.idempotencyKey)
        }
        XCTAssertEqual(synced, 2)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(posted, ["k1", "k2"])
    }

    func testReplayDropsPermanentClientError() async {
        let queue = makeQueue()
        queue.enqueue(body(key: "gone", choreId: 99))

        let synced = await queue.replay { _ in
            throw APIError.serverError(statusCode: 404, message: "chore not found")
        }
        XCTAssertEqual(synced, 0)
        XCTAssertEqual(queue.count, 0, "a permanent 4xx must not retry forever")
    }

    func testReplayKeeps429AndContinues() async {
        let queue = makeQueue()
        queue.enqueue(body(key: "k1"))
        queue.enqueue(body(key: "k2"))

        var attempts = 0
        let synced = await queue.replay { body in
            attempts += 1
            if body.idempotencyKey == "k1" {
                throw APIError.rateLimited(retryAfter: "5")
            }
        }
        XCTAssertEqual(synced, 1)
        XCTAssertEqual(attempts, 2, "429 keeps the item but continues the pass")
        XCTAssertEqual(queue.items.map { $0.body.idempotencyKey }, ["k1"])
    }

    func testReplayKeepsServerErrorAndContinues() async {
        let queue = makeQueue()
        queue.enqueue(body(key: "k1"))
        queue.enqueue(body(key: "k2"))

        let synced = await queue.replay { body in
            if body.idempotencyKey == "k1" {
                throw APIError.serverError(statusCode: 500, message: "boom")
            }
        }
        XCTAssertEqual(synced, 1)
        XCTAssertEqual(queue.items.map { $0.body.idempotencyKey }, ["k1"])
    }

    func testReplayStopsOnNetworkFailure() async {
        let queue = makeQueue()
        queue.enqueue(body(key: "k1"))
        queue.enqueue(body(key: "k2"))

        var attempts = 0
        let synced = await queue.replay { _ in
            attempts += 1
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertEqual(synced, 0)
        XCTAssertEqual(attempts, 1, "still offline — stop the pass, don't hammer")
        XCTAssertEqual(queue.count, 2)
    }

    func testReplayTreatsDecodingErrorAsSynced() async {
        // A decoding error is only thrown after a 2xx — the log is on the
        // server, so the item must not be retried (it would 200 again via
        // idempotency but would loop forever locally).
        let queue = makeQueue()
        queue.enqueue(body(key: "k1"))

        struct Dummy: Error {}
        let synced = await queue.replay { _ in
            throw APIError.decodingError(Dummy())
        }
        XCTAssertEqual(synced, 1)
        XCTAssertEqual(queue.count, 0)
    }

    func testReplayMixedPass() async {
        let queue = makeQueue()
        queue.enqueue(body(key: "ok1"))
        queue.enqueue(body(key: "bad"))
        queue.enqueue(body(key: "ok2"))

        let synced = await queue.replay { body in
            if body.idempotencyKey == "bad" {
                throw APIError.httpError(statusCode: 400)
            }
        }
        XCTAssertEqual(synced, 2)
        XCTAssertEqual(queue.count, 0)
    }

    // MARK: - PendingLog synthesis

    func testPendingLogFromBody() {
        let request = CreateLogRequest(
            choreId: 4, note: "big feed", indicators: ["🍼 formula"],
            date: "2026-07-03", hour: 9, completedAt: "2026-07-03T09:15:00Z",
            volumeML: 120, userId: nil, indicatorVolumes: ["🍼 formula": 120],
            followUpMinutes: nil, followUpTime: nil,
            rating: nil, title: nil, durationSeconds: nil, subject: "Ada",
            idempotencyKey: "key-1"
        )
        let pending = PendingLog(body: request, fallbackUserId: 42)
        XCTAssertEqual(pending.id, "key-1")
        XCTAssertEqual(pending.choreId, 4)
        XCTAssertEqual(pending.userId, 42)
        XCTAssertEqual(pending.note, "big feed")
        XCTAssertEqual(pending.volumeML, 120)
        XCTAssertEqual(pending.subject, "Ada")
        XCTAssertEqual(pending.indicatorVolumes, ["🍼 formula": 120])
        let expected = ISO8601DateFormatter().date(from: "2026-07-03T09:15:00Z")!
        XCTAssertEqual(pending.completedAt, expected)
    }
}
