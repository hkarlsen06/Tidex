import SwiftUI

/// Main signup screen view with native iOS styling
/// Supports email/password, Google, and Apple sign-up
struct SignupView: View {
  @Bindable var viewModel: SignupViewModel
  let currency: String
  var onNavigateToLogin: (() -> Void)?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasPlayedEntrance = false

  private enum ScrollTarget {
    case bottom
  }

  init(
    viewModel: SignupViewModel,
    currency: String = OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency(),
    onNavigateToLogin: (() -> Void)? = nil
  ) {
    self.viewModel = viewModel
    self.currency = currency
    self.onNavigateToLogin = onNavigateToLogin
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
    .onAppear {
      viewModel.onNavigateToLogin = onNavigateToLogin
      runEntranceAnimationIfNeeded()
      OnboardingFunnelRecorder.shared.recordPreAuth("signup_screen")
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
        title: .signupTitle,
        logoSize: 132,
        currency: currency,
        subtitle: .signupSubtitle,
        onLogoTap: restartOnboarding
      )
      .padding(.bottom, heroControlsGap)
      .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.00)

      messageStack
        .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.035)

      inputStepContent(scrollProxy: scrollProxy)
        .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.07)

      footerView
        .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.105)
    }
  }

  // MARK: - Header Section

  private var restartOnboarding: () -> Void {
    {
      NotificationCenter.default.post(name: .restartPreAuthOnboarding, object: nil)
    }
  }

  private func runEntranceAnimationIfNeeded() {
    guard !hasPlayedEntrance else { return }
    guard !reduceMotion else {
      hasPlayedEntrance = true
      return
    }

    DispatchQueue.main.async {
      hasPlayedEntrance = true
    }
  }

  @ViewBuilder
  private var messageStack: some View {
    VStack(spacing: Spacing.sm) {
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
    switch viewModel.step {
    case .form:
      formStepContent(scrollProxy: scrollProxy)

    case .verifyEmail:
      EmailVerificationForm(viewModel: viewModel)
    }
  }

  private func formStepContent(scrollProxy: ScrollViewProxy) -> some View {
    VStack(spacing: Spacing.md) {
      OAuthButtonsView(
        onGoogleTap: { Task { await viewModel.signUpWithGoogle() } },
        onAppleTap: { Task { await viewModel.signUpWithApple() } },
        isLoading: viewModel.isLoading
      )

      dividerView
        .padding(.vertical, Spacing.xs)

      if viewModel.showEmailForm {
        SignupForm(viewModel: viewModel)
      } else {
        revealEmailButton(scrollProxy: scrollProxy)
      }

      // Below every signup option, so it covers Apple, Google and email alike.
      TermsAgreementView()
        .padding(.top, Spacing.xxs)
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
          .font(.tidexBody)
          .accessibilityHidden(true)
        Text(.signupEmailReveal)
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
    viewModel.showEmailForm ? Spacing.lg : Spacing.sm
  }

  /// Smaller than on login because the subtitle under the title takes that room, so the
  /// screen still fits without scrolling.
  private var heroControlsGap: CGFloat {
    viewModel.showEmailForm ? 0 : Spacing.xxxl
  }

  private var authSectionSpacing: CGFloat {
    viewModel.showEmailForm ? Spacing.lg : Spacing.mlg
  }

  private func bottomPadding(for geometry: GeometryProxy) -> CGFloat {
    max(geometry.safeAreaInsets.bottom + Spacing.xs, Spacing.lg)
  }

  private var footerView: some View {
    Button(action: {
      onNavigateToLogin?()
    }) {
      Text(.signupLogin)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlueText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Spacing.xxs)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct SignupEntranceStepModifier: ViewModifier {
  let isVisible: Bool
  let delay: TimeInterval

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .opacity(isVisible ? 1 : 0)
      .offset(y: isVisible ? 0 : 22)
      .animation(
        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.86).delay(delay),
        value: isVisible
      )
  }
}

extension View {
  fileprivate func signupEntranceStep(isVisible: Bool, delay: TimeInterval) -> some View {
    modifier(SignupEntranceStepModifier(isVisible: isVisible, delay: delay))
  }
}

// MARK: - Signup Form

/// Email, password, and name form for signup with native iOS styling
struct SignupForm: View {
  @Bindable var viewModel: SignupViewModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// The name fields share a row and stack when large text would squeeze them.
  private var nameFieldsLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.sm))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
  }

  var body: some View {
    VStack(spacing: Spacing.md) {
      nameFieldsLayout {
        nameField(
          placeholder: String(localized: .signupFirstNamePlaceholder),
          text: $viewModel.firstName,
          contentType: .givenName
        )
        nameField(
          placeholder: String(localized: .signupLastNamePlaceholder),
          text: $viewModel.lastName,
          contentType: .familyName
        )
      }

      fieldError(viewModel.fieldErrors.firstName)
      fieldError(viewModel.fieldErrors.lastName)

      credentialFields

      fieldError(viewModel.fieldErrors.emailOrPhone)
      fieldError(viewModel.fieldErrors.password)

      PrimaryButton(
        title: String(localized: .signupSubmitButton),
        action: {
          Task { await viewModel.signUp() }
        },
        isLoading: viewModel.isLoading
      )
    }
  }

  private var credentialFields: some View {
    VStack(spacing: 0) {
      NativeTextField(
        placeholder: String(localized: .signupEmailPlaceholder),
        text: $viewModel.emailOrPhone,
        keyboardType: .emailAddress,
        textContentType: .emailAddress
      )

      Divider()
        .background(Color.tidexSeparator)

      NativeSecureField(
        placeholder: String(localized: .signupPasswordPlaceholder),
        text: $viewModel.password,
        onSubmit: {
          Task { await viewModel.signUp() }
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

  private func nameField(
    placeholder: String,
    text: Binding<String>,
    contentType: UITextContentType
  ) -> some View {
    VStack(spacing: 0) {
      TextField(placeholder, text: text)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
        .textContentType(contentType)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.msm)
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
        .font(.tidexFootnote)
        .foregroundColor(.tidexError)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.xxs)
        .announcesToVoiceOver(message)
    }
  }
}

#Preview {
  SignupView(viewModel: SignupViewModel())
}
