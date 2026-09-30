import SwiftUI

/// Code entry for the confirmation email sent at signup.
/// Mirrors `PhoneOTPForm` and reuses `OTPInputField`.
internal struct EmailVerificationForm: View {
  @Bindable internal var viewModel: SignupViewModel

  internal var body: some View {
    VStack(spacing: Spacing.lg) {
      instructions

      OTPInputField(
        code: $viewModel.otpCode,
        error: viewModel.fieldErrors.otp,
        onComplete: {
          Task { await viewModel.verifyEmailCode() }
        }
      )

      PrimaryButton(
        title: String(localized: .otpSubmitButton),
        action: {
          Task { await viewModel.verifyEmailCode() }
        },
        isLoading: viewModel.isLoading,
        isDisabled: viewModel.otpCode.count < SignupViewModel.codeLength
      )

      footerActions
    }
  }

  private var instructions: some View {
    VStack(spacing: Spacing.xs) {
      Text(.signupVerifyTitle)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(String(localized: .signupVerifySubtitle(viewModel.pendingEmail)))
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Text(.signupVerifyHint)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
    }
  }

  private var footerActions: some View {
    VStack(spacing: Spacing.micro) {
      resendButton
      backButton
    }
  }

  private var resendButton: some View {
    // The timeline redraws the button each second so the countdown stays current.
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = viewModel.resendSecondsRemaining(at: context.date)
      Button(action: {
        Task { await viewModel.resendCode() }
      }) {
        Text(resendTitle(secondsRemaining: remaining))
          .font(.tidexSubheadline)
          .foregroundColor(remaining > 0 ? .tidexTextMuted : .tidexBlueText)
          .multilineTextAlignment(.center)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(remaining > 0 || viewModel.isLoading)
    }
  }

  private func resendTitle(secondsRemaining: Int) -> String {
    if secondsRemaining > 0 {
      return String(localized: .signupVerifyResendIn(secondsRemaining))
    }
    return String(localized: .otpResendCode)
  }

  private var backButton: some View {
    Button(action: {
      viewModel.cancelEmailVerification()
    }) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "chevron.left")
          .font(.tidexCaption)
          .accessibilityHidden(true)
        Text(.signupVerifyBack)
          .font(.tidexSubheadline)
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  let viewModel = SignupViewModel()
  viewModel.showEmailVerification(email: "name@example.com")
  return EmailVerificationForm(viewModel: viewModel)
    .padding()
    .background(Color.tidexBackground)
}
