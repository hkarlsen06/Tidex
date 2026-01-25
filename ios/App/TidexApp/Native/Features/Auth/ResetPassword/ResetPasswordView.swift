import SwiftUI

/// Reset password screen with native iOS styling
/// Step 1: Enter email/phone -> Step 2: OTP verification (phone only) -> Step 3: New password
struct ResetPasswordView: View {
    @StateObject private var viewModel = ResetPasswordViewModel()
    @Environment(\.localization) private var localization
    var onNavigateToLogin: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    // Header section
                    headerSection
                        .padding(.bottom, 40)

                    // Main content
                    VStack(spacing: 24) {
                        // Error/Success banners
                        if let error = viewModel.errorMessage {
                            ErrorBanner(
                                message: error,
                                onDismiss: { viewModel.errorMessage = nil }
                            )
                        }

                        if let success = viewModel.successMessage {
                            SuccessBanner(
                                message: success,
                                onDismiss: { viewModel.successMessage = nil }
                            )
                        }

                        // Step content
                        switch viewModel.currentStep {
                        case .input:
                            inputStepContent
                        case .otp:
                            otpStepContent
                        case .newPassword:
                            newPasswordStepContent
                        case .success:
                            successStepContent
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 60)

                    // Footer - back to login link
                    if viewModel.currentStep == .input {
                        footerView
                            .padding(.bottom, 40)
                    }
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.tidexBackground)
        .loading(viewModel.isLoading)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            viewModel.onNavigateToLogin = onNavigateToLogin
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Key icon for reset password
            ZStack {
                Circle()
                    .fill(Color.tidexBlue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.tidexBlue)
            }

            // Title
            Text("Tidex")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Input Step

    private var inputStepContent: some View {
        VStack(spacing: 24) {
            // Instructions
            VStack(spacing: 8) {
                Text(localization.string("resetPassword.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("resetPassword.subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                // Email/Phone field in grouped style
                VStack(spacing: 0) {
                    NativeTextField(
                        placeholder: localization.string("resetPassword.emailOrPhonePlaceholder"),
                        text: $viewModel.emailOrPhone,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )
                }
                .background(Color.tidexSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Error message
                if let emailError = viewModel.fieldErrors.emailOrPhone {
                    Text(emailError)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                // Hint text
                Text(localization.string("resetPassword.hint"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Submit button
                PrimaryButton(
                    title: localization.string("resetPassword.submitButton"),
                    action: {
                        Task { await viewModel.sendResetCode() }
                    },
                    isLoading: viewModel.isLoading
                )
            }
        }
    }

    // MARK: - OTP Step

    private var otpStepContent: some View {
        VStack(spacing: 24) {
            // Instructions
            VStack(spacing: 8) {
                Text(localization.string("otp.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("otp.subtitle", viewModel.normalizedPhone))
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // OTP Input
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

            // Resend and back links
            VStack(spacing: 16) {
                Button(action: {
                    Task { await viewModel.resendOTP() }
                }) {
                    Text(localization.string("otp.resendCode"))
                        .font(.system(size: 15))
                        .foregroundColor(.tidexBlue)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)

                backButton
            }
        }
    }

    // MARK: - New Password Step

    private var newPasswordStepContent: some View {
        VStack(spacing: 24) {
            // Instructions
            VStack(spacing: 8) {
                Text(localization.string("resetPassword.newPassword.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(localization.string("resetPassword.newPassword.subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                // Password fields in grouped style
                VStack(spacing: 0) {
                    NativeSecureField(
                        placeholder: localization.string("resetPassword.newPasswordPlaceholder"),
                        text: $viewModel.newPassword
                    )

                    Divider()
                        .background(Color.tidexBorderSubtle)

                    NativeSecureField(
                        placeholder: localization.string("resetPassword.confirmPasswordPlaceholder"),
                        text: $viewModel.confirmPassword,
                        onSubmit: {
                            Task { await viewModel.updatePassword() }
                        }
                    )
                }
                .background(Color.tidexSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Error messages
                if let newPasswordError = viewModel.fieldErrors.newPassword {
                    Text(newPasswordError)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                if let confirmError = viewModel.fieldErrors.confirmPassword {
                    Text(confirmError)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }

                // Password hint
                Text(localization.string("resetPassword.passwordHint"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Submit button
                PrimaryButton(
                    title: localization.string("resetPassword.updatePasswordButton"),
                    action: {
                        Task { await viewModel.updatePassword() }
                    },
                    isLoading: viewModel.isLoading
                )

                // Back link
                backButton
            }
        }
    }

    // MARK: - Success Step

    private var successStepContent: some View {
        VStack(spacing: 24) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.tidexSuccess.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.tidexSuccess)
            }

            // Instructions
            VStack(spacing: 8) {
                Text(localization.string("resetPassword.success.title"))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(successMessage)
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // Back to login button
            PrimaryButton(
                title: localization.string("resetPassword.backToLogin"),
                action: { onNavigateToLogin?() }
            )
        }
    }

    private var successMessage: String {
        if viewModel.inputType == .email {
            return localization.string("resetPassword.success.emailInstructions")
        } else {
            return localization.string("resetPassword.success.passwordUpdatedInstructions")
        }
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: {
            viewModel.goBack()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                Text(localization.string("common.back"))
                    .font(.system(size: 15))
            }
            .foregroundColor(.tidexTextSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerView: some View {
        Button(action: {
            onNavigateToLogin?()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                Text(localization.string("resetPassword.backToLogin"))
                    .font(.system(size: 15))
            }
            .foregroundColor(.tidexTextSecondary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ResetPasswordView()
        .environment(\.localization, LocalizationManager.shared)
}
