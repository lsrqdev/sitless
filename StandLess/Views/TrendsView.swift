import SwiftUI
import Charts
import StandLessKit

struct TrendsView: View {
    @Bindable private var viewModel: TrendsViewModel

    init(viewModel: TrendsViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Trends")
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            Picker("Period", selection: $viewModel.period) {
                ForEach(TrendsViewModel.Period.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.top, 8)

            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .queryFailure:
                stateMessage("Couldn't load trends. Try again shortly.")
            case .loaded:
                loadedBody
            }
        }
    }

    private var loadedBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Chart(viewModel.series) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Standing", day.duration / 3600)
                    )
                    .foregroundStyle(MinimalHealthAccessView.standingAccent)
                }
                .frame(height: 200)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.period.label) average")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(TodayView.formatted(viewModel.periodAverage))/day")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text(comparisonText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
        }
    }

    private var comparisonText: String {
        let delta = viewModel.periodAverage - viewModel.priorPeriodAverage
        guard viewModel.priorPeriodAverage > 0 else {
            return "No prior-period data yet"
        }
        let sign = delta >= 0 ? "+" : "\u{2212}"
        return "\(sign)\(TodayView.formatted(abs(delta)))/day vs previous period"
    }

    private func stateMessage(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
