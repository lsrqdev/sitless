import SwiftUI
import StandLessKit

/// The 3-screen onboarding flow (R33), replacing Phase 1's single-screen
/// `MinimalHealthAccessView`. HealthKit access is requested only after the third screen's
/// explanation (R2) — never before.
struct OnboardingView: View {
    private struct Page {
        let systemImage: String
        let title: String
        let subtitle: String
    }

    private static let pages: [Page] = [
        Page(
            systemImage: "arrow.up.and.person.rectangle.portrait",
            title: "Spend less time sitting.",
            subtitle: "StandLess helps you understand how much of your day you spend standing."
        ),
        Page(
            systemImage: "applewatch",
            title: "Your Apple Watch already measures standing activity.",
            subtitle: "StandLess turns that information into simple daily and weekly trends."
        ),
        Page(
            systemImage: "heart.text.square",
            title: "Connect Apple Health",
            subtitle: "Your health data stays private — on your device and inside Apple Health."
        )
    ]

    @State private var viewModel: OnboardingViewModel
    @State private var pageIndex = 0
    private let onFinished: () -> Void

    init(viewModel: OnboardingViewModel, onFinished: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pageIndex) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                    pageContent(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 20) {
                HStack(spacing: 6) {
                    ForEach(Self.pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == pageIndex ? MinimalHealthAccessView.standingAccent : Color(white: 0.85))
                            .frame(width: index == pageIndex ? 16 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)

                Button(action: advance) {
                    Text(pageIndex == Self.pages.count - 1 ? "Allow Health Access" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(MinimalHealthAccessView.standingAccent)
                .disabled(viewModel.isRequestingAccess)
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 34)
        }
    }

    private func pageContent(_ page: Page) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: page.systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(MinimalHealthAccessView.standingAccent)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(page.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func advance() {
        if pageIndex < Self.pages.count - 1 {
            pageIndex += 1
        } else {
            Task {
                await viewModel.requestHealthAccess()
                onFinished()
            }
        }
    }
}
