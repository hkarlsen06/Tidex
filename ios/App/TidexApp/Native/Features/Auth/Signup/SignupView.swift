import SwiftUI

/// Main signup screen view
/// Supports email/password, phone/OTP, Google, and Apple sign-up
struct SignupView: View {
    @StateObject private var viewModel = SignupViewModel()
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

            // Content - constrained for iPad
            ScrollView {
                VStack(spacing: 24) {
                    // Header with logo
                    headerView
                        .padding(.top, 40)
                        .opacity(headerAppeared ? 1 : 0)
                        .offset(y: headerAppeared ? 0 : -20)

                    // Main card - constrained width for iPad
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
                                SignupOTPForm(viewModel: viewModel)
                            }
                        }
                        .padding(24)
                    }
                    .adaptiveFormWidth()
                    .opacity(cardAppeared ? 1 : 0)
                    .offset(y: cardAppeared ? 0 : 30)
                    .scaleEffect(cardAppeared ? 1 : 0.95)

                    // Footer
                    if viewModel.currentStep == .input {
                        footerView
                            .opacity(footerAppeared ? 1 : 0)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .loading(viewModel.isLoading)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
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
            // Logo
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
            return localization.string("signup.title")
        case .otp:
            return localization.string("otp.title")
        }
    }

    private var cardSubtitle: String {
        switch viewModel.currentStep {
        case .input:
            return localization.string("signup.subtitle")
        case .otp:
            return localization.string("otp.subtitle", viewModel.normalizedPhone)
        }
    }

    // MARK: - Input Step Content

    @ViewBuilder
    private var inputStepContent: some View {
        // OAuth buttons
        OAuthButtonsView(
            onGoogleTap: { Task { await viewModel.signUpWithGoogle() } },
            onAppleTap: { Task { await viewModel.signUpWithApple() } },
            isLoading: viewModel.isLoading
        )

        // Divider
        dividerView

        // Email/phone form
        if viewModel.showEmailForm {
            SignupForm(viewModel: viewModel)
        } else {
            OutlineButton(
                title: localization.string("signup.emailOrPhoneReveal"),
                action: { viewModel.showEmailForm = true },
                icon: "envelope"
            )
        }
    }

    // MARK: - Divider

    private var dividerView: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.tidexBorderSubtle)
                .frame(height: 1)

            Text(localization.string("login.separator"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextMuted)

            Rectangle()
                .fill(Color.tidexBorderSubtle)
                .frame(height: 1)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 4) {
            Text(localization.string("signup.hasAccount"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Button(action: {
                onNavigateToLogin?()
            }) {
                Text(localization.string("signup.login"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Signup Form

/// Email/phone, password, and terms form for signup
struct SignupForm: View {
    @ObservedObject var viewModel: SignupViewModel
    @Environment(\.localization) private var localization

    var body: some View {
        VStack(spacing: 16) {
            // Email/Phone field
            TidexTextField(
                label: localization.string("signup.emailOrPhoneLabel"),
                placeholder: localization.string("signup.emailOrPhonePlaceholder"),
                text: $viewModel.emailOrPhone,
                error: viewModel.fieldErrors.emailOrPhone,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                autocapitalization: .never,
                autocorrection: false
            )

            // Password field
            SecureTextField(
                label: localization.string("signup.passwordLabel"),
                placeholder: localization.string("signup.passwordPlaceholder"),
                text: $viewModel.password,
                error: viewModel.fieldErrors.password
            )

            // Password hint
            Text(localization.string("signup.passwordHint"))
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Submit button
            PrimaryButton(
                title: localization.string("signup.submitButton"),
                action: {
                    Task { await viewModel.signUp() }
                },
                isLoading: viewModel.isLoading
            )
        }
    }
}

// MARK: - Signup OTP Form

/// OTP verification form for phone signup
struct SignupOTPForm: View {
    @ObservedObject var viewModel: SignupViewModel
    @Environment(\.localization) private var localization

    var body: some View {
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
            Button(action: {
                viewModel.backToInput()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                    Text(localization.string("signup.backToSignup"))
                        .font(.system(size: 14))
                }
                .foregroundColor(.tidexTextSecondary)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SignupView()
        .environment(\.localization, LocalizationManager.shared)
}
