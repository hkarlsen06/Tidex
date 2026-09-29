import SwiftUI

/// Reset password screen with native iOS styling
/// Step 1: Enter email/phone -> Step 2: OTP verification (phone only) -> Step 3: New password
internal struct ResetPasswordView: View {  // swiftlint:disable:this type_body_length
  @State private var viewModel: ResetPasswordViewModel
  @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 36
  @ScaledMetric(relativeTo: .title) private var successIconSize: CGFloat = 48
  var onNavigateToLogin: (() -> Void)?

  init(
    presentationMode: ResetPasswordViewModel.PresentationMode = .standard,
    onNavigateToLogin: (() -> Void)? = nil
  ) {
    _viewModel = State(
      wrappedValue: ResetPasswordViewModel(presentationMode: presentationMode)
    )
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
              otpStepContent

            case .newPassword:
              newPasswordStepContent

            case .success:
              successStepContent
            }
          }
          .padding(.horizontal, Spacing.lg)

          Spacer(minLength: 60)

          // Footer - back to login link
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
      // Key icon for reset password
      ZStack {
        Circle()
          .fill(Color.tidexBlue.opacity(0.1))
          .frame(width: iconSize * 2.2, height: iconSize * 2.2)

        Image(systemName: "key.fill")
          .font(.system(size: iconSize))
          .foregroundColor(.tidexBlueText)
          .accessibilityHidden(true)
      }

      // Title
      Text("Tidex")
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)
    }
  }

  // MARK: - Input Step

  private var inputStepContent: some View {
    VStack(spacing: Spacing.lg) {
      // Instructions
      VStack(spacing: Spacing.xs) {
        Text(.resetPasswordTitle)
          .font(.tidexTitle)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text(.resetPasswordSubtitle)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      VStack(spacing: Spacing.md) {
        // Email/Phone field in grouped style
        VStack(spacing: 0) {
          NativeTextField(
            placeholder: String(localized: .resetPasswordEmailOrPhonePlaceholder),
            text: $viewModel.emailOrPhone,
            keyboardType: .emailAddress,
            textContentType: .emailAddress
          )
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

        // Error message
        if let emailError = viewModel.fieldErrors.emailOrPhone {
          Text(emailError)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xxs)
            .announcesToVoiceOver(emailError)
        }

        // Hint text
        Text(.resetPasswordHint)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
          .frame(maxWidth: .infinity, alignment: .leading)

        // Submit button
        PrimaryButton(
          title: String(localized: .resetPasswordSubmitButton),
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
    VStack(spacing: Spacing.lg) {
      // Instructions
      VStack(spacing: Spacing.xs) {
        Text(.otpTitle)
          .font(.tidexTitle)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text(otpSubtitle)
          .font(.tidexSubheadline)
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
            .foregroundColor(.tidexBlueText)
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)

        backButton
      }
    }
  }

  // MARK: - New Password Step

  private var newPasswordStepContent: some View {
    VStack(spacing: Spacing.lg) {
      // Instructions
      VStack(spacing: Spacing.xs) {
        Text(.resetPasswordNewPasswordTitle)
          .font(.tidexTitle)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text(.resetPasswordNewPasswordSubtitle)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      VStack(spacing: Spacing.md) {
        // Password fields in grouped style
        VStack(spacing: 0) {
          NativeSecureField(
            placeholder: String(localized: .resetPasswordNewPasswordPlaceholder),
            text: $viewModel.newPassword
          )

          Divider()
            .background(Color.tidexSeparator)

          NativeSecureField(
            placeholder: String(localized: .resetPasswordConfirmPasswordPlaceholder),
            text: $viewModel.confirmPassword,
            onSubmit: {
              Task { await viewModel.updatePassword() }
            }
          )
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

        // Error messages
        if let newPasswordError = viewModel.fieldErrors.newPassword {
          Text(newPasswordError)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xxs)
            .announcesToVoiceOver(newPasswordError)
        }

        if let confirmError = viewModel.fieldErrors.confirmPassword {
          Text(confirmError)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xxs)
            .announcesToVoiceOver(confirmError)
        }

        // Password hint
        Text(.resetPasswordPasswordHint)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
          .frame(maxWidth: .infinity, alignment: .leading)

        // Submit button
        PrimaryButton(
          title: String(localized: .resetPasswordUpdatePasswordButton),
          action: {
            Task { await viewModel.updatePassword() }
          },
          isLoading: viewModel.isLoading
        )

        if !viewModel.isRecoveryMode {
          backButton
        }
      }
    }
  }

  // MARK: - Success Step

  private var successStepContent: some View {
    VStack(spacing: Spacing.lg) {
      // Success icon
      ZStack {
        Circle()
          .fill(Color.tidexSuccess.opacity(0.1))
          .frame(width: iconSize * 2.2, height: iconSize * 2.2)

        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: successIconSize))
          .foregroundColor(.tidexSuccess)
          .accessibilityHidden(true)
      }

      // Instructions
      VStack(spacing: Spacing.xs) {
        Text(.resetPasswordSuccessTitle)
          .font(.tidexTitle)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)

        Text(successMessage)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      // Back to login button
      PrimaryButton(
        title: String(localized: .resetPasswordBackToLogin),
        action: {
          Task { await viewModel.handleSuccessAction() }
        }
      )
    }
  }

  private var successMessage: String {
    if viewModel.inputType == .email {
      return String(localized: .resetPasswordSuccessEmailInstructions)
    }
    return String(localized: .resetPasswordSuccessPasswordUpdatedInstructions)
  }

  // MARK: - Back Button

  private var backButton: some View {
    Button(action: {
      viewModel.goBack()
    }) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "chevron.left")
          .font(.tidexCaption)
          .accessibilityHidden(true)
        Text(.commonBack)
          .font(.tidexSubheadline)
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Footer

  private var footerView: some View {
    Button(action: {
      onNavigateToLogin?()
    }) {
      HStack(spacing: Spacing.xxs) {
        Image(systemName: "chevron.left")
          .font(.tidexCaption)
          .accessibilityHidden(true)
        Text(.resetPasswordBackToLogin)
          .font(.tidexSubheadline)
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var otpSubtitle: String {
    if viewModel.inputType == .email {
      return viewModel.successMessage ?? String(localized: .resetPasswordSuccessEmailSent)
    }

    return String(localized: .otpSubtitle(viewModel.normalizedPhone))
  }
}

#Preview {
  ResetPasswordView()
}
