import SwiftUI

/// Screen 6: Success/Ready
/// Confirms setup complete, shows save status, transitions to app
struct SuccessScreen: View {
  let completionMode: OnboardingCompletionMode
  // New API with save status handling
  var saveStatus: OnboardingSaveManager.SaveStatus = .success
  var errorMessage: String?
  let onComplete: () -> Void
  /// Opens the Add screen after setup. When set, it is the primary action and
  /// `onComplete` moves to a secondary button. Ignored for the friends-only path.
  var onAddFirstShift: (() -> Void)?
  var onRetry: (() -> Void)?

  @State private var checkmarkScale: CGFloat = 0.0
  @State private var checkmarkOpacity: Double = 0.0
  @State private var contentVisible = false
  @State private var showCalendarImport = false
  @State private var didImportFromCalendar = false

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
          .frame(height: Spacing.xl)

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
        if saveStatus == .error, let errorMessage {
          Spacer()
            .frame(height: 24)

          errorBanner(message: errorMessage)
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()
        }

        Spacer()

        // Bottom button(s)
        VStack(spacing: Spacing.sm) {
          // Add first shift, or Go to Dashboard / Friends when there is no shift to add
          OnboardingButton(
            title: addFirstShiftAction == nil
              ? buttonTitle : String(localized: .onboardingSuccessAddFirstShift),
            action: {
              Haptics.play(.medium)
              (addFirstShiftAction ?? onComplete)()
            }
          )
          .disabled(!saveStatus.allowsCompletion)
          .opacity(saveStatus.allowsCompletion ? 1 : 0.5)

          if addFirstShiftAction != nil {
            OnboardingButton(title: buttonTitle, action: onComplete, style: .secondary)
              .disabled(!saveStatus.allowsCompletion)
              .opacity(saveStatus.allowsCompletion ? 1 : 0.5)
          }

          // Import from an employer calendar link (Planday, Quinyx, Tamigo, MinGat)
          if completionMode == .fullSetup, saveStatus.allowsCompletion {
            Button {
              Haptics.play(.light)
              showCalendarImport = true
            } label: {
              Text(.calendarImportEntryButton)
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexBlue)
            }
          }

          // Retry button (only on error)
          if saveStatus == .error, let onRetry {
            Button(action: {
              Haptics.play(.medium)
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
        startAnimations()
      } else if newStatus == .error {
        withAnimation(.easeOut(duration: 0.2)) {
          contentVisible = true
        }
      }
    }
    .sensoryFeedback(.success, trigger: saveStatus) { _, newValue in newValue == .success }
    .sensoryFeedback(.error, trigger: saveStatus) { _, newValue in newValue == .error }
    .sheet(
      isPresented: $showCalendarImport,
      onDismiss: {
        // Shifts are in, so finish onboarding and show them in the app.
        if didImportFromCalendar {
          onComplete()
        }
      }
    ) {
      CalendarImportView { _ in
        didImportFromCalendar = true
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
        return String(localized: .onboardingSuccessFriendOnlyTitle)
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
        return String(localized: .onboardingSuccessFriendOnlySubtitle)
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
      return .onboardingSuccessFriendOnlyReassurance
    }
  }

  private var addFirstShiftAction: (() -> Void)? {
    completionMode == .fullSetup ? onAddFirstShift : nil
  }

  private var buttonTitle: String {
    switch completionMode {
    case .fullSetup:
      return String(localized: .onboardingSuccessButton)

    case .friendOnlySkip:
      return String(localized: .onboardingSuccessFriendOnlyButton)
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
    checkmarkScale = 0
    checkmarkOpacity = 0

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
        Haptics.play(.success)
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
    onAddFirstShift: {},
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
