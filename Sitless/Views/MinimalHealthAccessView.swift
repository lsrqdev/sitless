import SwiftUI

/// Single explanation screen shown before the HealthKit prompt (satisfies R2 for this phase;
/// superseded by the full 3-screen onboarding in Phase 3).
struct MinimalHealthAccessView: View {
    static let standingAccent = Color(red: 0.078, green: 0.722, blue: 0.702) // #14B8B3

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Sitless")
                .font(.largeTitle.bold())
            Text("Sitless reads your standing time from Apple Health to show how much of today you spent standing versus sitting. Your health data always stays on this device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Allow Health Access", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(Self.standingAccent)
                .padding(.horizontal, 32)
            Spacer()
                .frame(height: 40)
        }
    }
}
