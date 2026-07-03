import Foundation

/// Offline log queue, ported from the PWA's `web/static/js/offline-queue.js`.
///
/// A `POST /api/logs` made while offline (e.g. a 3am feed on flaky reception)
/// would otherwise fail and lose the log — the worst failure for the baby use
/// case where the timestamp matters. This queue persists failed/offline log
/// bodies (as JSON on disk; the PWA uses IndexedDB) and replays them when
/// connectivity returns. Each queued item carries a client-generated
/// idempotencyKey so replay is safe against duplicates (the server de-dups
/// on it).
@MainActor
final class OfflineLogQueue: ObservableObject {
    static let shared = OfflineLogQueue()

    struct Item: Codable, Equatable {
        let body: CreateLogRequest
        let queuedAt: Date
    }

    @Published private(set) var items: [Item] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("nabu-offline-log-queue.json")
    }

    var count: Int { items.count }

    /// Stores a log body (which must include an idempotencyKey) for later
    /// replay. Idempotent on the key, so re-enqueuing the same attempt
    /// overwrites rather than duplicates.
    @discardableResult
    func enqueue(_ body: CreateLogRequest) -> Bool {
        guard let key = body.idempotencyKey, !key.isEmpty else { return false }
        items.removeAll { $0.body.idempotencyKey == key }
        items.append(Item(body: body, queuedAt: Date()))
        persist()
        return true
    }

    func removeAll() {
        items = []
        persist()
    }

    /// Attempts to POST every queued log via the given closure. On success
    /// (including an idempotent replay hit) the item is removed. A permanent
    /// client error (4xx other than 429) also removes the item to avoid an
    /// infinite retry loop. A network failure stops the pass, leaving
    /// remaining items for a later attempt. Returns the number successfully
    /// synced.
    func replay(post: (CreateLogRequest) async throws -> Void) async -> Int {
        var synced = 0
        for item in items {
            do {
                try await post(item.body)
                remove(key: item.body.idempotencyKey)
                synced += 1
            } catch let error as APIError {
                switch error {
                case .serverError(let status, _), .httpError(let status):
                    if (400..<500).contains(status) && status != 429 {
                        // Permanent client error (e.g. the chore was deleted) — drop it.
                        remove(key: item.body.idempotencyKey)
                    }
                    // 5xx / 429: keep and try again next time.
                case .rateLimited:
                    break // keep and try again next time
                case .decodingError:
                    // The HTTP request itself succeeded (2xx) — the log is on
                    // the server, so treat as synced.
                    remove(key: item.body.idempotencyKey)
                    synced += 1
                default:
                    // Network-level failure — still offline; stop the pass.
                    return synced
                }
            } catch {
                // Still offline — stop; keep the rest queued.
                return synced
            }
        }
        return synced
    }

    private func remove(key: String?) {
        guard let key = key else { return }
        items.removeAll { $0.body.idempotencyKey == key }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort; the in-memory queue still replays
            // within this session.
        }
    }
}

/// A queued-but-unsynced log synthesized for display in Activity with a
/// "pending" badge (PWA Phase 2.1), reconciled (cleared) on the next
/// successful replay.
struct PendingLog: Identifiable, Equatable {
    let id: String // idempotencyKey
    let choreId: Int
    var userId: Int?
    let note: String
    let indicators: [String]
    let indicatorVolumes: [String: Int]
    let volumeML: Int?
    let rating: Int?
    let subject: String?
    let title: String?
    let completedAt: Date

    init(body: CreateLogRequest, fallbackUserId: Int?) {
        self.id = body.idempotencyKey ?? UUID().uuidString
        self.choreId = body.choreId
        self.userId = body.userId ?? fallbackUserId
        self.note = body.note ?? ""
        self.indicators = body.indicators ?? []
        self.indicatorVolumes = body.indicatorVolumes ?? [:]
        self.volumeML = body.volumeML
        self.rating = body.rating
        self.subject = body.subject
        self.title = body.title
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basic = ISO8601DateFormatter()
        self.completedAt = body.completedAt.flatMap { formatter.date(from: $0) ?? basic.date(from: $0) } ?? Date()
    }
}
