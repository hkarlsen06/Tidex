import SwiftUI

/// Screen 3: How It Works
/// Creates narrative tension through progressive visual hierarchy
/// - Step 1 feels "already done" (active state with pulse)
/// - Steps 2-3 are dimmed future states
/// - Vertical connector creates flow
/// - Outcome whisper at bottom reminds user of the payoff
struct HowItWorksScreen: View {
        @State private var stepsVisible = false
    @State private var outcomeVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Header - feels like a destination
            Text(.onboardingHowTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
                .frame(height: 48)

            // Steps as a progression timeline, not a list
            // Centered as a unit with constrained width for iPad
            VStack(alignment: .leading, spacing: 0) {
                StepItem(
                    icon: "clock.badge.checkmark",
                    title: String(localized: .onboardingHowStep1Title),
                    description: String(localized: .onboardingHowStep1Desc),
                    index: 0,
                    isVisible: stepsVisible,
                    progressState: .active,
                    showConnector: true
                )

                StepItem(
                    icon: "banknote",
                    title: String(localized: .onboardingHowStep2Title),
                    description: String(localized: .onboardingHowStep2Desc),
                    index: 1,
                    isVisible: stepsVisible,
                    progressState: .upcoming,
                    showConnector: true
                )

                StepItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: String(localized: .onboardingHowStep3Title),
                    description: String(localized: .onboardingHowStep3Desc),
                    index: 2,
                    isVisible: stepsVisible,
                    progressState: .future,
                    showConnector: false
                )
            }
            .frame(maxWidth: AdaptiveMaxWidth.content)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 28)

            // Outcome whisper - centered under the steps
            Text(.onboardingHowOutcome)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexBlue)
                .opacity(outcomeVisible ? 0.6 : 0)
                .offset(y: outcomeVisible ? 0 : 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Trigger step animations
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                stepsVisible = true
            }
            // Outcome fades in after steps settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeOut(duration: 0.5)) {
                    outcomeVisible = true
                }
            }
        }
    }
}

#Preview {
    HowItWorksScreen()
        .background(Color.tidexBackground)
}
