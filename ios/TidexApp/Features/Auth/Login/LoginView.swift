import SwiftUI

/// Main login screen view with native iOS styling
/// Supports email/password, phone/OTP, Google, and Apple sign-in
struct LoginView: View {
  @ObservedObject var viewModel: LoginViewModel
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

        ScrollViewReader { scrollProxy in
          ScrollView {
            VStack(spacing: 0) {
              Spacer(minLength: authTopSpacing)

              VStack(spacing: authSectionSpacing) {
                AuthHeroVisual(
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
                  footerView
                }
              }
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
          .scrollDisabled(!allowsScrolling)
        }
      }
    }
    .loading(viewModel.isLoading)
    .onTapGesture {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
  }

  private var restartOnboarding: () -> Void {
    {
      NotificationCenter.default.post(name: .restartPreAuthOnboarding, object: nil)
    }
  }

  private var allowsScrolling: Bool {
    viewModel.showEmailForm || viewModel.currentStep != .input
  }

  @ViewBuilder
  private var messageStack: some View {
    VStack(spacing: Spacing.sm) {
      if let prompt = viewModel.accountCreationPromptMessage {
        accountCreationPromptCard(message: prompt)
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
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
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

  private func accountCreationPromptCard(message: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      HStack(alignment: .top, spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.tidexError)
          .font(.tidexBody)

        Text(message)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)

        Spacer()

        Button(action: {
          viewModel.accountCreationPromptMessage = nil
        }) {
          Image(systemName: "xmark")
            .foregroundColor(.tidexTextMuted)
            .font(.tidexCaptionStrong)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "screenshotShare.dismiss")))
      }

      PrimaryButton(
        title: String(localized: .loginCreateAccount),
        action: {
          onNavigateToSignup?()
        }
      )
    }
    .padding(Spacing.md)
    .background(Color.tidexError.opacity(0.15))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.md)
        .stroke(Color.tidexError.opacity(0.3), lineWidth: 1)
    )
    .cornerRadius(CornerRadius.md)
  }

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
        Text(.loginEmailOrPhoneReveal)
          .font(.tidexBodyMedium)
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color.tidexSurfaceSecondary)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
  }

  // MARK: - Divider

  private var dividerView: some View {
    HStack(spacing: Spacing.md) {
      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.9))
        .frame(height: 1)

      Text(.loginSeparator)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)

      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.9))
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

  private var footerView: some View {
    HStack(spacing: 0) {
      footerLink(title: Text(.loginCreateAccount)) {
        onNavigateToSignup?()
      }

      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.9))
        .frame(width: 1, height: 18)

      footerLink(title: Text(.loginForgotPassword)) {
        onNavigateToResetPassword?()
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func footerLink(title: Text, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      title
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
        .lineLimit(1)
        .minimumScaleFactor(0.86)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Shared Auth Hero Visual

struct AuthHeroVisual: View {
  let logoSize: CGFloat
  let currency: String
  var onLogoTap: (() -> Void)?

  var body: some View {
    VStack(spacing: Spacing.xxs) {
      logoSection
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)

      ghostedPaycheckPreview
        .padding(.top, -Spacing.huge)
        .offset(y: -Spacing.md)
    }
  }

  @ViewBuilder
  private var logoSection: some View {
    let content = ZStack {
      RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous)
        .fill(
          RadialGradient(
            gradient: Gradient(colors: [
              Color.tidexBlue.opacity(0.08),
              Color.tidexBlue.opacity(0.02),
              Color.clear,
            ]),
            center: .center,
            startRadius: 20,
            endRadius: 100
          )
        )
        .frame(width: 180, height: 180)

      Image("TidexLogo")
        .resizable()
        .scaledToFit()
        .frame(width: logoSize, height: logoSize)
    }

    if let onLogoTap {
      content
        .onTapGesture(perform: onLogoTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(.authRestartPreAuthOnboarding))
    } else {
      content
        .accessibilityHidden(true)
    }
  }

  private var ghostedAmountText: String {
    let hourlyWage = OnboardingCurrencyResolver.defaultHourlyWage(for: currency)
    let estimatedMonthlyHours = 162.0
    let estimatedNet = hourlyWage * estimatedMonthlyHours * 0.8
    return CurrencyConfig.format(estimatedNet, currency: currency)
  }

  @ViewBuilder
  private var ghostedPaycheckPreview: some View {
    let card = ZStack {
      VStack(spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(heroAccentGradient(opacity: 0.55))
          .frame(width: 80, height: 8)

        Spacer().frame(height: 4)

        Text(ghostedAmountText)
          .font(.tidexAmountLarge)
          .foregroundStyle(heroAccentGradient(opacity: 0.55))

        Spacer().frame(height: 8)

        HStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 80, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 55, height: 6)
        }

        HStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 65, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 50, height: 6)
        }

        HStack {
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 90, height: 6)
          Spacer()
          RoundedRectangle(cornerRadius: 3)
            .fill(Color.tidexTextSecondary.opacity(0.7))
            .frame(width: 60, height: 6)
        }
      }
      .padding(.horizontal, Spacing.lg)
      .padding(.vertical, Spacing.mlg)
      .frame(width: 280)
      .background(heroCardBackground)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
          .stroke(heroBorderGradient, lineWidth: 1)
      )

      LinearGradient(
        gradient: Gradient(stops: [
          .init(color: Color.tidexBackground, location: 0.0),
          .init(color: Color.tidexBackground.opacity(0.85), location: 0.3),
          .init(color: Color.tidexBackground.opacity(0.4), location: 0.7),
          .init(color: Color.clear, location: 1.0),
        ]),
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(width: 280, height: 180)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .accessibilityHidden(true)
    }
    .opacity(0.9)
    .blur(radius: 0.5)

    if let onLogoTap {
      card
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
        .onTapGesture(perform: onLogoTap)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(.authRestartPreAuthOnboarding))
    } else {
      card.accessibilityHidden(true)
    }
  }

  private var heroCardBackground: some View {
    ZStack {
      Color.tidexSurfacePrimary

      LinearGradient(
        colors: [
          Color.logoGradientColors[0].opacity(0.08),
          Color.clear,
          Color.logoGradientColors[2].opacity(0.06),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }

  private func heroAccentGradient(opacity: Double = 1) -> LinearGradient {
    LinearGradient(
      colors: [
        Color.logoGradientColors[0].opacity(opacity),
        Color.logoGradientColors[1].opacity(opacity),
        Color.logoGradientColors[2].opacity(opacity),
      ],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private var heroBorderGradient: LinearGradient {
    LinearGradient(
      colors: [
        Color.logoGradientColors[0].opacity(0.28),
        Color.tidexBorder.opacity(0.65),
        Color.logoGradientColors[2].opacity(0.28),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .motionAnimation(.affordance, value: configuration.isPressed, reduceMotion: reduceMotion)
  }
}

#Preview {
  LoginView(viewModel: LoginViewModel())
}
