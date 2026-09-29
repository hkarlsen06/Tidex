import SwiftUI

/// OTP verification form for phone login with native iOS styling
internal struct PhoneOTPForm: View {
  @Bindable internal var viewModel: LoginViewModel

  private let otpCodeLength: Int = 6

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

      // Verify button
      PrimaryButton(
        title: String(localized: .otpSubmitButton),
        action: {
          Task { await viewModel.verifyOTP() }
        },
        isLoading: viewModel.isLoading,
        isDisabled: viewModel.otpCode.count < otpCodeLength
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

      Text(String(localized: .otpSubtitle(viewModel.normalizedPhone)))
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
  PhoneOTPForm(viewModel: LoginViewModel())
    .padding()
    .background(Color.tidexBackground)
}
