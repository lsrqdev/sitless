import SwiftUI
import StandLessKit

/// Minimal Settings screen for Phase 2: the Standing Goal row only.
/// The full grouped list (reminder, Health status, About) arrives in Phase 3.
struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = Bindable(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StandingGoalPicker(selectedDuration: $viewModel.standingGoal.duration)
                    } label: {
                        LabeledContent("Standing goal", value: TodayView.formatted(viewModel.standingGoal.duration))
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct StandingGoalPicker: View {
    @Binding var selectedDuration: TimeInterval

    var body: some View {
        List(StandingGoal.options, id: \.self) { option in
            Button {
                selectedDuration = option
            } label: {
                HStack {
                    Text(TodayView.formatted(option))
                        .foregroundStyle(.primary)
                    Spacer()
                    if option == selectedDuration {
                        Image(systemName: "checkmark")
                            .foregroundStyle(MinimalHealthAccessView.standingAccent)
                    }
                }
            }
        }
        .navigationTitle("Standing Goal")
    }
}
