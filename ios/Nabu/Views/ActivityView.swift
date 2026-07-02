import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var environment: AppEnvironment
    @State private var historyLogs: [ChoreLog] = []
    @State private var historyHasMore = false
    @State private var historyBefore: String?
    // Additive chore filter: empty = show all activity, otherwise show only the
    // selected chores. Matches the PWA activity filter.
    @State private var choreFilter: Set<Int> = []
    @State private var showingFilter = false

    private let activityStore: ActivityStore
    private let logStore: LogStore

    init(activityStore: ActivityStore, logStore: LogStore) {
        self.activityStore = activityStore
        self.logStore = logStore
    }

    var body: some View {
        NavigationStack {
            // Activity is history-only, matching the PWA (the Day/Week calendar
            // sub-views were removed there for low usage / visual noise).
            HistoryListView(
                activityStore: activityStore, logStore: logStore,
                logs: $historyLogs, hasMore: $historyHasMore, before: $historyBefore,
                choreFilter: $choreFilter
            )
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFilter = true
                    } label: {
                        Image(systemName: choreFilter.isEmpty
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter activity")
                }
            }
            .sheet(isPresented: $showingFilter) {
                ChoreFilterSheet(chores: state.chores, selected: $choreFilter)
            }
        }
        .task {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        guard historyLogs.isEmpty else { return }
        do {
            let data = try await activityStore.loadHistory()
            historyLogs = data.logs
            historyHasMore = data.hasMore
            historyBefore = data.start
        } catch {}
    }
}

// MARK: - History List View

struct HistoryListView: View {
    let activityStore: ActivityStore
    let logStore: LogStore
    @Binding var logs: [ChoreLog]
    @Binding var hasMore: Bool
    @Binding var before: String?
    @Binding var choreFilter: Set<Int>
    @EnvironmentObject var state: AppState

    @State private var isLoadingMore = false
    @State private var selectedLog: ChoreLog?
    @State private var selectedChore: Chore?

    var body: some View {
        List {
            if let message = emptyMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .listRowSeparator(.hidden)
            }

            ForEach(groupedLogs(), id: \.key) { group in
                Section(group.key) {
                    ForEach(group.rows) { log in
                        historyRow(log)
                    }
                }
            }

            if hasMore {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Button("Load more") {
                            Task { await loadMore() }
                        }
                    }
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $selectedLog) { log in
            if let chore = selectedChore {
                LogSheet(state: state, chore: chore, log: log, logStore: logStore)
            }
        }
    }

    /// Message to show when the (filtered) list is empty. Distinguishes "no
    /// match on this page but more pages exist" from "nothing matches at all",
    /// so a paginated view doesn't wrongly claim there's no matching activity.
    private var emptyMessage: String? {
        guard groupedLogs().isEmpty else { return nil }
        if !choreFilter.isEmpty {
            return hasMore
                ? "No matching activity in this time range. Load more to look further back."
                : "No activity matches the selected chores."
        }
        return logs.isEmpty ? "No completed chores yet." : nil
    }

    private func groupedLogs() -> [(key: String, rows: [ChoreLog])] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var groups: [String: [ChoreLog]] = [:]
        for log in filterLogsByChores(logs, selected: choreFilter) {
            let dateStr = f.string(from: log.completedAt)
            groups[dateStr, default: []].append(log)
        }
        return groups.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
    }

    @ViewBuilder
    private func historyRow(_ log: ChoreLog) -> some View {
        let chore = state.chores.first(where: { $0.id == log.choreId })
        Button {
            selectedChore = chore
            selectedLog = log
        } label: {
            HStack(spacing: 12) {
                Text(chore?.icon ?? "📋")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: chore?.color ?? "#6B7280") ?? .gray)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(chore?.name ?? "Chore")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    HStack(spacing: 4) {
                        Text(fmtTime(log.completedAt))
                        if let userId = state.members.first(where: { $0.userId == log.userId }) {
                            Text("· \(userId.displayName.isEmpty ? userId.email : userId.displayName)")
                        }
                        if !log.note.isEmpty {
                            Text("· \(log.note)")
                        }
                        let volKeys = Set(log.indicatorVolumes?.keys.map { $0 } ?? [])
                        if volKeys.isEmpty, let volume = log.volumeML {
                            Text("· \(volume)mL")
                        }
                        let volParts = (log.indicatorVolumes ?? [:]).map { k, v in
                            "\(k.split(separator: " ").first ?? "") \(v)mL"
                        }
                        if !volParts.isEmpty {
                            Text("· \(volParts.joined(separator: " "))")
                        }
                        ForEach(log.indicators.filter { !volKeys.contains($0) }, id: \.self) { indicator in
                            Text(indicator.split(separator: " ").first.map(String.init) ?? "")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .overlay(
                Rectangle()
                    .fill(Color(hex: chore?.color ?? "#6B7280") ?? .gray)
                    .frame(width: 3),
                alignment: .leading
            )
        }
    }

    private func loadMore() async {
        guard let before = before else { return }
        isLoadingMore = true
        do {
            let data = try await activityStore.loadMoreHistory(before: before)
            logs.append(contentsOf: data.logs)
            hasMore = data.hasMore
            self.before = data.start
        } catch {}
        isLoadingMore = false
    }
}

// MARK: - Chore Filter Sheet

/// Multi-select chore filter presented from the Activity toolbar. Selection is
/// additive: tapping "All activity" clears the filter, tapping a chore toggles
/// it. Chores are listed in a single alphabetically-sorted list with large,
/// tap-friendly rows.
struct ChoreFilterSheet: View {
    let chores: [Chore]
    @Binding var selected: Set<Int>
    @Environment(\.dismiss) private var dismiss

    private var sortedChores: [Chore] {
        chores.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selected.removeAll()
                } label: {
                    HStack {
                        Text("All activity")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        if selected.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(sortedChores) { chore in
                    Button {
                        if selected.contains(chore.id) {
                            selected.remove(chore.id)
                        } else {
                            selected.insert(chore.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(chore.icon)
                                .font(.title3)
                                .frame(width: 28)
                            Text(chore.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selected.contains(chore.id) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Filter activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
