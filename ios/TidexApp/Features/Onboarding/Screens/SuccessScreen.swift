import SwiftUI
import UIKit

/// Screen 6: Success/Ready
/// Confirms setup complete, shows save status, transitions to app
struct SuccessScreen: View {
  let completionMode: OnboardingCompletionMode
  // New API with save status handling
  var saveStatus: OnboardingSaveManager.SaveStatus = .success
  var errorMessage: String?
  let onComplete: () -> Void
  var onRetry: (() -> Void)?

  @State private var checkmarkScale: CGFloat = 0.0
  @State private var checkmarkOpacity: Double = 0.0
  @State private var contentVisible = false

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        Spacer()

        // Animated checkmark or loading
        statusAnimation

        Spacer()
          .frame(height: 32)

        // Header and content - constrained for iPad
        VStack(spacing: Spacing.sm) {
          Text(statusTitle)
            .font(.tidexScreenTitle)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.center)

          Text(statusSubtitle)
            .font(.tidexBody)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)

          if saveStatus == .success || saveStatus == .idle {
            Spacer()
              .frame(height: 8)

            // Reassurance line
            Text(reassuranceText)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextMuted)
              .multilineTextAlignment(.center)
              .padding(.horizontal, Spacing.md)
          }
        }
        .padding(.horizontal, Spacing.xl)
        .adaptiveContentWidth()
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 20)

        // Error message
        if saveStatus == .error, let errorMessage = errorMessage {
          Spacer()
            .frame(height: 24)

          errorBanner(message: errorMessage)
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()
        }

        Spacer()

        // Bottom button(s)
        VStack(spacing: Spacing.sm) {
          // Go to Dashboard button
          OnboardingButton(
            title: buttonTitle,
            action: {
              UIImpactFeedbackGenerator(style: .medium).impactOccurred()
              onComplete()
            }
          )
          .disabled(!saveStatus.allowsCompletion)
          .opacity(saveStatus.allowsCompletion ? 1 : 0.5)

          // Retry button (only on error)
          if saveStatus == .error, let onRetry = onRetry {
            Button(action: {
              UIImpactFeedbackGenerator(style: .medium).impactOccurred()
              onRetry()
            }) {
              Text(.commonRetry)
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexBlue)
            }
          }
        }
        .padding(.horizontal, Spacing.lg)
        .adaptiveContentWidth()
        .padding(.bottom, Spacing.xl)
        .opacity(contentVisible ? 1 : 0)
      }
    }
    .onAppear {
      startAnimations()
    }
    .onChange(of: saveStatus) { _, newStatus in
      if newStatus == .success {
        // Play success haptic when save completes
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } else if newStatus == .error {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
      }
    }
  }

  // MARK: - Status Animation

  @ViewBuilder
  private var statusAnimation: some View {
    ZStack {
      switch saveStatus {
      case .idle, .success:
        // Checkmark
        Circle()
          .fill(Color.tidexSuccess.opacity(0.15))
          .frame(width: 120, height: 120)
          .scaleEffect(checkmarkScale)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 80))
          .foregroundColor(.tidexSuccess)
          .scaleEffect(checkmarkScale)
          .opacity(checkmarkOpacity)

      case .saving:
        // Loading spinner
        Circle()
          .fill(Color.tidexBlue.opacity(0.15))
          .frame(width: 120, height: 120)

        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(1.5)
          .tint(.tidexBlue)

      case .error:
        // Error icon
        Circle()
          .fill(Color.tidexError.opacity(0.15))
          .frame(width: 120, height: 120)

        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 80))
          .foregroundColor(.tidexError)
      }
    }
  }

  // MARK: - Status Text

  private var statusTitle: String {
    switch saveStatus {
    case .idle, .success:
      switch completionMode {
      case .fullSetup:
        return String(localized: .onboardingSuccessTitle)
      case .friendOnlySkip:
        return String(
          localized: "onboarding.success.friend_only.title", table: "Localizable")
      }
    case .saving:
      return String(localized: .onboardingSuccessSavingTitle)
    case .error:
      return String(localized: .onboardingSuccessErrorTitle)
    }
  }

  private var statusSubtitle: String {
    switch saveStatus {
    case .idle, .success:
      switch completionMode {
      case .fullSetup:
        return String(localized: .onboardingSuccessSubtitle)
      case .friendOnlySkip:
        return String(
          localized: "onboarding.success.friend_only.subtitle", table: "Localizable")
      }
    case .saving:
      return String(localized: .onboardingSuccessSaving)
    case .error:
      return String(localized: .onboardingSuccessErrorSubtitle)
    }
  }

  private var reassuranceText: LocalizedStringResource {
    switch completionMode {
    case .fullSetup:
      return .onboardingSuccessReassurance
    case .friendOnlySkip:
      return LocalizedStringResource(
        "onboarding.success.friend_only.reassurance", table: "Localizable")
    }
  }

  private var buttonTitle: String {
    switch completionMode {
    case .fullSetup:
      return String(localized: .onboardingSuccessButton)
    case .friendOnlySkip:
      return String(localized: "onboarding.success.friend_only.button", table: "Localizable")
    }
  }

  // MARK: - Error Banner

  @ViewBuilder
  private func errorBanner(message: String) -> some View {
    HStack(spacing: Spacing.sm) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.tidexBody)
        .foregroundColor(.tidexError)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .lineLimit(3)

      Spacer()
    }
    .padding(Spacing.md)
    .background(Color.tidexError.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  // MARK: - Animation Sequence

  private func startAnimations() {
    // Only animate checkmark for idle/success states
    if saveStatus == .idle || saveStatus == .success {
      // Checkmark draw and scale animation
      withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
        checkmarkScale = 1.1
        checkmarkOpacity = 1.0
      }

      // Settle to normal scale
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.4)) {
        checkmarkScale = 1.0
      }

      // Success haptic
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      }
    }

    // Show content
    withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
      contentVisible = true
    }
  }
}

#Preview("Success") {
  SuccessScreen(
    completionMode: .fullSetup,
    saveStatus: .success,
    onComplete: {},
    onRetry: nil
  )
}

#Preview("Saving") {
  SuccessScreen(
    completionMode: .fullSetup,
    saveStatus: .saving,
    onComplete: {},
    onRetry: nil
  )
}

#Preview("Error") {
  SuccessScreen(
    completionMode: .fullSetup,
    saveStatus: .error,
    errorMessage: "Could not connect to server. Please check your internet connection.",
    onComplete: {},
    onRetry: {}
  )
}
