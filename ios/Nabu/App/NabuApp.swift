import SwiftUI

@main
struct NabuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .environmentObject(environment)
                .onAppear {
                    environment.configure(with: state)
                    appDelegate.attach(appState: state)
                    PushRegistrationController.shared.configure(api: environment.apiClient)
                }
                .tint(DesignColors.primary)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
