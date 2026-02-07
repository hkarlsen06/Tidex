import SwiftUI

/// OTP verification form for phone login with native iOS styling
struct PhoneOTPForm: View {
  @ObservedObject var viewModel: LoginViewModel

  var body: some View {
    VStack(spacing: Spacing.lg) {
      // Instructions
      VStack(spacing: Spacing.xs) {
        Text(.otpTitle)
          .font(.tidexTitle)
          .foregroundColor(.tidexTextPrimary)

        Text(String(localized: .otpSubtitle(viewModel.normalizedPhone)))
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      // OTP input
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
        isDisabled: viewModel.otpCode.count < 6
      )

      // Resend and back links
      VStack(spacing: Spacing.md) {
        Button(action: {
          Task { await viewModel.resendOTP() }
        }) {
          Text(.otpResendCode)
            .font(.tidexSubheadline)
            .foregroundColor(.tidexBlue)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)

        Button(action: {
          viewModel.backToInput()
        }) {
          HStack(spacing: Spacing.xxs) {
            Image(systemName: "chevron.left")
              .font(.tidexCaption)
            Text(.otpBackToLogin)
              .font(.tidexSubheadline)
          }
          .foregroundColor(.tidexTextSecondary)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

#Preview {
  PhoneOTPForm(viewModel: LoginViewModel())
    .padding()
    .background(Color.tidexBackground)
}
