import Foundation

@MainActor
final class PreferencesDataLoader {
    let api: APIClient
    let state: AppState

    init(api: APIClient, state: AppState) {
        self.api = api
        self.state = state
    }

    func loadPreferences() async {
        do {
            let data: UserPreferencesResponse = try await api.get("/api/preferences")
            state.choreOrder = data.preferences.choreOrder
            state.hiddenHomeChoreIDs = data.preferences.hiddenHomeChoreIds
            state.volumeUnit = data.preferences.volumeUnit == "oz" ? "oz" : "ml"
            state.statsSectionOrder = data.preferences.statsSectionOrder
            state.statsSectionHidden = data.preferences.statsSectionHidden
            state.statsWidgets = data.preferences.statsWidgets
        } catch {
            // Silent failure
        }
    }

    /// Persists the stats section order; the server echo wins (PWA
    /// `saveStatsSectionOrder`).
    @discardableResult
    func saveStatsSectionOrder(_ order: [String]) async -> Bool {
        state.statsSectionOrder = order
        do {
            let patch = PatchUserPreferencesRequest(statsSectionOrder: order)
            let data: UserPreferencesResponse = try await api.patch("/api/preferences", body: patch)
            state.statsSectionOrder = data.preferences.statsSectionOrder
            return true
        } catch {
            return false
        }
    }

    /// Persists the hidden stats sections (PWA `saveStatsSectionHidden`).
    @discardableResult
    func saveStatsSectionHidden(_ hidden: [String]) async -> Bool {
        state.statsSectionHidden = hidden
        do {
            let patch = PatchUserPreferencesRequest(statsSectionHidden: hidden)
            let data: UserPreferencesResponse = try await api.patch("/api/preferences", body: patch)
            state.statsSectionHidden = data.preferences.statsSectionHidden
            return true
        } catch {
            return false
        }
    }

    /// Persists the user-defined stats widgets. The server validates the
    /// schema and echoes back the normalized list (with server-assigned ids),
    /// which we store (PWA `saveStatsWidgets`).
    @discardableResult
    func saveStatsWidgets(_ widgets: [StatsWidget]) async -> Bool {
        do {
            let patch = PatchUserPreferencesRequest(statsWidgets: widgets)
            let data: UserPreferencesResponse = try await api.patch("/api/preferences", body: patch)
            state.statsWidgets = data.preferences.statsWidgets
            return true
        } catch {
            return false
        }
    }

    /// Optimistically applies the unit, then persists it; rolls back on
    /// failure (mirrors the PWA's `setVolumeUnit`).
    func setVolumeUnit(_ unit: String) async {
        let previous = state.volumeUnit
        state.volumeUnit = unit
        do {
            let patch = PatchUserPreferencesRequest(volumeUnit: unit)
            let data: UserPreferencesResponse = try await api.patch("/api/preferences", body: patch)
            state.volumeUnit = data.preferences.volumeUnit == "oz" ? "oz" : "ml"
        } catch {
            state.volumeUnit = previous
        }
    }

    func syncTimezone() async {
        let systemTZ = TimeZone.current.identifier
        guard state.household != nil else { return }
        do {
            let data: UserPreferencesResponse = try await api.get("/api/preferences")
            if data.preferences.timezone != systemTZ {
                let patch = PatchUserPreferencesRequest(timezone: systemTZ)
                let _: UserPreferencesResponse = try await api.patch("/api/preferences", body: patch)
            }
        } catch {
            // Silent failure
        }
    }
}
