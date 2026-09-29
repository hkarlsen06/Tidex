import SwiftUI

/// Main login screen view with native iOS styling
/// Supports email/password, phone/OTP, Google, and Apple sign-in
struct LoginView: View {
  @Bindable var viewModel: LoginViewModel
  let currency: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum ScrollTarget {
    case bottom
  }

  // Navigation callbacks
  var onNavigateToSignup: (() -> Void)?
  var onNavigateToResetPassword: (() -> Void)?

  init(
    viewModel: LoginViewModel,
    currency: String = OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency(),
    onNavigateToSignup: (() -> Void)? = nil,
    onNavigateToResetPassword: (() -> Void)? = nil
  ) {
    self.viewModel = viewModel
    self.currency = currency
    self.onNavigateToSignup = onNavigateToSignup
    self.onNavigateToResetPassword = onNavigateToResetPassword
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        scrollContent(geometry: geometry)
      }
    }
    .loading(viewModel.isLoading)
    .onTapGesture {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
  }

  private func scrollContent(geometry: GeometryProxy) -> some View {
    ScrollViewReader { scrollProxy in
      ScrollView {
        VStack(spacing: 0) {
          Spacer(minLength: authTopSpacing)

          entranceColumn(scrollProxy: scrollProxy)
            .frame(maxWidth: 420)
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, bottomPadding(for: geometry))
            .frame(maxWidth: .infinity)

          Color.clear
            .frame(height: 0)
            .id(ScrollTarget.bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }

  private func entranceColumn(scrollProxy: ScrollViewProxy) -> some View {
    VStack(spacing: authSectionSpacing) {
      AuthHeroVisual(
        title: .loginTitle,
        logoSize: 132,
        currency: currency,
        onLogoTap: restartOnboarding
      )
      .padding(.bottom, heroControlsGap)

      messageStack

      VStack(spacing: Spacing.lg) {
        switch viewModel.currentStep {
        case .input:
          inputStepContent(scrollProxy: scrollProxy)

        case .otp:
          PhoneOTPForm(viewModel: viewModel)
        }
      }

      if viewModel.currentStep == .input {
        LoginFooterLinks(
          onCreateAccount: { onNavigateToSignup?() },
          onForgotPassword: { onNavigateToResetPassword?() }
        )
      }
    }
  }

  private var restartOnboarding: () -> Void {
    {
      NotificationCenter.default.post(name: .restartPreAuthOnboarding, object: nil)
    }
  }

  @ViewBuilder
  private var messageStack: some View {
    VStack(spacing: Spacing.sm) {
      if let prompt = viewModel.accountCreationPromptMessage {
        AccountCreationPromptCard(
          message: prompt,
          onDismiss: { viewModel.accountCreationPromptMessage = nil },
          onCreateAccount: { onNavigateToSignup?() }
        )
      }

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
    }
  }

  // MARK: - Input Step Content

  @ViewBuilder
  private func inputStepContent(scrollProxy: ScrollViewProxy) -> some View {
    VStack(spacing: Spacing.md) {
      // OAuth buttons
      OAuthButtonsView(
        onGoogleTap: { Task { await viewModel.signInWithGoogle() } },
        onAppleTap: { Task { await viewModel.signInWithApple() } },
        onPasskeyTap: { Task { await viewModel.signInWithPasskey() } },
        isLoading: viewModel.isLoading
      )

      // Divider
      dividerView
        .padding(.vertical, Spacing.xs)

      // Email/phone form or reveal button
      if viewModel.showEmailForm {
        emailFormSection
      } else {
        revealEmailButton(scrollProxy: scrollProxy)
      }
    }
  }

  // MARK: - Email Form Section

  private var emailFormSection: some View {
    VStack(spacing: Spacing.md) {
      credentialFields

      fieldError(viewModel.fieldErrors.emailOrPhone)
      fieldError(viewModel.fieldErrors.password)

      // Phone hint - password is optional for OTP flow
      if viewModel.inputType == .phone, AuthService.isSMSAvailable {
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

  private var credentialFields: some View {
    VStack(spacing: 0) {
      // Email/Phone field
      NativeTextField(
        placeholder: String(localized: .loginEmailOrPhonePlaceholder),
        text: $viewModel.emailOrPhone,
        keyboardType: .emailAddress,
        textContentType: .emailAddress
      )
      .accessibilityIdentifier("login.email-or-phone")

      Divider()
        .background(Color.tidexSeparator)

      // Password field
      NativeSecureField(
        placeholder: viewModel.inputType == .phone && AuthService.isSMSAvailable
          ? String(localized: .loginPasswordOptionalLabel)
          : String(localized: .loginPasswordPlaceholder),
        text: $viewModel.password,
        onSubmit: {
          Task { await viewModel.signIn() }
        }
      )
    }
    .background(Color.tidexSurfacePrimary)
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
        .stroke(Color.tidexBorderSubtle, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  @ViewBuilder
  private func fieldError(_ message: String?) -> some View {
    if let message {
      Text(message)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexError)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xxs)
        .announcesToVoiceOver(message)
    }
  }

  // MARK: - Reveal Email Button

  private func revealEmailButton(scrollProxy: ScrollViewProxy) -> some View {
    Button {
      MotionTokens.animate(.feedback, reduceMotion: reduceMotion) {
        viewModel.showEmailForm = true
      }
      DispatchQueue.main.async {
        MotionTokens.animate(.feedback, reduceMotion: reduceMotion) {
          scrollProxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "envelope")
          .font(.tidexBodyMedium)
          .accessibilityHidden(true)
        Text(.loginEmailOrPhoneReveal)
          .font(.tidexBodyMedium)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundColor(.tidexTextSecondary)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 50)
      .background(Color.tidexSurfaceSecondary)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
    .accessibilityIdentifier("login.reveal-email")
  }

  // MARK: - Divider

  private var dividerView: some View {
    HStack(spacing: Spacing.md) {
      Rectangle()
        .fill(Color.tidexSeparator)
        .frame(height: 1)

      Text(.loginSeparator)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)

      Rectangle()
        .fill(Color.tidexSeparator)
        .frame(height: 1)
    }
  }

  // MARK: - Footer

  private var authTopSpacing: CGFloat {
    viewModel.showEmailForm || viewModel.currentStep != .input ? Spacing.lg : Spacing.sm
  }

  private var heroControlsGap: CGFloat {
    viewModel.showEmailForm || viewModel.currentStep != .input ? 0 : Spacing.huge + Spacing.xs
  }

  private var authSectionSpacing: CGFloat {
    viewModel.showEmailForm || viewModel.currentStep != .input ? Spacing.lg : Spacing.mlg
  }

  private func bottomPadding(for geometry: GeometryProxy) -> CGFloat {
    max(geometry.safeAreaInsets.bottom + Spacing.xs, Spacing.lg)
  }

}

#Preview {
  LoginView(viewModel: LoginViewModel())
}
