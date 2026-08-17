import Foundation

/// Returns up to three distinct recent amounts (in canonical mL) logged for
/// the chore, most-recent-first, drawn from whatever logs are already in
/// state. Powers the recent-value chips (PWA Phase 5.3, `app.js`
/// `recentVolumesForChore`).
func recentVolumes(forChore choreId: Int, latest: ChoreLog?, sources: [ChoreLog]) -> [Int] {
    var logs = sources.filter { $0.choreId == choreId }
    if let latest = latest {
        logs.insert(latest, at: 0)
    }
    logs.sort { $0.completedAt > $1.completedAt }

    var seen = Set<Int>()
    var out: [Int] = []
    for log in logs {
        var vals: [Int] = []
        if let v = log.volumeML {
            vals.append(v)
        }
        if let indicatorVolumes = log.indicatorVolumes {
            // Sorted by label for determinism (JS object order is insertion
            // order; a Swift dictionary has none).
            for (_, v) in indicatorVolumes.sorted(by: { $0.key < $1.key }) where v > 0 {
                vals.append(v)
            }
        }
        for v in vals where v > 0 && !seen.contains(v) {
            seen.insert(v)
            out.append(v)
            if out.count >= 3 { return out }
        }
    }
    return out
}

/// Applies a recent amount without changing the selected indicator types.
func applyRecentVolumeSelection(
    _ ml: Int,
    hasIndicators: Bool,
    selectedIndicators: [String],
    indicatorVolumes: [String: Int],
    volumeML: Int?
) -> (indicatorVolumes: [String: Int], volumeML: Int?) {
    var updatedIndicatorVolumes = indicatorVolumes
    var updatedVolumeML = volumeML
    if !hasIndicators {
        updatedVolumeML = ml
    } else {
        for label in selectedIndicators {
            updatedIndicatorVolumes[label] = ml
        }
    }
    return (updatedIndicatorVolumes, updatedVolumeML)
}
