import SwiftUI
import StandLessKit

@main
struct StandLessApp: App {
    private let healthData: HealthDataProviding = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            TodayView(
                viewModel: TodayViewModel(healthData: healthData),
                needsAccess: healthData.authorizationState == .notDetermined
            )
        }
    }
}
