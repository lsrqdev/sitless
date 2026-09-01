import SwiftUI
import SitlessKit

/// The 5-color activity language used across the Today timeline and metric row, matching the
/// approved mockup tokens (standing #14B8B3, active #34C759, sedentary #C99A4B, unknown #D8D8DD,
/// sleep #6D6FC7).
enum ActivityColor {
    static let standing = MinimalHealthAccessView.standingAccent
    static let active = Color(red: 0.204, green: 0.780, blue: 0.349)
    static let sedentary = Color(red: 0.788, green: 0.604, blue: 0.294)
    static let unknown = Color(red: 0.847, green: 0.847, blue: 0.867)
    static let sleep = Color(red: 0.427, green: 0.435, blue: 0.780)

    static func color(for state: ActivityState) -> Color {
        switch state {
        case .standing: return standing
        case .active: return active
        case .sedentary: return sedentary
        case .unknown: return unknown
        case .sleep: return sleep
        }
    }

    static func name(for state: ActivityState) -> String {
        switch state {
        case .standing: return "Standing"
        case .active: return "Active"
        case .sedentary: return "Sedentary estimate"
        case .unknown: return "Unknown"
        case .sleep: return "Sleep"
        }
    }
}

/// The hourly segmented timeline bar (R23) — answers "when was I inactive today" without
/// becoming a detailed analytics chart. Each segment carries its own VoiceOver label (R36).
struct TimelineView: View {
    let segments: [ActivityInterval]
    let window: DateInterval

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S TIMELINE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(ActivityColor.color(for: segment.state))
                            .frame(width: width(for: segment, totalWidth: geo.size.width))
                            .accessibilityElement()
                            .accessibilityLabel(accessibilityLabel(for: segment))
                    }
                }
            }
            .frame(height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Text(Self.hourFormatter.string(from: window.start))
                Spacer()
                Text(Self.hourFormatter.string(from: window.end))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            legend
        }
    }

    private func width(for segment: ActivityInterval, totalWidth: CGFloat) -> CGFloat {
        guard window.duration > 0 else { return 0 }
        let fraction = segment.duration / window.duration
        return max(totalWidth * CGFloat(fraction), 0)
    }

    private func accessibilityLabel(for segment: ActivityInterval) -> String {
        let start = segment.start.formatted(date: .omitted, time: .shortened)
        let end = segment.end.formatted(date: .omitted, time: .shortened)
        return "\(ActivityColor.name(for: segment.state)) from \(start) to \(end)"
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: ActivityColor.standing, label: "Standing")
            legendItem(color: ActivityColor.active, label: "Active")
            legendItem(color: ActivityColor.sedentary, label: "Sedentary est.")
            legendItem(color: ActivityColor.unknown, label: "Unknown")
            legendItem(color: ActivityColor.sleep, label: "Sleep")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}
