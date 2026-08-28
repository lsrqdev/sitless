import SwiftUI
import Charts
import StandLessKit

struct TodayView: View {
    @State private var viewModel: TodayViewModel
    @State private var showAccessScreen: Bool

    init(viewModel: TodayViewModel, needsAccess: Bool) {
        _viewModel = State(initialValue: viewModel)
        _showAccessScreen = State(initialValue: needsAccess)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Debug") {
                            DiagnosticsView(healthData: viewModel.healthData)
                        }
                    }
                }
                #endif
        }
        .task {
            if !showAccessScreen {
                await viewModel.start()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if showAccessScreen {
            MinimalHealthAccessView {
                showAccessScreen = false
                Task { await viewModel.start() }
            }
        } else {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                stateMessage("Health data isn't available on this device.")
            case .authorizationRequired:
                stateMessage("Allow Health access in Settings to see your standing time.")
            case .queryFailure:
                stateMessage("Couldn't load your standing time. Try again shortly.")
            case .loaded:
                loadedBody
            }
        }
    }

    private var loadedBody: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text(Self.formatted(viewModel.todayStandingDuration))
                        .font(.system(size: 64, weight: .bold))
                        .monospacedDigit()
                    Text("STANDING")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(MinimalHealthAccessView.standingAccent)
                }
                .padding(.top, 24)

                Chart(viewModel.sevenDaySeries) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Standing", day.duration / 3600)
                    )
                    .foregroundStyle(MinimalHealthAccessView.standingAccent)
                }
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
    }

    private func stateMessage(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func formatted(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
