import SwiftUI
import SitlessKit

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

                    NavigationLink {
                        ReminderIntervalPicker(selected: $viewModel.reminderInterval)
                    } label: {
                        LabeledContent("Inactivity reminder", value: viewModel.reminderInterval.displayName)
                    }
                }

                Section {
                    LabeledContent("Apple Health") {
                        switch viewModel.healthConnection {
                        case .connected:
                            statusText("Connected", isConnected: true)
                        case .notConnected:
                            statusText("Not Connected", isConnected: false)
                        case .unavailable:
                            statusText("Unavailable", isConnected: false)
                        case nil:
                            ProgressView()
                        }
                    }
                    LabeledContent("Motion access") {
                        statusText(
                            viewModel.isMotionConnected ? "Connected" : "Not Connected",
                            isConnected: viewModel.isMotionConnected
                        )
                    }
                } footer: {
                    Text("Sitless reads standing, activity, and sleep data from Apple Health to build your daily picture. Motion access lets the inactivity reminder stay quiet while you're driving. Nothing leaves your device.")
                }

                Section {
                    NavigationLink("About Sitless") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await viewModel.loadHealthConnection() }
        }
    }

    private func statusText(_ text: LocalizedStringKey, isConnected: Bool) -> some View {
        Text(text)
            .foregroundStyle(isConnected ? MinimalHealthAccessView.standingAccent : .secondary)
            .fontWeight(isConnected ? .semibold : .regular)
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sitless")
                        .font(.title2.bold())
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section {
                Text("Sitless has no account, no cloud backend, and no third-party analytics. Your standing, activity, and sleep data stays on this device and inside Apple Health.")
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

private struct ReminderIntervalPicker: View {
    @Binding var selected: ReminderInterval

    var body: some View {
        List(ReminderInterval.allCases, id: \.self) { option in
            Button {
                selected = option
            } label: {
                HStack {
                    Text(option.displayName)
                        .foregroundStyle(.primary)
                    Spacer()
                    if option == selected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(MinimalHealthAccessView.standingAccent)
                    }
                }
            }
        }
        .navigationTitle("Inactivity Reminder")
    }
}
