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
              PhoneOTPForm(viewModel: viewModel)
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
      Text(.loginSubtitle)
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
        onGoogleTap: { Task { await viewModel.signInWithGoogle() } },
        onAppleTap: { Task { await viewModel.signInWithApple() } },
        isLoading: viewModel.isLoading
      )

      // Divider
      dividerView
        .padding(.vertical, Spacing.xs)

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
    VStack(spacing: Spacing.md) {
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
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

      // Error messages
      if let emailError = viewModel.fieldErrors.emailOrPhone {
        Text(emailError)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      if let passwordError = viewModel.fieldErrors.password {
        Text(passwordError)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      // Forgot password link (only for email login)
      if viewModel.inputType == .email {
        HStack {
          Spacer()
          Button(action: {
            onNavigateToResetPassword?()
          }) {
            Text(.loginForgotPassword)
              .font(.tidexLabelStrong)
              .foregroundColor(.tidexBlue)
          }
          .buttonStyle(.plain)
        }
      }

      // Phone hint - password is optional for OTP flow
      if viewModel.inputType == .phone {
        Text(.loginPhonePasswordHint)
          .font(.tidexCaptionRegular)
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
      HStack(spacing: Spacing.xs) {
        Image(systemName: "envelope")
          .font(.tidexBodyMedium)
        Text(.loginEmailOrPhoneReveal)
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
      Text(.loginNoAccount)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)

      Button(action: {
        onNavigateToSignup?()
      }) {
        Text(.loginCreateAccount)
          .font(.tidexLabelStrong)
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
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .keyboardType(keyboardType)
      .textContentType(textContentType)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .focused($isFocused)
      .padding(.horizontal, Spacing.contentHorizontal)
      .padding(.vertical, Spacing.sm)
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
    HStack(spacing: Spacing.sm) {
      if isSecure {
        SecureField(placeholder, text: $text)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .textContentType(.password)
          .focused($isFocused)
          .onSubmit {
            onSubmit?()
          }
      } else {
        TextField(placeholder, text: $text)
          .font(.tidexBody)
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
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextMuted)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, Spacing.contentHorizontal)
    .padding(.vertical, Spacing.sm)
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
