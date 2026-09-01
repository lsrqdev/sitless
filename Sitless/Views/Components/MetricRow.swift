import SwiftUI
import SitlessKit

/// The Standing / Sedentary* / Active three-metric row (R21). The sedentary figure always
/// shows a "—" placeholder rather than a computed value when it isn't available, since a low
/// standing/sedentary value must never be confused with a genuinely measured zero.
struct MetricRow: View {
    let standingDuration: TimeInterval
    let sedentaryDuration: TimeInterval?
    let activeDuration: TimeInterval?

    var body: some View {
        HStack(spacing: 0) {
            metric(color: ActivityColor.standing, label: "Standing", value: TodayView.formatted(standingDuration))
            metric(color: ActivityColor.sedentary, label: "Sedentary*", value: sedentaryDuration.map(TodayView.formatted) ?? "—", isDimmed: sedentaryDuration == nil)
            metric(color: ActivityColor.active, label: "Active", value: activeDuration.map(TodayView.formatted) ?? "—", isDimmed: activeDuration == nil)
        }
    }

    private func metric(color: Color, label: String, value: String, isDimmed: Bool = false) -> some View {
        VStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isDimmed ? Color(white: 0.78) : .primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}
