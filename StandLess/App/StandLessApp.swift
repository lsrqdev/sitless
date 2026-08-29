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

/// Gates the app behind the 3-screen onboarding flow (R33) on first launch, then shows the
/// app's three main sections — Today, Trends, Settings — kept deliberately simple (no nested
/// tab navigation beyond this).
private struct RootTabView: View {
    let healthData: HealthDataProviding
    let settingsStore: SettingsStore
    @State private var needsOnboarding: Bool

    init(healthData: HealthDataProviding, settingsStore: SettingsStore) {
        self.healthData = healthData
        self.settingsStore = settingsStore
        _needsOnboarding = State(initialValue: healthData.authorizationState == .notDetermined)
    }

    var body: some View {
        if needsOnboarding {
            OnboardingView(viewModel: OnboardingViewModel(healthData: healthData)) {
                needsOnboarding = false
            }
        } else {
            TabView {
                TodayView(viewModel: TodayViewModel(healthData: healthData, settingsStore: settingsStore))
                    .tabItem { Label("Today", systemImage: "figure.stand") }

                TrendsView(viewModel: TrendsViewModel(healthData: healthData))
                    .tabItem { Label("Trends", systemImage: "chart.bar") }

                SettingsView(viewModel: SettingsViewModel(store: settingsStore, healthData: healthData))
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
