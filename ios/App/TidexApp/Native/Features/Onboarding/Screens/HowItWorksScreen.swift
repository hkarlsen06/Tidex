import SwiftUI

/// Screen 3: How It Works
/// Creates narrative tension through progressive visual hierarchy
/// - Step 1 feels "already done" (active state with pulse)
/// - Steps 2-3 are dimmed future states
/// - Vertical connector creates flow
/// - Outcome whisper at bottom reminds user of the payoff
struct HowItWorksScreen: View {
    @Environment(\.localization) private var localization
    @State private var stepsVisible = false
    @State private var outcomeVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Header - feels like a destination
            Text(localization.string("onboarding.how.title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
                .frame(height: 48)

            // Steps as a progression timeline, not a list
            // Centered as a unit with fixed width
            VStack(alignment: .center, spacing: 0) {
                StepItem(
                    icon: "clock.badge.checkmark",
                    title: localization.string("onboarding.how.step1.title"),
                    description: localization.string("onboarding.how.step1.desc"),
                    index: 0,
                    isVisible: stepsVisible,
                    progressState: .active,
                    showConnector: true
                )

                StepItem(
                    icon: "banknote",
                    title: localization.string("onboarding.how.step2.title"),
                    description: localization.string("onboarding.how.step2.desc"),
                    index: 1,
                    isVisible: stepsVisible,
                    progressState: .upcoming,
                    showConnector: true
                )

                StepItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: localization.string("onboarding.how.step3.title"),
                    description: localization.string("onboarding.how.step3.desc"),
                    index: 2,
                    isVisible: stepsVisible,
                    progressState: .future,
                    showConnector: false
                )
            }
            .padding(.horizontal, 40)  // Generous but not cramped

            Spacer()
                .frame(height: 28)

            // Outcome whisper - centered under the steps
            Text(localization.string("onboarding.how.outcome"))
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
        .environment(\.localization, LocalizationManager.shared)
}
