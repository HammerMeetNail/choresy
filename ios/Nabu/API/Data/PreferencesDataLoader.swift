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
        } catch {
            // Silent failure
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
