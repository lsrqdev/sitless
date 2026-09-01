import SwiftUI

/// The standing-goal progress bar shown on Today: "current / target" plus a bar (R21).
struct GoalProgressView: View {
    let current: TimeInterval
    let goal: TimeInterval

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(current / goal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Standing goal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(TodayView.formatted(current)) / \(TodayView.formatted(goal))")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            ProgressView(value: fraction)
                .tint(MinimalHealthAccessView.standingAccent)
        }
    }
}
