import SwiftUI

/// Screen 1: Welcome/Hero
/// Establishes brand, creates emotional connection, sets expectation
struct WelcomeScreen: View {
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo with subtle glow effect
            logoSection

            Spacer()
                .frame(height: 48)

            // Headline and subheadline
            textContent

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var logoSection: some View {
        ZStack {
            // Subtle gradient glow behind logo
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.tidexBlue.opacity(0.3),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 50,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 30)

            // App logo
            Image("Splash")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180, height: 180)
        }
    }

    @ViewBuilder
    private var textContent: some View {
        VStack(spacing: 12) {
            // Headline with gradient text effect
            Text(localization.string("onboarding.welcome.title"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.tidexBlue, .tidexBlue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)

            // Subheadline
            Text(localization.string("onboarding.welcome.subtitle"))
                .font(.system(size: 17))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
}

#Preview {
    WelcomeScreen()
        .background(Color.tidexBackground)
        .environment(\.localization, LocalizationManager.shared)
}
