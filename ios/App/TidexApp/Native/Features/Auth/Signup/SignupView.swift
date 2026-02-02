import SwiftUI

/// Main signup screen view with native iOS styling
/// Supports email/password, phone/OTP, Google, and Apple sign-up
struct SignupView: View {
    @StateObject private var viewModel = SignupViewModel()
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
                            SignupOTPForm(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 60)

                    // Footer
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
            // Full wordmark
            Image("TidexWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 48)

            // Subtitle
            Text(.signupSubtitle)
                .font(.system(size: 17))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Input Step Content

    @ViewBuilder
    private var inputStepContent: some View {
        VStack(spacing: 16) {
            // OAuth buttons
            OAuthButtonsView(
                onGoogleTap: { Task { await viewModel.signUpWithGoogle() } },
                onAppleTap: { Task { await viewModel.signUpWithApple() } },
                isLoading: viewModel.isLoading
            )

            // Divider
            dividerView
                .padding(.vertical, 8)

            // Email/phone form or reveal button
            if viewModel.showEmailForm {
                SignupForm(viewModel: viewModel)
            } else {
                revealEmailButton
            }
        }
    }

    // MARK: - Reveal Email Button

    private var revealEmailButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.showEmailForm = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.system(size: 16))
                Text(.signupEmailOrPhoneReveal)
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.tidexTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.tidexSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SnappyButtonStyle())
    }

    // MARK: - Divider

    private var dividerView: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.tidexBorderSubtle)
                .frame(height: 1)

            Text(.loginSeparator)
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
            Text(.signupHasAccount)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)

            Button(action: {
                onNavigateToLogin?()
            }) {
                Text(.signupLogin)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Signup Form

/// Email/phone, password, and terms form for signup with native iOS styling
struct SignupForm: View {
    @ObservedObject var viewModel: SignupViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Name fields side by side
            HStack(spacing: 12) {
                // First name
                VStack(spacing: 0) {
                    TextField(String(localized: .signupFirstNamePlaceholder), text: $viewModel.firstName)
                        .font(.system(size: 17))
                        .foregroundColor(.tidexTextPrimary)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(Color.tidexSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Last name
                VStack(spacing: 0) {
                    TextField(String(localized: .signupLastNamePlaceholder), text: $viewModel.lastName)
                        .font(.system(size: 17))
                        .foregroundColor(.tidexTextPrimary)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(Color.tidexSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Name error messages
            if let firstNameError = viewModel.fieldErrors.firstName {
                Text(firstNameError)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if let lastNameError = viewModel.fieldErrors.lastName {
                Text(lastNameError)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            // Email/Phone and Password in grouped style
            VStack(spacing: 0) {
                // Email/Phone field
                NativeTextField(
                    placeholder: String(localized: .signupEmailOrPhonePlaceholder),
                    text: $viewModel.emailOrPhone,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )

                Divider()
                    .background(Color.tidexBorderSubtle)

                // Password field
                NativeSecureField(
                    placeholder: String(localized: .signupPasswordPlaceholder),
                    text: $viewModel.password,
                    onSubmit: {
                        Task { await viewModel.signUp() }
                    }
                )
            }
            .background(Color.tidexSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Error messages
            if let emailError = viewModel.fieldErrors.emailOrPhone {
                Text(emailError)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if let passwordError = viewModel.fieldErrors.password {
                Text(passwordError)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            // Password hint
            Text(.signupPasswordHint)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Submit button
            PrimaryButton(
                title: String(localized: .signupSubmitButton),
                action: {
                    Task { await viewModel.signUp() }
                },
                isLoading: viewModel.isLoading
            )
        }
    }
}

// MARK: - Signup OTP Form

/// OTP verification form for phone signup with native iOS styling
struct SignupOTPForm: View {
    @ObservedObject var viewModel: SignupViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            // OTP explanation
            VStack(spacing: 8) {
                Text(.otpTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)

                Text(String(localized: .otpSubtitle(viewModel.normalizedPhone)))
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // OTP Input
            OTPInputField(
                code: $viewModel.otpCode,
                error: viewModel.fieldErrors.otp
            )

            // Verify button
            PrimaryButton(
                title: String(localized: .otpSubmitButton),
                action: {
                    Task { await viewModel.verifyOTP() }
                },
                isLoading: viewModel.isLoading
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
                        Text(.signupBackToSignup)
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
    SignupView()
}
