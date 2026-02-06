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
      VStack(spacing: 12) {
        Text(.onboardingGetstartedTitle)
          .font(.system(size: 28, weight: .bold))
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)

        Text(.onboardingGetstartedSubtitle)
          .font(.system(size: 17))
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 32)
      .adaptiveContentWidth()

      Spacer()

      // CTAs - constrained for iPad
      VStack(spacing: 12) {
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
      .padding(.horizontal, 24)
      .adaptiveContentWidth()
      .padding(.bottom, 24)
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
