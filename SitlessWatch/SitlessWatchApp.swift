import SwiftUI
import SitlessKit

@main
struct SitlessWatchApp: App {
    private let healthData: HealthDataProviding = HealthKitManager()
    private let settingsStore = SettingsStore()
    private let connectivity: WatchConnectivityService

    init() {
        let connectivity = WatchConnectivityService(settingsStore: settingsStore)
        connectivity.activate()
        self.connectivity = connectivity
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView(viewModel: WatchHomeViewModel(healthData: healthData, settingsStore: settingsStore))
        }
    }
}
