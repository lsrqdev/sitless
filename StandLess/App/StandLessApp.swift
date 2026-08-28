import SwiftUI
import StandLessKit

@main
struct StandLessApp: App {
    private let healthData: HealthDataProviding = HealthKitManager()
    private let settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView(healthData: healthData, settingsStore: settingsStore)
        }
    }
}

/// The app's three main sections — Today, Trends, Settings — kept deliberately simple (no
/// nested tab navigation beyond this).
private struct RootTabView: View {
    let healthData: HealthDataProviding
    let settingsStore: SettingsStore

    var body: some View {
        TabView {
            TodayView(
                viewModel: TodayViewModel(healthData: healthData, settingsStore: settingsStore),
                needsAccess: healthData.authorizationState == .notDetermined
            )
            .tabItem { Label("Today", systemImage: "figure.stand") }

            TrendsView(viewModel: TrendsViewModel(healthData: healthData))
                .tabItem { Label("Trends", systemImage: "chart.bar") }

            SettingsView(viewModel: SettingsViewModel(store: settingsStore))
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
