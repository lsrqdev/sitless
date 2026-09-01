import Foundation
import Observation
import StandLessKit

/// Drives the 3-screen onboarding flow (R33). HealthKit authorization is requested exactly
/// once, only after the third screen's explanation — never before (R2).
@MainActor
@Observable
final class OnboardingViewModel {
    private let healthData: HealthDataProviding
    private(set) var isRequestingAccess = false

    init(healthData: HealthDataProviding) {
        self.healthData = healthData
    }

    func requestHealthAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        try? await healthData.requestAuthorization()
    }
}
