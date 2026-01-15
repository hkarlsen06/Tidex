import SwiftUI

/// Reset password screen with three-step flow
/// Step 1: Enter email/phone -> Step 2: OTP verification (phone only) -> Step 3: New password
struct ResetPasswordView: View {
    @StateObject private var viewModel = ResetPasswordViewModel()
    @Environment(\.localization) private var localization
    var onNavigateToLogin: (() -> Void)?

    // Animation state
    @State private var headerAppeared = false
    @State private var cardAppeared = false
    @State private var footerAppeared = false

    var body: some View {
        ZStack {
            // Background - adapts to system appearance
            Color.tidexBackground
                .ignoresSafeArea()

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Header with logo
                    headerView
                        .padding(.top, 40)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : -20)

                    // Main card
                    TidexCard {
                        VStack(spacing: 20) {
                            // Card header
                            cardHeader

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
                        .padding(24)
                    }
                    .opacity(cardAppeared ? 1 : 0)
                    .offset(y: cardAppeared ? 0 : 30)
                    .scaleEffect(cardAppeared ? 1 : 0.95)

                    // Footer - back to login link
                    if viewModel.currentStep == .input || viewModel.currentStep == .success {
                        footerView
                            .opacity(footerAppeared ? 1 : 0)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .loading(viewModel.isLoading)
        .onAppear {
            viewModel.onNavigateToLogin = onNavigateToLogin

            // Fast staggered entrance animations - feel snappy
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                headerAppeared = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05)) {
                cardAppeared = true
            }
            withAnimation(.easeOut(duration: 0.25).delay(0.1)) {
                footerAppeared = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 12) {
            LogoWatermark(opacity: 1.0)
                .frame(width: 60, height: 60)

            Text("Tidex")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Card Header

    private var cardHeader: some View {
        VStack(spacing: 8) {
            Text(cardTitle)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Text(cardSubtitle)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var cardTitle: String {
        switch viewModel.currentStep {
        case .input:
            return localization.string("resetPassword.title")
        case .otp:
            return localization.string("otp.title")
        case .newPassword:
            return localization.string("resetPassword.newPassword.title")
        case .success:
            return localization.string("resetPassword.success.title")
        }
    }

    private var cardSubtitle: String {
        switch viewModel.currentStep {
        case .input:
            return localization.string("resetPassword.subtitle")
        case .otp:
            return localization.string("otp.subtitle", viewModel.normalizedPhone)
        case .newPassword:
            return localization.string("resetPassword.newPassword.subtitle")
        case .success:
            return localization.string("resetPassword.success.subtitle")
        }
    }

    // MARK: - Input Step

    private var inputStepContent: some View {
        VStack(spacing: 16) {
            // Email/Phone field
            TidexTextField(
                label: localization.string("resetPassword.emailOrPhoneLabel"),
                placeholder: localization.string("resetPassword.emailOrPhonePlaceholder"),
                text: $viewModel.emailOrPhone,
                error: viewModel.fieldErrors.emailOrPhone,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                autocorrection: false
            )

            // Hint text
            Text(localization.string("resetPassword.hint"))
                .font(.system(size: 12))
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

    // MARK: - OTP Step

    private var otpStepContent: some View {
        VStack(spacing: 20) {
            // OTP Input
            OTPInputField(
                code: $viewModel.otpCode,
                error: viewModel.fieldErrors.otp
            )

            // Verify button
            PrimaryButton(
                title: localization.string("otp.submitButton"),
                action: {
                    Task { await viewModel.verifyOTP() }
                },
                isLoading: viewModel.isLoading
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

            // Back link
            backButton
        }
    }

    // MARK: - New Password Step

    private var newPasswordStepContent: some View {
        VStack(spacing: 16) {
            // New password field
            SecureTextField(
                label: localization.string("resetPassword.newPasswordLabel"),
                placeholder: localization.string("resetPassword.newPasswordPlaceholder"),
                text: $viewModel.newPassword,
                error: viewModel.fieldErrors.newPassword
            )

            // Confirm password field
            SecureTextField(
                label: localization.string("resetPassword.confirmPasswordLabel"),
                placeholder: localization.string("resetPassword.confirmPasswordPlaceholder"),
                text: $viewModel.confirmPassword,
                error: viewModel.fieldErrors.confirmPassword
            )

            // Password hint
            Text(localization.string("resetPassword.passwordHint"))
                .font(.system(size: 12))
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

    // MARK: - Success Step

    private var successStepContent: some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.tidexSuccess)

            Text(successMessage)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

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
                    .font(.system(size: 14))
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
                    .font(.system(size: 14))
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
