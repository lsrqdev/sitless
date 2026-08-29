import SwiftUI
import StandLessKit

/// The full grouped Settings list (R30): standing goal, inactivity reminder, Apple Health
/// connection status, and About — no account, profile, or social settings.
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

                    // Placeholder row: the inactivity reminder is wired up in Phase 5, once
                    // Core Motion and NotificationManager exist. Shown here to match the
                    // approved Settings layout, but not yet interactive.
                    LabeledContent("Inactivity reminder", value: "Off")
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Apple Health") {
                        Text(viewModel.isHealthConnected ? "Connected" : "Not Connected")
                            .foregroundStyle(viewModel.isHealthConnected ? MinimalHealthAccessView.standingAccent : .secondary)
                            .fontWeight(viewModel.isHealthConnected ? .semibold : .regular)
                    }
                } footer: {
                    Text("StandLess reads standing, activity, and sleep data from Apple Health to build your daily picture. Nothing leaves your device.")
                }

                Section {
                    NavigationLink("About StandLess") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("StandLess")
                        .font(.title2.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                Text("StandLess has no account, no cloud backend, and no third-party analytics. Your standing, activity, and sleep data stays on this device and inside Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
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
