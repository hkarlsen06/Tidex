import SwiftUI

/// OTP verification form for phone login with native iOS styling
struct PhoneOTPForm: View {
    @ObservedObject var viewModel: LoginViewModel

    
    var body: some View {
        VStack(spacing: 24) {
            // Instructions
            VStack(spacing: 8) {
                Text(.otpTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(String(localized: .otpSubtitle(viewModel.normalizedPhone)))
                    .font(.system(size: 15))
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
            VStack(spacing: 16) {
                Button(action: {
                    Task { await viewModel.resendOTP() }
                }) {
                    Text(.otpResendCode)
                        .font(.system(size: 15))
                        .foregroundColor(.tidexBlue)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)

                Button(action: {
                    viewModel.backToInput()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text(.otpBackToLogin)
                            .font(.system(size: 15))
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
