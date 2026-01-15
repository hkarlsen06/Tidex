import SwiftUI

/// OTP verification form for phone login
struct PhoneOTPForm: View {
    @ObservedObject var viewModel: LoginViewModel

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 20) {
            // Instructions
            VStack(spacing: 8) {
                Text(localization.string("otp.title"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("otp.subtitle", viewModel.normalizedPhone))
                    .font(.system(size: 14))
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
                title: localization.string("otp.submitButton"),
                action: {
                    Task { await viewModel.verifyOTP() }
                },
                isLoading: viewModel.isLoading,
                isDisabled: viewModel.otpCode.count < 6
            )

            // Resend code link
            Button(action: {
                Task { await viewModel.resendOTP() }
            }) {
                Text(localization.string("otp.resendCode"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            // Back to login link
            Button(action: {
                viewModel.backToInput()
            }) {
                Text(localization.string("otp.backToLogin"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextMuted)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    PhoneOTPForm(viewModel: LoginViewModel())
        .padding()
        .background(Color.tidexBackground)
}
