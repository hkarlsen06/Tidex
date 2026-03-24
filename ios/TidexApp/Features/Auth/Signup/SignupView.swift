import SwiftUI

/// Main signup screen view with native iOS styling
/// Supports email/password, phone/OTP, Google, and Apple sign-up
struct SignupView: View {
  @ObservedObject var viewModel: SignupViewModel
  var onNavigateToLogin: (() -> Void)?

  init(
    viewModel: SignupViewModel,
    onNavigateToLogin: (() -> Void)? = nil
  ) {
    self.viewModel = viewModel
    self.onNavigateToLogin = onNavigateToLogin
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          Spacer(minLength: 60)

          // Header section
          headerSection
            .padding(.bottom, Spacing.xxl)

          // Main content
          VStack(spacing: Spacing.lg) {
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
          .padding(.horizontal, Spacing.lg)

          Spacer(minLength: 60)

          // Footer
          if viewModel.currentStep == .input {
            footerView
              .padding(.bottom, Spacing.xxl)
          }
        }
        .frame(minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background(Color.tidexBackground)
    .loading(viewModel.isLoading)
    .onTapGesture {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    .onAppear {
      viewModel.onNavigateToLogin = onNavigateToLogin
    }
  }

  // MARK: - Header Section

  private var headerSection: some View {
    VStack(spacing: Spacing.md) {
      // Full wordmark
      Image("TidexWordmark")
        .resizable()
        .scaledToFit()
        .frame(height: 48)

      // Subtitle
      Text(.signupSubtitle)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
  }

  // MARK: - Input Step Content

  @ViewBuilder
  private var inputStepContent: some View {
    VStack(spacing: Spacing.md) {
      // OAuth buttons
      OAuthButtonsView(
        onGoogleTap: { Task { await viewModel.signUpWithGoogle() } },
        onAppleTap: { Task { await viewModel.signUpWithApple() } },
        isLoading: viewModel.isLoading
      )

      // Divider
      dividerView
        .padding(.vertical, Spacing.xs)

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
      HStack(spacing: Spacing.xs) {
        Image(systemName: "envelope")
          .font(.tidexBody)
        Text(.signupEmailOrPhoneReveal)
          .font(.tidexBodyMedium)
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
  }

  // MARK: - Divider

  private var dividerView: some View {
    HStack(spacing: Spacing.md) {
      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)

      Text(.loginSeparator)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)

      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)
    }
  }

  // MARK: - Footer

  private var footerView: some View {
    HStack(spacing: Spacing.xxs) {
      Text(.signupHasAccount)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Button(action: {
        onNavigateToLogin?()
      }) {
        Text(.signupLogin)
          .font(.tidexLabelStrong)
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
    VStack(spacing: Spacing.md) {
      // Name fields side by side
      HStack(spacing: Spacing.sm) {
        // First name
        VStack(spacing: 0) {
          TextField(String(localized: .signupFirstNamePlaceholder), text: $viewModel.firstName)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.msm)
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

        // Last name
        VStack(spacing: 0) {
          TextField(String(localized: .signupLastNamePlaceholder), text: $viewModel.lastName)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .textContentType(.familyName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.msm)
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      }

      // Name error messages
      if let firstNameError = viewModel.fieldErrors.firstName {
        Text(firstNameError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      if let lastNameError = viewModel.fieldErrors.lastName {
        Text(lastNameError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
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
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

      // Error messages
      if let emailError = viewModel.fieldErrors.emailOrPhone {
        Text(emailError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      if let passwordError = viewModel.fieldErrors.password {
        Text(passwordError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      // Password hint
      Text(.signupPasswordHint)
        .font(.tidexFootnote)
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
    VStack(spacing: Spacing.lg) {
      // OTP explanation
      VStack(spacing: Spacing.xs) {
        Text(.otpTitle)
          .font(.tidexTitle)
          .foregroundColor(.tidexTextPrimary)

        Text(String(localized: .otpSubtitle(viewModel.normalizedPhone)))
          .font(.tidexSubheadline)
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
            Text(.signupBackToSignup)
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
  SignupView(viewModel: SignupViewModel())
}
