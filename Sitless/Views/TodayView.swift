import SwiftUI
import SitlessKit

struct TodayView: View {
    @State private var viewModel: TodayViewModel

    init(viewModel: TodayViewModel) {
        _viewModel = State(initialValue: viewModel)
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
        .task { await viewModel.start() }
        .onAppear { viewModel.reloadGoal() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            stateMessage("Health data isn't available on this device.")
        case .noData:
            noDataBody
        case .queryFailure:
            stateMessage("Couldn't load your standing time. Try again shortly.")
        case .loaded:
            loadedBody(isPartial: false)
        case .partialData:
            loadedBody(isPartial: true)
        }
    }

    private func loadedBody(isPartial: Bool) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 6) {
                    Text(Self.formatted(viewModel.todayStandingDuration))
                        .font(.system(size: 64, weight: .bold))
                        .monospacedDigit()
                        .accessibilityLabel("\(Self.formatted(viewModel.todayStandingDuration)) standing today")
                    Text("STANDING")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(MinimalHealthAccessView.standingAccent)
                        .accessibilityHidden(true)

                    if isPartial {
                        partialDataBadge
                    } else if let standingPercentage = viewModel.standingPercentage {
                        percentageBlock(standingPercentage)
                    }

                    if !isPartial, let comparisonText {
                        Text(comparisonText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 24)

                MetricRow(
                    standingDuration: viewModel.todayStandingDuration,
                    sedentaryDuration: isPartial ? nil : viewModel.estimatedSedentaryDuration,
                    activeDuration: viewModel.activeDuration
                )
                .padding(.horizontal, 4)

                GoalProgressView(current: viewModel.todayStandingDuration, goal: viewModel.standingGoal)
                    .padding(.horizontal, 32)

                if !viewModel.timeline.isEmpty {
                    TimelineView(segments: viewModel.timeline, window: viewModel.todayWindow)
                        .padding(.horizontal)
                }

                footnote(isPartial: isPartial)
                    .padding(.horizontal, 32)
            }
        }
    }

    private func percentageBlock(_ percentage: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(percentage)%")
                .font(.system(size: 30, weight: .bold))
            Text("of tracked awake time")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 22)
        .accessibilityElement(children: .combine)
    }

    private var partialDataBadge: some View {
        VStack(spacing: 4) {
            Text("Partial data today")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            Text("Sedentary estimate based on available data. Wear your Apple Watch to improve accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private func footnote(isPartial: Bool) -> some View {
        if isPartial {
            Text("Large stretches of today have insufficient data to classify, so they're shown as Unknown rather than guessed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if viewModel.estimatedSedentaryDuration != nil {
            Text("*Sedentary time is estimated from available activity data.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var noDataBody: some View {
        VStack(spacing: 8) {
            Text("No standing data yet")
                .font(.headline)
            Text("Wear your Apple Watch normally and check again later. If nothing appears, check that Sitless is allowed to read your standing time in the Health app, under Sharing.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var comparisonText: String? {
        switch viewModel.comparison {
        case .vsYesterday(let delta):
            let sign = delta >= 0 ? "+" : "\u{2212}"
            return "\(sign)\(Self.formatted(abs(delta))) standing vs yesterday"
        case .vsSevenDayAverage(let deltaPercent):
            let sign = deltaPercent >= 0 ? "+" : ""
            return "\(sign)\(deltaPercent)% vs your 7-day average"
        case nil:
            return nil
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

    static func formatted(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
