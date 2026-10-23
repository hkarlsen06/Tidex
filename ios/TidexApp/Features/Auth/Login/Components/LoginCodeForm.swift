import SwiftUI

/// Code entry for the email Clerk sends when a sign-in needs a second factor.
internal struct LoginCodeForm: View {
  @Bindable internal var viewModel: LoginViewModel

  internal var body: some View {
    VStack(spacing: Spacing.lg) {
      instructions

      OTPInputField(
        code: $viewModel.otpCode,
        error: viewModel.fieldErrors.otp,
        onComplete: {
          Task { await viewModel.verifyOTP() }
        }
      )

      PrimaryButton(
        title: String(localized: .otpSubmitButton),
        action: {
          Task { await viewModel.verifyOTP() }
        },
        isLoading: viewModel.isLoading,
        isDisabled: viewModel.otpCode.count < LoginViewModel.codeLength
      )

      footerActions
    }
  }

  private var instructions: some View {
    VStack(spacing: Spacing.xs) {
      Text(.otpTitle)
        .font(.tidexTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Text(String(localized: .otpSubtitle(viewModel.email)))
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
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
    Button(action: {
      Task { await viewModel.resendOTP() }
    }) {
      Text(.otpResendCode)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexBlueText)
        .multilineTextAlignment(.center)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isLoading)
  }

  private var backButton: some View {
    Button(action: {
      viewModel.backToInput()
    }) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "chevron.left")
          .font(.tidexCaption)
          .accessibilityHidden(true)
        Text(.otpBackToLogin)
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
  LoginCodeForm(viewModel: LoginViewModel())
    .padding()
    .background(Color.tidexBackground)
}
