import SwiftUI
import StandLessKit

/// The Watch's single primary scrollable screen — standing time, goal progress, comparison,
/// last-stand context, and Stand Hours, all on one view with no nested navigation (R34).
struct WatchHomeView: View {
    static let standingAccent = Color(red: 0.078, green: 0.722, blue: 0.702) // #14B8B3

    @State private var viewModel: WatchHomeViewModel

    init(viewModel: WatchHomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        content
            .task { await viewModel.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            stateMessage("Health data isn't available on this device.")
        case .denied:
            stateMessage("Allow Health access in Settings to see your standing time.")
        case .noData:
            stateMessage("No standing data yet. Wear your Apple Watch normally and check again later.")
        case .queryFailure:
            stateMessage("Couldn't load your standing time.")
        case .loaded:
            loadedBody(isPartial: false)
        case .partialData:
            loadedBody(isPartial: true)
        }
    }

    private func loadedBody(isPartial: Bool) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(Self.formatted(viewModel.standingDuration))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .accessibilityLabel("\(Self.formatted(viewModel.standingDuration)) standing today")

                Text("Standing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.standingAccent)
                    .accessibilityHidden(true)

                goalSection
                    .padding(.top, 16)

                if isPartial {
                    Text("Partial data today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                } else if let comparisonText {
                    Text(comparisonText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Self.standingAccent)
                        .padding(.top, 12)
                }

                Divider()
                    .padding(.vertical, 14)

                VStack(spacing: 10) {
                    miniRow(label: "Last stand", value: lastStandText)
                    miniRow(label: "Stand hours", value: standHoursText)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
        }
    }

    private var goalSection: some View {
        VStack(spacing: 5) {
            HStack {
                Text("Goal")
                Spacer()
                Text(Self.formatted(viewModel.standingGoal))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            ProgressView(value: goalFraction)
                .tint(Self.standingAccent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goal \(Self.formatted(viewModel.standingGoal)), \(Int(goalFraction * 100)) percent complete")
    }

    private func miniRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var goalFraction: Double {
        guard viewModel.standingGoal > 0 else { return 0 }
        return min(viewModel.standingDuration / viewModel.standingGoal, 1)
    }

    private var comparisonText: String? {
        switch viewModel.comparison {
        case .vsYesterday(let delta):
            let sign = delta >= 0 ? "+" : "\u{2212}"
            return "\(sign)\(Self.formatted(abs(delta))) vs yesterday"
        case .vsSevenDayAverage(let deltaPercent):
            let sign = deltaPercent >= 0 ? "+" : ""
            return "\(sign)\(deltaPercent)% vs 7-day average"
        case nil:
            return nil
        }
    }

    private var lastStandText: String {
        guard let lastStandElapsed = viewModel.lastStandElapsed else { return "—" }
        return Self.elapsedLabel(lastStandElapsed)
    }

    private var standHoursText: String {
        guard let standHours = viewModel.standHours else { return "—" }
        return "\(standHours) / \(WatchHomeViewModel.appleStandHoursGoal)"
    }

    private func stateMessage(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func formatted(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private static func elapsedLabel(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval) / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(remainder)m ago"
    }
}
