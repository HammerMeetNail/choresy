import SwiftUI

/// Persistent elapsed-time chip for the running duration timer. Overlaid at
/// the top of the tab view so it stays visible across tabs (the PWA's
/// top-bar chip). Tapping stops the timer and logs the chore with
/// `durationSeconds`.
struct TimerChipView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var environment: AppEnvironment
    @State private var isLogging = false

    var body: some View {
        if let timer = state.activeTimer {
            Button {
                stopAndLog(timer)
            } label: {
                HStack(spacing: 8) {
                    Text(timer.choreIcon)
                    Text(timer.choreName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(DurationTimer.formatElapsed(DurationTimer.elapsedSeconds(timer, now: context.date)))
                            .font(.subheadline.monospacedDigit())
                    }
                    Text("Stop & log")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DesignColors.brand)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(isLogging)
            .accessibilityIdentifier("timer-chip")
            .accessibilityLabel("Stop timer and log \(timer.choreName)")
        }
    }

    private func stopAndLog(_ timer: ActiveTimer) {
        guard !isLogging else { return }
        isLogging = true
        let durationSeconds = DurationTimer.elapsedSeconds(timer)
        let completedAt = ISO8601DateFormatter().string(from: Date())
        // Clear the timer immediately so a double-tap can't double-log.
        state.activeTimer = nil
        DurationTimer.save(nil)

        let logStore = LogStore(api: environment.apiClient)
        let userId = state.user?.id
        Task {
            defer { isLogging = false }
            do {
                // Matches the PWA stop-timer body: no date, no slotHour
                // (Anytime), just completedAt + durationSeconds.
                let outcome = try await logStore.createLog(
                    choreId: timer.choreId,
                    completedAt: completedAt,
                    userId: userId,
                    durationSeconds: durationSeconds
                )
                switch outcome {
                case .created(let response):
                    state.todayLogs.insert(response.log, at: 0)
                    state.latestLogs[timer.choreId] = response.log
                case .queued(let pending):
                    var row = pending
                    if row.userId == nil { row.userId = userId }
                    state.pendingLogs.insert(row, at: 0)
                }
            } catch {
                // Server rejected the log — restore the timer so the elapsed
                // time isn't silently lost.
                let restored = timer
                state.activeTimer = restored
                DurationTimer.save(restored)
            }
        }
    }
}
