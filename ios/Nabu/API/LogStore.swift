import Foundation

/// Result of a log creation attempt: either the server accepted it, or the
/// network was down and the body was queued for replay (PWA `logChore`
/// semantics — the log and its timestamp are never lost).
enum CreateLogOutcome {
    case created(LogResponse)
    case queued(PendingLog)
}

@MainActor
final class LogStore {
    let api: APIClient
    let offlineQueue: OfflineLogQueue

    init(api: APIClient, offlineQueue: OfflineLogQueue? = nil) {
        self.api = api
        self.offlineQueue = offlineQueue ?? OfflineLogQueue.shared
    }

    func createLog(choreId: Int, note: String = "", date: String? = nil,
                   indicators: [String] = [], slotHour: Int? = nil,
                   completedAt: String? = nil, volumeML: Int? = nil,
                   userId: Int? = nil, indicatorVolumes: [String: Int]? = nil,
                   followUpMinutes: Int? = nil,
                   followUpTime: String? = nil,
                   rating: Int? = nil, title: String? = nil,
                   durationSeconds: Int? = nil,
                   subject: String? = nil) async throws -> CreateLogOutcome {
        var body = CreateLogRequest(
            choreId: choreId, note: note, indicators: indicators,
            date: date, hour: slotHour, completedAt: completedAt,
            volumeML: volumeML, userId: userId,
            indicatorVolumes: indicatorVolumes,
            followUpMinutes: followUpMinutes,
            followUpTime: followUpTime,
            rating: rating, title: title,
            durationSeconds: durationSeconds, subject: subject,
            // Idempotency key so an offline replay can't create a duplicate.
            idempotencyKey: UUID().uuidString
        )
        do {
            let response: LogResponse = try await api.post("/api/logs", body: body)
            return .created(response)
        } catch let error where Self.isNetworkFailure(error) {
            // Network failure (offline / flaky). Queue the log so it (and its
            // timestamp) is not lost, then report it as queued instead of
            // failing. Capture completedAt now if it wasn't set, so the time
            // is preserved.
            if body.completedAt == nil {
                body = CreateLogRequest(
                    choreId: body.choreId, note: body.note, indicators: body.indicators,
                    date: body.date, hour: body.hour,
                    completedAt: ISO8601DateFormatter().string(from: Date()),
                    volumeML: body.volumeML, userId: body.userId,
                    indicatorVolumes: body.indicatorVolumes,
                    followUpMinutes: body.followUpMinutes,
                    followUpTime: body.followUpTime,
                    rating: body.rating, title: body.title,
                    durationSeconds: body.durationSeconds, subject: body.subject,
                    idempotencyKey: body.idempotencyKey
                )
            }
            offlineQueue.enqueue(body)
            return .queued(PendingLog(body: body, fallbackUserId: nil))
        }
    }

    /// Whether the error means the request never reached the server (queue
    /// and replay later) as opposed to the server rejecting it (surface to
    /// the user).
    static func isNetworkFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case APIError.networkError = error { return true }
        return false
    }

    /// Replays the offline queue. Returns the number of logs synced.
    func replayOfflineQueue() async -> Int {
        await offlineQueue.replay { body in
            let _: LogResponse = try await self.api.post("/api/logs", body: body)
        }
    }

    func updateLog(logId: Int, note: String? = nil, indicators: [String]? = nil,
                   volumeML: Int? = nil, userId: Int? = nil,
                   completedAt: String? = nil, hour: Int? = nil,
                   date: String? = nil, indicatorVolumes: [String: Int]? = nil,
                   rating: Int? = nil, title: String? = nil,
                   subject: String?? = nil) async throws -> LogResponse {
        let body = UpdateLogRequest(
            note: note, indicators: indicators, volumeML: volumeML,
            userId: userId, completedAt: completedAt, hour: hour, date: date,
            indicatorVolumes: indicatorVolumes,
            rating: rating, title: title, subject: subject
        )
        return try await api.patch("/api/logs/\(logId)", body: body)
    }

    func deleteLog(logId: Int) async throws -> StatusResponse {
        return try await api.delete("/api/logs/\(logId)")
    }
}
