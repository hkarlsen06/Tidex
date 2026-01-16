import SwiftUI

/// Screen 3: How It Works
/// Brief explanation of the shift tracking flow with staggered animations
struct HowItWorksScreen: View {
    @Environment(\.localization) private var localization
    @State private var stepsVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Header
            Text(localization.string("onboarding.how.title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
                .frame(height: 48)

            // Steps
            VStack(spacing: 28) {
                StepItem(
                    icon: "clock.badge.checkmark",
                    title: localization.string("onboarding.how.step1.title"),
                    description: localization.string("onboarding.how.step1.desc"),
                    index: 0,
                    isVisible: stepsVisible
                )

                StepItem(
                    icon: "banknote",
                    title: localization.string("onboarding.how.step2.title"),
                    description: localization.string("onboarding.how.step2.desc"),
                    index: 1,
                    isVisible: stepsVisible
                )

                StepItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: localization.string("onboarding.how.step3.title"),
                    description: localization.string("onboarding.how.step3.desc"),
                    index: 2,
                    isVisible: stepsVisible
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Trigger staggered animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                stepsVisible = true
            }
        }
    }
}

#Preview {
    HowItWorksScreen()
        .background(Color.tidexBackground)
        .environment(\.localization, LocalizationManager.shared)
}
