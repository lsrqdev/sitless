#if DEBUG
import SwiftUI
import StandLessKit

/// Developer-only raw-data screen (R35) — never compiled into Release builds.
struct DiagnosticsView: View {
    let healthData: HealthDataProviding

    @State private var snapshot: HealthDiagnosticsSnapshot?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let snapshot {
                Section("Query Range") {
                    Text("\(snapshot.queryRange.start.formatted()) – \(snapshot.queryRange.end.formatted())")
                }
                Section("Stand Time Samples (\(snapshot.standTimeSamples.count))") {
                    ForEach(Array(snapshot.standTimeSamples.enumerated()), id: \.offset) { _, sample in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.sourceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(sample.start.formatted()) – \(sample.end.formatted())")
                                .font(.caption)
                            Text("\(sample.value, specifier: "%.1f") min")
                                .font(.caption)
                        }
                    }
                }
            }
            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task { await refresh() }
                }
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: now) else { return }
        do {
            snapshot = try await healthData.rawDiagnostics(in: DateInterval(start: start, end: now))
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }
}
#endif
