import XCTest
import SitlessKit
@testable import Sitless

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private static func isolatedStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests-\(UUID().uuidString)")!
        return SettingsStore(defaults: defaults)
    }

    private static func viewModel(authorizationState: HealthAuthorizationState) -> SettingsViewModel {
        SettingsViewModel(
            store: isolatedStore(),
            healthData: MockHealthDataProvider(authorizationState: authorizationState)
        )
    }

    func testHealthConnectionIsUnresolvedBeforeLoading() {
        XCTAssertNil(Self.viewModel(authorizationState: .determined).healthConnection)
    }

    func testHealthConnectionIsConnectedOncePromptHasBeenAnswered() async {
        let viewModel = Self.viewModel(authorizationState: .determined)

        await viewModel.loadHealthConnection()

        XCTAssertEqual(viewModel.healthConnection, .connected)
    }

    func testHealthConnectionIsNotConnectedWhilePromptIsUnanswered() async {
        let viewModel = Self.viewModel(authorizationState: .notDetermined)

        await viewModel.loadHealthConnection()

        XCTAssertEqual(viewModel.healthConnection, .notConnected)
    }

    func testHealthConnectionIsUnavailableWhenDeviceHasNoHealthStore() async {
        let viewModel = Self.viewModel(authorizationState: .unavailable)

        await viewModel.loadHealthConnection()

        XCTAssertEqual(viewModel.healthConnection, .unavailable)
    }
}
