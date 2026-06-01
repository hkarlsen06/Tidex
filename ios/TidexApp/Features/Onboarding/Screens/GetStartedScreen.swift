import SwiftUI

/// Screen 4: Get Started (CTA)
/// Convert interest into action - sign up or log in
struct GetStartedScreen: View {
  let onCreateAccount: () -> Void
  let onLogin: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      // Icon/illustration
      ZStack {
        Circle()
          .fill(Color.tidexBlue.opacity(0.1))
          .frame(width: 120, height: 120)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 64))
          .foregroundColor(.tidexBlue)
      }

      Spacer()
        .frame(height: 32)

      // Header and subheadline - constrained for iPad
      VStack(spacing: Spacing.sm) {
        Text(.onboardingGetstartedTitle)
          .font(.tidexScreenTitle)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)

        Text(.onboardingGetstartedSubtitle)
          .font(.tidexBody)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, Spacing.xl)
      .adaptiveContentWidth()

      Spacer()

      // CTAs - constrained for iPad
      VStack(spacing: Spacing.lg) {
        OnboardingButton(
          title: String(localized: .onboardingGetstartedSignup),
          action: onCreateAccount
        )

        OnboardingButton(
          title: String(localized: .onboardingGetstartedLogin),
          action: onLogin,
          style: .secondary
        )
      }
      .padding(.horizontal, Spacing.lg)
      .adaptiveContentWidth()
      .padding(.bottom, Spacing.lg)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  GetStartedScreen(
    onCreateAccount: {},
    onLogin: {}
  )
  .background(Color.tidexBackground)
}
