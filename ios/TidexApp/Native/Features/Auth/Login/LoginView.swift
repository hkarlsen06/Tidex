import SwiftUI

/// Main login screen view with native iOS styling
/// Supports email/password, phone/OTP, Google, and Apple sign-in
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    
    // Navigation callbacks
    var onNavigateToSignup: (() -> Void)?
    var onNavigateToResetPassword: (() -> Void)?

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
                            PhoneOTPForm(viewModel: viewModel)
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
            Text(.loginSubtitle)
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
                onGoogleTap: { Task { await viewModel.signInWithGoogle() } },
                onAppleTap: { Task { await viewModel.signInWithApple() } },
                isLoading: viewModel.isLoading
            )

            // Divider
            dividerView
                .padding(.vertical, 8)

            // Email/phone form or reveal button
            if viewModel.showEmailForm {
                emailFormSection
            } else {
                revealEmailButton
            }
        }
    }

    // MARK: - Email Form Section

    private var emailFormSection: some View {
        VStack(spacing: 16) {
            // Form fields in a grouped style
            VStack(spacing: 0) {
                // Email/Phone field
                NativeTextField(
                    placeholder: String(localized: .loginEmailOrPhonePlaceholder),
                    text: $viewModel.emailOrPhone,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )

                Divider()
                    .background(Color.tidexBorderSubtle)

                // Password field
                NativeSecureField(
                    placeholder: viewModel.inputType == .phone
                        ? String(localized: .loginPasswordOptionalLabel)
                        : String(localized: .loginPasswordPlaceholder),
                    text: $viewModel.password,
                    onSubmit: {
                        Task { await viewModel.signIn() }
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

            // Forgot password link (only for email login)
            if viewModel.inputType == .email {
                HStack {
                    Spacer()
                    Button(action: {
                        onNavigateToResetPassword?()
                    }) {
                        Text(.loginForgotPassword)
                            .font(.system(size: 15))
                            .foregroundColor(.tidexBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Phone hint - password is optional for OTP flow
            if viewModel.inputType == .phone {
                Text(.loginPhonePasswordHint)
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Submit button
            PrimaryButton(
                title: String(localized: .loginSubmitButton),
                action: {
                    Task { await viewModel.signIn() }
                },
                isLoading: viewModel.isLoading
            )
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
                Text(.loginEmailOrPhoneReveal)
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
            Text(.loginNoAccount)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)

            Button(action: {
                onNavigateToSignup?()
            }) {
                Text(.loginCreateAccount)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.tidexBlue)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Native Text Field

/// A text field styled like native iOS grouped forms
struct NativeTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 17))
            .foregroundColor(.tidexTextPrimary)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .onSubmit {
                onSubmit?()
            }
    }
}

// MARK: - Native Secure Field

/// A secure field styled like native iOS grouped forms
struct NativeSecureField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var isSecure: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 17))
                    .foregroundColor(.tidexTextPrimary)
                    .textContentType(.password)
                    .focused($isFocused)
                    .onSubmit {
                        onSubmit?()
                    }
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 17))
                    .foregroundColor(.tidexTextPrimary)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit {
                        onSubmit?()
                    }
            }

            Button {
                isSecure.toggle()
            } label: {
                Image(systemName: isSecure ? "eye" : "eye.slash")
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Snappy Button Style

/// Button style with immediate press feedback
struct SnappyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    LoginView()
}
