import Foundation

@MainActor
final class ActivityStore {
    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func loadHistory() async throws -> HistoryResponse {
        try await api.get("/api/logs/history")
    }

    func loadMoreHistory(before: String) async throws -> HistoryResponse {
        try await api.get("/api/logs/history", query: [URLQueryItem(name: "before", value: before)])
    }

    /// Flat text search across note/title — spans all history, capped and
    /// newest-first on the server, bypassing the windowed pagination.
    func searchHistory(query: String) async throws -> HistoryResponse {
        try await api.get("/api/logs/history", query: [URLQueryItem(name: "q", value: query)])
    }

    func loadToday(date: String) async throws -> TodayResponse {
        try await api.get("/api/logs/today", query: [URLQueryItem(name: "date", value: date)])
    }

    // MARK: - Day notes

    /// Loads the household's day notes (server default: last 90 days) as a
    /// date → note map, mirroring the PWA's `state.dayNotes`.
    func loadDayNotes() async throws -> [String: String] {
        let data: DayNotesResponse = try await api.get("/api/day-notes")
        return Dictionary(uniqueKeysWithValues: data.notes.map { ($0.date, $0.note) })
    }

    /// Sets (or clears, when empty) the shared note for a date.
    func setDayNote(date: String, note: String) async throws -> DayNote {
        let data: DayNoteResponse = try await api.put("/api/day-notes/\(date)", body: SetDayNoteRequest(note: note))
        return data.note
    }

    // MARK: - CSV export

    /// Downloads the full CSV log export (the PWA's Settings link uses the
    /// same all-history window) and writes it to a shareable temp file.
    func exportLogsCSV() async throws -> URL {
        let data = try await api.getData("/api/logs/export", query: [URLQueryItem(name: "start", value: "2000-01-01")])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nabu-logs.csv")
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Date helpers

func todayISO() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

func shiftISO(_ dateStr: String, by days: Int) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: dateStr),
          let shifted = Calendar.current.date(byAdding: .day, value: days, to: d) else {
        return dateStr
    }
    return f.string(from: shifted)
}

func weekStart(from dateStr: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: dateStr) else { return dateStr }
    let weekday = Calendar.current.component(.weekday, from: d)
    let daysFromMonday = weekday == 1 ? -6 : 2 - weekday
    guard let monday = Calendar.current.date(byAdding: .day, value: daysFromMonday, to: d) else {
        return dateStr
    }
    return f.string(from: monday)
}

func fmtHour(_ h: Int) -> String {
    switch h {
    case 0: return "12 AM"
    case 1...11: return "\(h) AM"
    case 12: return "12 PM"
    case 13...23: return "\(h - 12) PM"
    default: return "\(h)"
    }
}

func fmtShortDate(_ dateStr: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: dateStr) else { return dateStr }
    f.dateFormat = "E, d"
    return f.string(from: d)
}

func fmtTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

// MARK: - Activity filtering

/// Filters history logs by a set of selected chore IDs. An empty selection
/// means "no filter" — every log is returned. This mirrors the PWA activity
/// filter's additive semantics: nothing selected shows all activity, and each
/// selected chore adds its logs to the view.
func filterLogsByChores(_ logs: [ChoreLog], selected: Set<Int>) -> [ChoreLog] {
    guard !selected.isEmpty else { return logs }
    return logs.filter { selected.contains($0.choreId) }
}
